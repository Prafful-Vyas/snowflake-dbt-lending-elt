-- Raw layer: S3 landing -> Snowflake via storage integration + auto-ingest Snowpipe.
-- Run as ACCOUNTADMIN / SYSADMIN once per environment (dbt does not manage these).

USE ROLE ACCOUNTADMIN;

-- IAM trust is set up on the AWS side with the STORAGE_AWS_IAM_USER_ARN and
-- STORAGE_AWS_EXTERNAL_ID returned by DESC INTEGRATION (no access keys stored here).
CREATE STORAGE INTEGRATION IF NOT EXISTS s3_lending_landing
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/snowflake-lending-landing'
  STORAGE_ALLOWED_LOCATIONS = ('s3://bank-lending-landing/');

GRANT USAGE ON INTEGRATION s3_lending_landing TO ROLE SYSADMIN;

USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS RAW.LENDING;
USE SCHEMA RAW.LENDING;

CREATE FILE FORMAT IF NOT EXISTS ff_parquet TYPE = PARQUET USE_LOGICAL_TYPE = TRUE;
CREATE FILE FORMAT IF NOT EXISTS ff_csv
  TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL') EMPTY_FIELD_AS_NULL = TRUE ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE;

CREATE STAGE IF NOT EXISTS landing
  STORAGE_INTEGRATION = s3_lending_landing
  URL = 's3://bank-lending-landing/'
  FILE_FORMAT = ff_parquet;

-- Raw tables keep source columns plus load metadata. Typed conversion happens in
-- dbt staging, so a source type change never blocks ingestion.
CREATE TABLE IF NOT EXISTS raw_loan_transactions (
  txn_id STRING, facility_id STRING, txn_type STRING, value_date STRING,
  amount STRING, currency STRING,
  loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), _file STRING, _file_row NUMBER
);
CREATE TABLE IF NOT EXISTS raw_facilities (
  facility_id STRING, counterparty_id STRING, facility_type STRING, currency STRING,
  committed_limit STRING, start_date STRING, maturity_date STRING, margin_bps STRING,
  loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
CREATE TABLE IF NOT EXISTS raw_counterparties (
  counterparty_id STRING, legal_name STRING, sector STRING, country STRING,
  internal_rating STRING, tax_id STRING, updated_at STRING,
  loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
CREATE TABLE IF NOT EXISTS raw_fx_rates (
  rate_date STRING, from_currency STRING, to_currency STRING, rate STRING,
  loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Transactions arrive as Parquet, continuously. S3 event notifications go to the pipe's SQS queue.
CREATE PIPE IF NOT EXISTS pipe_loan_transactions AUTO_INGEST = TRUE AS
  COPY INTO raw_loan_transactions (txn_id, facility_id, txn_type, value_date, amount, currency, _file, _file_row)
  FROM (
    SELECT $1:txn_id, $1:facility_id, $1:txn_type, $1:value_date, $1:amount, $1:currency,
           METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
    FROM @landing/loan_transactions/
  )
  FILE_FORMAT = (FORMAT_NAME = ff_parquet)
  ON_ERROR = 'SKIP_FILE';

-- Reference data is a daily CSV drop and is bulk-loaded with COPY (idempotent:
-- Snowflake's load metadata skips files that were already loaded).
-- COPY INTO raw_counterparties (counterparty_id, legal_name, sector, country, internal_rating, tax_id, updated_at)
--   FROM @landing/counterparties/ FILE_FORMAT = (FORMAT_NAME = ff_csv) ON_ERROR = 'ABORT_STATEMENT';

-- Ops checks:
-- SELECT SYSTEM$PIPE_STATUS('RAW.LENDING.PIPE_LOAN_TRANSACTIONS');
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(TABLE_NAME => 'RAW_LOAN_TRANSACTIONS',
--          START_TIME => DATEADD(hour, -24, CURRENT_TIMESTAMP())));

-- 1) Publish the exposure mart as a Snowflake-managed Iceberg table on S3, so
--    Athena/Spark consumers read the same data without a copy.
-- 2) Snowflake Tasks: an in-platform alternative to Airflow for the freshness and
--    volume checks, so they still run if the orchestrator is down.

USE ROLE ACCOUNTADMIN;
CREATE EXTERNAL VOLUME IF NOT EXISTS ev_lending_iceberg
  STORAGE_LOCATIONS = ((
    NAME = 'lending-iceberg-eu-west-2'
    STORAGE_PROVIDER = 'S3'
    STORAGE_BASE_URL = 's3://bank-lending-iceberg/'
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/snowflake-lending-iceberg'
  ));
GRANT USAGE ON EXTERNAL VOLUME ev_lending_iceberg TO ROLE TRANSFORMER;

USE ROLE TRANSFORMER;
CREATE SCHEMA IF NOT EXISTS LENDING.SHARED;
CREATE ICEBERG TABLE IF NOT EXISTS LENDING.SHARED.exposure_by_sector_rating (
  month_end DATE, sector STRING, internal_rating STRING, facilities NUMBER, counterparties NUMBER,
  drawn_gbp NUMBER(38, 2), committed_gbp NUMBER(38, 2), utilisation_pct NUMBER(9, 4)
)
  CATALOG = 'SNOWFLAKE'
  EXTERNAL_VOLUME = 'ev_lending_iceberg'
  BASE_LOCATION = 'exposure_by_sector_rating/';

CREATE SCHEMA IF NOT EXISTS LENDING.OPS;
CREATE TABLE IF NOT EXISTS LENDING.OPS.data_checks (
  checked_at TIMESTAMP_NTZ, check_name STRING, observed NUMBER, threshold NUMBER, passed BOOLEAN
);

-- Root task: hourly freshness of the transaction feed (serverless compute).
CREATE OR REPLACE TASK LENDING.OPS.t_check_freshness
  SCHEDULE = 'USING CRON 15 * * * * UTC'
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
AS
  INSERT INTO LENDING.OPS.data_checks
  SELECT CURRENT_TIMESTAMP(), 'raw_loan_transactions_hours_since_load',
         DATEDIFF(hour, MAX(loaded_at), CURRENT_TIMESTAMP()), 26,
         DATEDIFF(hour, MAX(loaded_at), CURRENT_TIMESTAMP()) <= 26
  FROM RAW.LENDING.raw_loan_transactions;

-- Child task: after the hourly check, refresh the Iceberg copy if the mart changed.
CREATE OR REPLACE TASK LENDING.OPS.t_publish_iceberg
  AFTER LENDING.OPS.t_check_freshness
AS
  INSERT OVERWRITE INTO LENDING.SHARED.exposure_by_sector_rating
  SELECT * FROM LENDING.MARTS.MART_EXPOSURE_BY_SECTOR_RATING;

ALTER TASK LENDING.OPS.t_publish_iceberg RESUME;
ALTER TASK LENDING.OPS.t_check_freshness RESUME;

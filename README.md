# Wholesale Lending ELT on Snowflake + dbt

An ELT pipeline for wholesale-lending exposure reporting: **S3 → Snowpipe → Snowflake
RAW → dbt (staging → intermediate → star-schema marts) → Iceberg share**. It is
orchestrated by **Airflow** (with an **Autosys** equivalent and **Snowflake Tasks**
for in-platform checks) and deployed with **GitHub Actions** environment promotion.
The whole dbt project also builds and tests on **DuckDB**, so development and every
pull request need no warehouse.

```
 S3 landing ──(storage integration, auto-ingest Snowpipe / COPY)──► RAW.LENDING (all STRING + load metadata)
                                                                          │ dbt sources (+ freshness SLAs)
                                                                          ▼
   staging (views): typing, trimming, de-dup latest load ── 13 generic tests
        │
   intermediate (views): FX → GBP, date-spine daily balance roll-forward
        │
   snapshots: counterparties SCD2 (rating / sector changes)
        │
   marts: dim_counterparty (SCD2, point-in-time) · dim_facility · dim_date
          fct_loan_transactions (incremental MERGE, 3-day late-arrival lookback)
          fct_facility_balance_daily (incremental periodic snapshot)
          mart_exposure_by_sector_rating (month-end, rating as at month end)
        │                                        singular tests: balance within limit,
        ▼                                        fact ↔ staging reconciliation, mart ↔ balances,
   LENDING.SHARED Iceberg table (Athena/Spark)   one current version per counterparty
```

See [docs/data_model.md](docs/data_model.md) for the conceptual, logical and physical model.

## What's in the repo

| Path | Purpose |
|---|---|
| `models/`, `snapshots/`, `tests/`, `macros/` | dbt project: 12 models, 1 snapshot, 34 tests. Cross-database macros (`dbt.date_spine`, `dbt.dateadd`, `dbt.datediff`, `dbt.last_day`) plus an `incremental_strategy()` macro (MERGE on Snowflake, delete+insert on DuckDB) keep the SQL portable. |
| `snowflake/01_ingest_s3_snowpipe.sql` | Storage integration (IAM role, no keys), external stage, file formats, raw tables, auto-ingest pipe with file metadata, COPY for reference data, ops queries |
| `snowflake/02_governance.sql` | Role hierarchy (LOADER / TRANSFORMER / REPORTER / CREDIT_RISK), warehouses, a masking policy on tax IDs, a row access policy by country entitlement |
| `snowflake/03_iceberg_and_tasks.sql` | External volume + Snowflake-managed Iceberg table, and a serverless Task tree (freshness check → Iceberg publish) |
| `airflow/dags/lending_elt.py` | S3 marker sensor → Snowpipe drained check → `dbt source freshness` → `snapshot` → `build` → `docs` |
| `autosys/lending_elt.jil`, `scripts/run_dbt.sh` | The same flow as an Autosys box. The wrapper uses a lock, logs, retries transient failures only, and never retries test failures. |
| `.github/workflows/ci.yml` | PR: DuckDB build + two-day scenario. Merge to main: Slim CI deploy to Snowflake prod (`state:modified+ --defer`) behind the `prod` environment |
| `scripts/gen_seeds.py` | Synthetic counterparties, facilities, ~10.5k transactions and daily FX (seeds stand in for RAW locally) |

## Run locally

```bash
pip install "dbt-core~=1.9.0" "dbt-duckdb~=1.9.0" duckdb
python scripts/gen_seeds.py
dbt seed  --profiles-dir profiles
dbt build --profiles-dir profiles --exclude resource_type:seed
python scripts/verify_two_day.py      # day 1 full build, day 2 re-rating + incremental
```

## What was verified

On DuckDB with dbt 1.9 (`scripts/verify_two_day.py`, which also runs in CI):

* Day 1: all 12 models, the snapshot and all 34 tests pass. That covers 300
  counterparties, 600 facilities, 10,507 transactions and 292,962 facility-day
  balances.
* Day 2: 10% of counterparties are re-rated, then snapshot and incremental build.
  `dim_counterparty` holds 327 versions (300 current, 27 closed). The re-rate is
  clamped at AAA/CCC, so 3 of the 30 picks did not change. The incremental fact
  stays at 10,507 rows with zero duplicates, and every transaction resolves to a
  counterparty version. All 47 nodes pass.
* The reconciliation tests (fact ↔ staging counts and amounts, and the exposure mart ↔
  daily balances) pass.

**Not run against a real Snowflake account.** The `snowflake/*.sql` scripts, the
Snowflake dbt targets, the Airflow DAG (compile-checked only) and the Autosys JIL are
written to the vendors' documented syntax, but they have not been executed here.

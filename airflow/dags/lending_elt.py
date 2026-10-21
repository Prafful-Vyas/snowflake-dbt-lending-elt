"""Daily wholesale-lending ELT: S3 landing -> Snowflake RAW (Snowpipe) -> dbt -> marts.

    wait for landing marker ─► confirm Snowpipe has drained ─► dbt source freshness
        ─► dbt snapshot ─► dbt build (models + tests, prod target) ─► docs artifacts

dbt runs through the BashOperator against the `prod` target. Key-pair credentials
come from an Airflow connection exported as environment variables (never in the repo).
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta

from airflow.decorators import dag, task
from airflow.operators.bash import BashOperator
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

DBT_DIR = "/opt/airflow/dbt/lending_elt"
DBT = f"cd {DBT_DIR} && dbt --no-use-colors {{cmd}} --profiles-dir profiles --target prod"
DBT_ENV = {
    "SNOWFLAKE_ACCOUNT": "{{ conn.snowflake_lending.extra_dejson.account }}",
    "SNOWFLAKE_USER": "{{ conn.snowflake_lending.login }}",
    "SNOWFLAKE_PRIVATE_KEY_PATH": "/opt/airflow/secrets/snowflake_lending.p8",
}


@dag(
    schedule="30 5 * * 1-5",
    start_date=datetime(2026, 10, 1),
    catchup=False,
    max_active_runs=1,
    default_args={"owner": "lending-data", "retries": 1, "retry_delay": timedelta(minutes=15)},
    tags=["lending", "snowflake", "dbt"],
)
def lending_elt():
    landed = S3KeySensor(
        task_id="landing_complete",
        bucket_key="s3://bank-lending-landing/loan_transactions/{{ ds }}/_SUCCESS",
        mode="reschedule", poke_interval=300, timeout=4 * 3600,
    )

    @task(retries=6, retry_delay=timedelta(minutes=5))
    def snowpipe_drained():
        """Fail (and retry) until the pipe has no pending files, so dbt never builds
        on a half-loaded day."""
        hook = SnowflakeHook(snowflake_conn_id="snowflake_lending")
        status = json.loads(hook.get_first("SELECT SYSTEM$PIPE_STATUS('RAW.LENDING.PIPE_LOAN_TRANSACTIONS')")[0])
        if status.get("executionState") != "RUNNING" or int(status.get("pendingFileCount", 0)) > 0:
            raise RuntimeError(f"pipe not drained: {status}")
        return status

    def dbt(task_id: str, cmd: str, **kw) -> BashOperator:
        return BashOperator(task_id=task_id, bash_command=DBT.format(cmd=cmd), env=DBT_ENV, append_env=True, **kw)

    freshness = dbt("source_freshness", "source freshness")
    snapshot = dbt("snapshot", "snapshot")
    build = dbt("build", "build --exclude resource_type:snapshot --vars '{as_of_date: \"{{ ds }}\"}'")
    docs = dbt("docs", "docs generate", trigger_rule="all_done")

    landed >> snowpipe_drained() >> freshness >> snapshot >> build >> docs


lending_elt()

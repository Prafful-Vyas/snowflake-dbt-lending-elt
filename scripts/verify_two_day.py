"""End-to-end check on DuckDB: full build on day 1, re-rate counterparties, then an
incremental build + snapshot on day 2. Asserts the SCD2 and incremental behaviour.

    python scripts/verify_two_day.py      (used by CI; needs dbt-duckdb)
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent


def sh(*args: str) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)


def dbt(*args: str) -> None:
    sh("dbt", "--no-use-colors", *args, "--profiles-dir", "profiles")


def main() -> int:
    work = Path(tempfile.mkdtemp())
    os.environ["DBT_DUCKDB_PATH"] = str(work / "lending.duckdb")
    original = (ROOT / "seeds" / "raw_counterparties.csv").read_bytes()
    try:
        sh(sys.executable, "scripts/gen_seeds.py")
        dbt("seed")
        dbt("build", "--exclude", "resource_type:seed")
        with duckdb.connect(os.environ["DBT_DUCKDB_PATH"], read_only=True) as c:
            day1_txns = c.execute("select count(*) from marts.fct_loan_transactions").fetchone()[0]

        sh(sys.executable, "scripts/gen_seeds.py", "--rerate", "--out", str(work / "day2"))
        shutil.copy(work / "day2" / "raw_counterparties.csv", ROOT / "seeds" / "raw_counterparties.csv")
        dbt("seed", "--select", "raw_counterparties")
        dbt("build", "--exclude", "resource_type:seed")

        with duckdb.connect(os.environ["DBT_DUCKDB_PATH"], read_only=True) as c:
            q = c.execute
            versions, current, closed = q("select count(*), count(*) filter (where is_current), "
                                          "count(*) filter (where not is_current) from marts.dim_counterparty").fetchone()
            day2_txns = q("select count(*) from marts.fct_loan_transactions").fetchone()[0]
            dupes = q("select count(*) - count(distinct txn_id) from marts.fct_loan_transactions").fetchone()[0]
            unresolved = q("select count(*) from marts.fct_loan_transactions where counterparty_sk is null").fetchone()[0]
        print(f"dim_counterparty: {versions} versions, {current} current, {closed} closed")
        print(f"fct_loan_transactions: day1 {day1_txns}, day2 {day2_txns}, duplicates {dupes}, unresolved {unresolved}")
        assert current == 300 and closed > 0 and versions == current + closed
        assert day2_txns == day1_txns and dupes == 0 and unresolved == 0
        print("OK")
        return 0
    finally:
        (ROOT / "seeds" / "raw_counterparties.csv").write_bytes(original)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())

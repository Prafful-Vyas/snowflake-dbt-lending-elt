"""Generate synthetic wholesale-lending source data as dbt seeds.

    python scripts/gen_seeds.py                # initial load
    python scripts/gen_seeds.py --rerate       # day-2 counterparty file: some ratings/sectors change

In Snowflake these tables arrive from S3 through Snowpipe (snowflake/02_raw_and_pipes.sql).
The seeds stand in for that raw layer so the project builds end to end on DuckDB.
"""

from __future__ import annotations

import argparse
import csv
import random
from datetime import date, timedelta
from pathlib import Path

SECTORS = ["Real Estate", "Manufacturing", "Energy", "Retail", "Technology", "Healthcare",
           "Transport", "Financials", "Utilities", "Telecoms"]
COUNTRIES = ["GB", "US", "DE", "FR", "IN", "AE", "SG", "NL"]
RATINGS = ["AAA", "AA", "A", "BBB", "BB", "B", "CCC"]
CCY = ["GBP", "GBP", "USD", "EUR"]
START, END = date(2025, 1, 1), date(2026, 9, 30)


def write(name: str, rows: list[dict], out: Path) -> None:
    with open(out / f"{name}.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="seeds")
    ap.add_argument("--counterparties", type=int, default=300)
    ap.add_argument("--rerate", action="store_true", help="emit a changed counterparty file only")
    ap.add_argument("--seed", type=int, default=5)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    cps = [{"counterparty_id": f"CP{i:05d}", "legal_name": f"{rng.choice(['Albion', 'Meridian', 'Northgate', 'Sterling', 'Harbour', 'Crown', 'Vertex', 'Orchard'])} "
            f"{rng.choice(['Holdings', 'Group', 'Industries', 'Partners', 'Capital'])} {i}",
            "sector": rng.choice(SECTORS), "country": rng.choice(COUNTRIES),
            "internal_rating": rng.choices(RATINGS, weights=[2, 5, 15, 30, 25, 15, 8])[0],
            "tax_id": f"{rng.randint(10**8, 10**9 - 1)}", "updated_at": "2026-09-30 18:00:00"}
           for i in range(1, args.counterparties + 1)]
    if args.rerate:
        rng2 = random.Random(args.seed + 1)
        for cp in rng2.sample(cps, len(cps) // 10):
            i = RATINGS.index(cp["internal_rating"])
            cp["internal_rating"] = RATINGS[min(len(RATINGS) - 1, max(0, i + rng2.choice([-1, 1, 1])))]
            cp["updated_at"] = "2026-10-01 18:00:00"
        write("raw_counterparties", cps, out)
        print(f"rerated {len(cps) // 10} counterparties")
        return
    write("raw_counterparties", cps, out)

    facilities, txns = [], []
    seq = 0
    for f in range(1, args.counterparties * 2 + 1):
        cp = rng.choice(cps)
        ccy = rng.choice(CCY)
        limit = rng.choice([5, 10, 25, 50, 100, 250]) * 1_000_000
        start = START + timedelta(days=rng.randint(0, 300))
        ftype = rng.choice(["TERM_LOAN", "REVOLVER", "REVOLVER"])
        facilities.append({"facility_id": f"FAC{f:06d}", "counterparty_id": cp["counterparty_id"],
                           "facility_type": ftype, "currency": ccy, "committed_limit": limit,
                           "start_date": start.isoformat(),
                           "maturity_date": (start + timedelta(days=365 * rng.choice([3, 5, 7]))).isoformat(),
                           "margin_bps": rng.choice([150, 175, 200, 250, 300, 375])})
        drawn, d = 0.0, start
        while d <= END:
            if ftype == "TERM_LOAN" and drawn == 0:
                kind, amt = "DRAWDOWN", float(limit)
            elif ftype == "REVOLVER" and rng.random() < 0.5 and drawn < limit:
                kind, amt = "DRAWDOWN", round(rng.uniform(0.05, 0.4) * (limit - drawn), 2)
            elif drawn > 0:
                kind, amt = "REPAYMENT", round(min(drawn, rng.uniform(0.02, 0.3) * drawn), 2)
            else:
                d += timedelta(days=rng.randint(10, 60))
                continue
            if amt <= 0:
                d += timedelta(days=rng.randint(10, 60))
                continue
            drawn = round(drawn + amt if kind == "DRAWDOWN" else drawn - amt, 2)
            seq += 1
            txns.append({"txn_id": f"LT{seq:08d}", "facility_id": f"FAC{f:06d}", "txn_type": kind,
                         "value_date": d.isoformat(), "amount": f"{amt:.2f}", "currency": ccy,
                         "loaded_at": f"{d.isoformat()} 23:00:00"})
            if drawn > 0 and rng.random() < 0.6:
                seq += 1
                txns.append({"txn_id": f"LT{seq:08d}", "facility_id": f"FAC{f:06d}", "txn_type": "INTEREST",
                             "value_date": d.isoformat(), "amount": f"{drawn * 0.06 / 12:.2f}", "currency": ccy,
                             "loaded_at": f"{d.isoformat()} 23:00:00"})
            d += timedelta(days=rng.randint(15, 75))
    write("raw_facilities", facilities, out)
    write("raw_loan_transactions", txns, out)

    rates, d = [], START
    level = {"USD": 0.79, "EUR": 0.85}
    while d <= END:
        for ccy in level:
            level[ccy] = round(level[ccy] * (1 + rng.gauss(0, 0.003)), 6)
            rates.append({"rate_date": d.isoformat(), "from_currency": ccy, "to_currency": "GBP", "rate": level[ccy]})
        d += timedelta(days=1)
    write("raw_fx_rates", rates, out)
    print(f"{len(cps)} counterparties, {len(facilities)} facilities, {len(txns)} transactions, {len(rates)} fx rates")


if __name__ == "__main__":
    main()

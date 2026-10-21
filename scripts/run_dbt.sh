#!/usr/bin/env bash
# Scheduler-friendly dbt wrapper (used by the Autosys jobs in autosys/lending_elt.jil).
#
#   run_dbt.sh <target> <dbt command...>      e.g.  run_dbt.sh prod build --select marts
#
# Retries transient Snowflake/network failures. dbt test failures are never retried:
# re-running cannot fix bad data. Exit codes: 0 ok · 1 dbt failure · 2 usage · 3 lock held.
set -euo pipefail

target="${1:-}"; shift || true
if [[ -z "$target" || $# -eq 0 ]]; then
  echo "usage: $0 <target> <dbt command...>" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${LOG_DIR:-$ROOT/logs}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
mkdir -p "$LOG_DIR"
log="$LOG_DIR/dbt-$(date -u +%Y%m%dT%H%M%SZ)-$1.log"

exec 9>"$LOG_DIR/.dbt-$target.lock"
flock -n 9 || { echo "another dbt run on target $target is in progress" >&2; exit 3; }

cd "$ROOT"
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "$(date -u +%FT%TZ) attempt $attempt/$MAX_ATTEMPTS: dbt $* --target $target" | tee -a "$log"
  if dbt --no-use-colors "$@" --profiles-dir profiles --target "$target" >>"$log" 2>&1; then
    echo "$(date -u +%FT%TZ) success" | tee -a "$log"
    exit 0
  fi
  # Only connection-level errors are worth retrying.
  if grep -Eq "Failure in test|Database Error in (model|test)|Compilation Error" "$log"; then
    echo "$(date -u +%FT%TZ) dbt failed with a data/model error; not retrying (see $log)" | tee -a "$log"
    exit 1
  fi
  sleep $((attempt * 60))
done
echo "$(date -u +%FT%TZ) giving up after $MAX_ATTEMPTS attempts (see $log)" | tee -a "$log"
exit 1

#!/bin/bash
# run_batch.sh - nightly batch sequence with dependency ordering
# Jobs run in order; a dependent job is HELD if its predecessor failed.
#
# PORTABILITY: macOS ships bash 3.2, which has no associative arrays
# (declare -A, bash 4+). Status is tracked in dynamically-named scalars
# via eval so this runs on the stock interpreter without a Homebrew bash.

ROOT="$HOME/batchmon"
LOG="$ROOT/logs/batch_$(date +%Y%m%d).log"
mkdir -p "$ROOT/logs"

JOBS="J100 J200 J300 J400 J500"

set_status() { eval "STATUS_$1=\"\$2\""; }
get_status() { eval "printf '%s' \"\${STATUS_$1:-UNRUN}\""; }

log() { printf '%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG"; }

# run_job <job_id> <depends_on|NONE> <description> <command>
run_job() {
  local job=$1 dep=$2 desc=$3 cmd=$4 depstat

  if [[ "$dep" != NONE ]]; then
    depstat=$(get_status "$dep")
    if [[ "$depstat" != "0" ]]; then
      set_status "$job" "HELD"
      log "$job|HELD|$desc|predecessor $dep status=$depstat"
      return
    fi
  fi

  log "$job|START|$desc|"
  local t0 t1 rc
  t0=$(date +%s)
  eval "$cmd" >> "$LOG.detail" 2>&1
  rc=$?
  t1=$(date +%s)
  set_status "$job" "$rc"

  if (( rc == 0 )); then
    log "$job|END|$desc|rc=0 duration=$((t1-t0))s"
  else
    log "$job|FAIL|$desc|rc=$rc duration=$((t1-t0))s"
  fi
}

log "BATCH|BEGIN|nightly sequence|"

run_job J100 NONE "Verify inbound file arrival" \
  "$ROOT/bin/check_file_arrival.sh"

run_job J200 NONE "Validate transmission control totals" \
  "$ROOT/bin/check_transmission_integrity.sh"

run_job J300 J200 "Load validated sales into staging" \
  "sleep 1"

run_job J400 J300 "Generate DC replenishment extract" \
  "sleep 1"

run_job J500 NONE "Archive prior-day inbound" \
  "sleep 1"

log "BATCH|END|nightly sequence|"

echo
echo "--- SUMMARY ---"
FAILED=0
for j in $JOBS; do
  s=$(get_status "$j")
  case "$s" in
    0)    printf '%-6s COMPLETED\n' "$j" ;;
    HELD) printf '%-6s HELD (dependency not met)\n' "$j"; FAILED=1 ;;
    *)    printf '%-6s FAILED rc=%s\n' "$j" "$s"; FAILED=1 ;;
  esac
done

exit $FAILED
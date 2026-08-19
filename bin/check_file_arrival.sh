#!/bin/bash
# check_file_arrival.sh - verify expected inbound/outbound files arrived on time
# Exit: 0=OK 1=WARNING 2=CRITICAL 3=UNKNOWN
# NOTE: uses BSD date/stat (macOS). Linux needs date -d and stat -c.

ROOT="$HOME/batchmon"
SCHED="$ROOT/schedule.conf"
TODAY=$(date +%Y%m%d)
NOW_MIN=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))

OK=0; WARN=0; CRIT=0
declare -a MSGS

[[ -r "$SCHED" ]] || { echo "FILE_ARRIVAL UNKNOWN - cannot read $SCHED"; exit 3; }

while IFS='|' read -r feed src pattern sla sev minbytes impact; do
  [[ "$feed" =~ ^#.*$ || -z "$feed" ]] && continue

  fname="${pattern/\{DATE\}/$TODAY}"
  if [[ "$src" == dc_* ]]; then
    fpath="$ROOT/outbound/$src/$fname"
  else
    fpath="$ROOT/inbound/$src/$fname"
  fi

  sla_min=$(( 10#${sla:0:2} * 60 + 10#${sla:2:2} ))
  past_sla=$(( NOW_MIN > sla_min ? 1 : 0 ))

  # --- missing ---
  if [[ ! -f "$fpath" ]]; then
    if [[ -f "$ROOT/quarantine/$fname.rej" ]]; then
      MSGS+=("CRITICAL: $feed quarantined - rejected at gateway")
      (( CRIT++ ))
    elif (( past_sla )); then
      MSGS+=("$sev: $feed missing, past ${sla} SLA")
      [[ "$sev" == CRITICAL ]] && (( CRIT++ )) || (( WARN++ ))
    else
      MSGS+=("OK: $feed pending, SLA ${sla} not reached")
      (( OK++ ))
    fi
    continue
  fi

  size=$(stat -f%z "$fpath")

  # --- zero-byte ---
  if (( size == 0 )); then
    MSGS+=("CRITICAL: $feed zero-byte, transfer connected but sent no data")
    (( CRIT++ )); continue
  fi

  # --- undersized ---
  if (( size < minbytes )); then
    MSGS+=("WARNING: $feed only ${size}B, below ${minbytes}B minimum")
    (( WARN++ )); continue
  fi

  # --- stale ---
  age_h=$(( ( $(date +%s) - $(stat -f%m "$fpath") ) / 3600 ))
  if (( age_h > 24 )); then
    MSGS+=("WARNING: $feed timestamp ${age_h}h old, possible stale carryover")
    (( WARN++ )); continue
  fi

  # --- duplicate retransmission ---
  dupes=$(find "$(dirname "$fpath")" -name "${fname%.dat}_*.dat" | wc -l | tr -d ' ')
  if (( dupes > 0 )); then
    MSGS+=("WARNING: $feed has $dupes retransmission(s) present")
    (( WARN++ )); continue
  fi

  MSGS+=("OK: $feed received, ${size}B")
  (( OK++ ))
done < <(cat "$SCHED"; echo)

printf '%s\n' "${MSGS[@]}"

TOTAL=$(( OK + WARN + CRIT ))
if (( CRIT > 0 )); then
  echo "FILE_ARRIVAL CRITICAL - $CRIT critical, $WARN warning, $OK ok | feeds=$TOTAL crit=$CRIT warn=$WARN"
  exit 2
elif (( WARN > 0 )); then
  echo "FILE_ARRIVAL WARNING - $WARN warning, $OK ok | feeds=$TOTAL crit=0 warn=$WARN"
  exit 1
fi
echo "FILE_ARRIVAL OK - all $OK feeds received | feeds=$TOTAL crit=0 warn=0"
exit 0
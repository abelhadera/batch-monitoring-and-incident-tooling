#!/bin/bash
# check_transmission_integrity.sh - validate header/trailer control totals
# Exit: 0=OK 1=WARNING 2=CRITICAL 3=UNKNOWN
# NOTE: BSD-flavored (macOS). File layout:
#   HDR|<type>|<store>|<date>
#   D|<date>|<txn>|<seq>|<amount>
#   TRL|<record_count>|<amount_total>

ROOT="$HOME/batchmon"
SCHED="$ROOT/schedule.conf"
TODAY=$(date +%Y%m%d)

OK=0; WARN=0; CRIT=0; SKIP=0
declare -a MSGS

[[ -r "$SCHED" ]] || { echo "TRANSMISSION_INTEGRITY UNKNOWN - cannot read $SCHED"; exit 3; }

while IFS='|' read -r feed src pattern sla sev minbytes impact; do
  [[ "$feed" =~ ^#.*$ || -z "$feed" ]] && continue

  fname="${pattern/\{DATE\}/$TODAY}"
  if [[ "$src" == dc_* ]]; then
    fpath="$ROOT/outbound/$src/$fname"
  else
    fpath="$ROOT/inbound/$src/$fname"
  fi

  # not our job to report absence - that's check_file_arrival
  [[ -f "$fpath" && -s "$fpath" ]] || { (( SKIP++ )); continue; }

  hdr=$(head -1 "$fpath")
  trl=$(tail -1 "$fpath")

  if [[ "$hdr" != HDR\|* ]]; then
    MSGS+=("CRITICAL: $feed malformed - no HDR record")
    (( CRIT++ )); continue
  fi
  if [[ "$trl" != TRL\|* ]]; then
    MSGS+=("CRITICAL: $feed truncated - no TRL record, transfer incomplete")
    (( CRIT++ )); continue
  fi

  hdr_date=$(cut -d'|' -f4 <<< "$hdr")
  declared_count=$(cut -d'|' -f2 <<< "$trl")
  declared_amt=$(cut -d'|' -f3 <<< "$trl")

  actual_count=$(grep -c '^D|' "$fpath")
  actual_amt=$(awk -F'|' '$1=="D" {s+=$5} END {printf "%.2f", s+0}' "$fpath")

  declared_count=$(( 10#$declared_count ))

  if [[ "$hdr_date" != "$TODAY" ]]; then
    MSGS+=("WARNING: $feed header date $hdr_date, expected $TODAY")
    (( WARN++ )); continue
  fi

  if (( actual_count != declared_count )); then
    diff=$(( declared_count - actual_count ))
    MSGS+=("CRITICAL: $feed record count mismatch - trailer declares $declared_count, file has $actual_count (short $diff)")
    (( CRIT++ )); continue
  fi

  if [[ "$actual_amt" != "$declared_amt" ]]; then
    MSGS+=("CRITICAL: $feed control total mismatch - trailer $declared_amt, computed $actual_amt")
    (( CRIT++ )); continue
  fi

  MSGS+=("OK: $feed integrity verified, $actual_count records, total $actual_amt")
  (( OK++ ))
done < <(cat "$SCHED"; echo)

printf '%s\n' "${MSGS[@]}"

TOTAL=$(( OK + WARN + CRIT ))
if (( CRIT > 0 )); then
  echo "TRANSMISSION_INTEGRITY CRITICAL - $CRIT failed validation, $WARN warning, $OK ok ($SKIP not present) | checked=$TOTAL crit=$CRIT warn=$WARN"
  exit 2
elif (( WARN > 0 )); then
  echo "TRANSMISSION_INTEGRITY WARNING - $WARN warning, $OK ok ($SKIP not present) | checked=$TOTAL crit=0 warn=$WARN"
  exit 1
fi
echo "TRANSMISSION_INTEGRITY OK - all $OK validated ($SKIP not present) | checked=$TOTAL crit=0 warn=0"
exit 0
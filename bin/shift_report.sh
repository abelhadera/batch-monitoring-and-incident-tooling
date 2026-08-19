#!/bin/bash
# shift_report.sh - end-of-shift handoff summary
# Summarizes the MOST RECENT batch run plus all open incidents.
# Reads pipe-delimited incidents.psv (quoted CSV proved fragile to parse in shell).

ROOT="$HOME/batchmon"
INC="$ROOT/logs/incidents.psv"
BLOG="$ROOT/logs/batch_$(date +%Y%m%d).log"
NOW=$(date '+%Y-%m-%d %H:%M:%S')

hr() { printf '%s\n' "------------------------------------------------------------"; }

hr
printf 'NIGHTLY OPERATIONS SHIFT REPORT\n'
printf 'Generated: %s\n' "$NOW"
printf 'Operator:  %s\n' "$USER"
hr

printf '\nBATCH JOB SUMMARY (most recent run)\n'
if [[ -f "$BLOG" ]]; then
  start=$(grep -n 'BATCH|BEGIN' "$BLOG" | tail -1 | cut -d: -f1)
  tail -n "+$start" "$BLOG" | awk -F'|' '
    $2 ~ /^J/ && $3=="END"  {ok++;   next}
    $2 ~ /^J/ && $3=="FAIL" {fail++; f=f $2 " "; next}
    $2 ~ /^J/ && $3=="HELD" {held++; h=h $2 " "; next}
    END {
      printf "  Completed: %d\n", ok+0
      printf "  Failed:    %d  %s\n", fail+0, f
      printf "  Held:      %d  %s\n", held+0, h
    }'
else
  printf '  No batch log for today.\n'
fi

printf '\nOPEN INCIDENTS BY TIER\n'
if [[ -f "$INC" ]]; then
  awk -F'|' 'NR>1 && $9=="OPEN" {print $8}' "$INC" \
    | sort | uniq -c | sort -rn \
    | awk '{printf "  %-24s %s\n", $2, $1}'
else
  printf '  No incidents logged.\n'
fi

printf '\nCRITICAL ITEMS REQUIRING ACTION\n'
if [[ -f "$INC" ]]; then
  awk -F'|' 'NR>1 && $5=="CRITICAL" && $9=="OPEN" {
    printf "  [%s] %s\n      Symptom: %s\n      Impact:  %s\n      Route:   %s\n\n", $1, $4, $6, $7, $8
  }' "$INC"
fi

hr
printf 'END OF REPORT\n'
hr
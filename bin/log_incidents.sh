#!/bin/bash
# log_incidents.sh - convert check output into structured incident records
# Appends to logs/incidents.csv. Each non-OK condition becomes one row with
# a stable incident ID, severity, symptom, and the escalation tier the
# runbook assigns to it.

ROOT="$HOME/batchmon"
SCHED="$ROOT/schedule.conf"
INC="$ROOT/logs/incidents.psv"
TS=$(date '+%Y-%m-%d %H:%M:%S')
DATE_ID=$(date '+%Y%m%d')
mkdir -p "$ROOT/logs"

if [[ ! -f "$INC" ]]; then
    echo "incident_id|opened|system|feed|severity|symptom|business_impact|escalation_tier|status" > "$INC"
fi

# business impact lookup from schedule.conf
impact_for() {
  awk -F'|' -v f="$1" '$1==f {print $7}' "$SCHED" | head -1
}

# escalation tier by severity + symptom class
tier_for() {
  case "$1:$2" in
    CRITICAL:*quarantin*)   echo "Tier2-DataQuality" ;;
    CRITICAL:*zero-byte*)   echo "Tier1-StoreSupport" ;;
    CRITICAL:*mismatch*)    echo "Tier2-DataQuality" ;;
    CRITICAL:*truncated*)   echo "Tier2-DataQuality" ;;
    CRITICAL:*missing*)     echo "Tier1-StoreSupport" ;;
    CRITICAL:*)             echo "Tier2-DataQuality" ;;
    WARNING:*retransmis*)   echo "Tier0-OperatorReview" ;;
    WARNING:*stale*)        echo "Tier1-StoreSupport" ;;
    WARNING:*)              echo "Tier0-OperatorReview" ;;
    *)                      echo "Tier0-OperatorReview" ;;
  esac
}

seq_n=$(( $(wc -l < "$INC") - 1 ))

record() {
  local system=$1 sev=$2 line=$3 feed impact tier id
  feed=$(awk '{print $2}' <<< "$line")
  impact=$(impact_for "$feed")
  [[ -z "$impact" ]] && impact="Not classified"
  tier=$(tier_for "$sev" "$line")
  seq_n=$(( seq_n + 1 ))
  id=$(printf 'INC-%s-%03d' "$DATE_ID" "$seq_n")

  # strip leading "SEVERITY: FEED " to leave the symptom
  local symptom="${line#*: }"
  symptom="${symptom#* }"
  symptom="${symptom//|/;}"

  printf '%s|%s|%s|%s|%s|%s|%s|%s|OPEN\n' \
    "$id" "$TS" "$system" "$feed" "$sev" "$symptom" "$impact" "$tier" >> "$INC"
  printf '  %s  %-10s %-8s %s\n' "$id" "$feed" "$sev" "$tier"
}

scan() {
  local system=$1 script=$2 out
  out=$("$script")
  while IFS= read -r line; do
    case "$line" in
      CRITICAL:*) record "$system" CRITICAL "$line" ;;
      WARNING:*)  record "$system" WARNING  "$line" ;;
    esac
  done <<< "$out"
}

echo "Scanning for incidents at $TS"
echo
scan FILE_ARRIVAL "$ROOT/bin/check_file_arrival.sh"
scan TRANSMISSION "$ROOT/bin/check_transmission_integrity.sh"
echo
echo "Incident log: $INC"
echo "Open incidents: $(( $(wc -l < "$INC") - 1 ))"
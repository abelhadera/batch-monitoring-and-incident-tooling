#!/bin/bash
# seed_env.sh - build a fake nightly file-transmission environment
set -euo pipefail

ROOT="$HOME/batchmon"
[[ "$ROOT" == "$HOME/batchmon" ]] || { echo "refusing to wipe $ROOT"; exit 1; }

TODAY=$(date +%Y%m%d)
YDAY=$(date -v-1d +%Y%m%d)

rm -rf "$ROOT/inbound" "$ROOT/outbound" "$ROOT/quarantine"
mkdir -p "$ROOT"/inbound/{store_0142,store_0187,store_0203} \
         "$ROOT"/outbound/dc_dallas "$ROOT"/quarantine

# make_file <path> <type> <store> <n_records> [trailer_count_override]
make_file() {
  local path=$1 type=$2 store=$3 n=$4 trailer=${5:-$4}
  local total=0 amt i
  printf 'HDR|%s|%s|%s\n' "$type" "$store" "$TODAY" > "$path"
  for ((i=1; i<=n; i++)); do
    amt=$(( (RANDOM % 9000) + 100 ))
    total=$(( total + amt ))
    printf 'D|%s|%06d|%05d|%d.%02d\n' \
      "$YDAY" $((100000+i)) "$i" $((amt/100)) $((amt%100)) >> "$path"
  done
  printf 'TRL|%010d|%d.%02d\n' "$trailer" $((total/100)) $((total%100)) >> "$path"
}

age() { touch -t "$(date -v-"$2" +%Y%m%d%H%M)" "$1"; }

I="$ROOT/inbound"; O="$ROOT/outbound"

# 1. HEALTHY - arrived on time, control totals match
make_file "$I/store_0142/SALES_0142_$TODAY.dat" SALES 0142 12
age "$I/store_0142/SALES_0142_$TODAY.dat" 4H

# 2. INTEGRITY FAILURE - trailer claims 11 records, file has 8
make_file "$I/store_0142/INV_0142_$TODAY.dat" INV 0142 8 11
age "$I/store_0142/INV_0142_$TODAY.dat" 3H

# 3. ZERO-BYTE - transfer connected but sent nothing
: > "$I/store_0187/SALES_0187_$TODAY.dat"
age "$I/store_0187/SALES_0187_$TODAY.dat" 3H

# 4. DUPLICATE - retransmission landed alongside original
make_file "$I/store_0187/INV_0187_$TODAY.dat" INV 0187 15
make_file "$I/store_0187/INV_0187_${TODAY}_02.dat" INV 0187 15
age "$I/store_0187/INV_0187_$TODAY.dat" 3H

# 5. MISSING - only yesterday's file present
make_file "$I/store_0203/SALES_0203_$YDAY.dat" SALES 0203 9
age "$I/store_0203/SALES_0203_$YDAY.dat" 28H

# 6. STALE - outbound feed two days old
make_file "$O/dc_dallas/RTS_DALLAS_$TODAY.dat" RTS DALLAS 40
age "$O/dc_dallas/RTS_DALLAS_$TODAY.dat" 52H

# 7. QUARANTINED - rejected at the gateway
make_file "$ROOT/quarantine/SALES_0203_$TODAY.dat.rej" SALES 0203 6 6
printf 'REJECT|%s|checksum mismatch on receipt\n' "$TODAY" \
  >> "$ROOT/quarantine/SALES_0203_$TODAY.dat.rej"

echo "Seeded $ROOT at $(date '+%Y-%m-%d %H:%M:%S')"
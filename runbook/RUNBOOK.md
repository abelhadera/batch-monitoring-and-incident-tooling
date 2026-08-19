# Nightly Batch Runbook

Covers alerts from `bin/check_file_arrival.sh` and `bin/check_transmission_integrity.sh`.

## Tiers

| Tier | Who | When |
|---|---|---|
| Tier0 | Operator | You can fix it |
| Tier1 | Store Support | Source has to resend |
| Tier2 | Data Quality | File came in wrong |

---

## File missing past SLA

`CRITICAL: <feed> missing, past <hhmm> SLA`

**Check**
- `ls -la inbound/<store>/`
- `ls -la quarantine/` — it may have been rejected
- Is yesterday's file there?

**Do**
- Yesterday OK, today missing → one-off. Ask for a resend.
- Several days missing → connectivity. Tier1 ticket, include store number.

**Escalate**
- Tier1 now if the feed is CRITICAL.
- 30 min past SLA and still nothing → tell the batch coordinator. J300 can't run.

**Why it matters:** Sales close is late. Replenishment under-orders.

---

## Zero-byte file

`CRITICAL: <feed> zero-byte, transfer connected but sent no data`

**Check**
- `wc -c inbound/<store>/<file>`
- File has a timestamp, so the transfer connected. Not the same as missing.

**Do**
- Don't delete it. Move to `quarantine/`.
- Ask for a resend. Give them the arrival timestamp.

**Escalate**
- Tier1. Say a session connected — that points at the sending job, not the network.

**Why it matters:** Same as missing.

---

## Control total mismatch

`CRITICAL: <feed> record count mismatch` / `control total mismatch`

**Check**
- `head -1` and `tail -1` for HDR and TRL
- `grep -c '^D|' <file>` for the real count
- Short count = truncated. Right count, wrong amount = corrupted field.

**Do**
- **Don't load it.** Backing out bad inventory is worse than waiting. J300 holds on purpose.
- Quarantine it, ask for the whole file again.

**Escalate**
- Tier2. Give them declared count, actual count, difference.

**Why it matters:** Inventory goes stale. Pick lists over-allocate stock that never arrived.

---

## Duplicate file

`WARNING: <feed> has N retransmission(s) present`

**Check**
- `ls -la` both
- Compare the TRL lines

**Do**
- Same trailer → keep the newer one, archive the old. Nothing else needed.
- Different trailer → newer wins, but confirm with the source first.

**Escalate**
- Tier0. Only go Tier1 if trailers differ and nobody can say which is right.

**Why it matters:** Load both and inventory doubles. Load the wrong one and you lose transactions.

---

## Stale timestamp

`WARNING: <feed> timestamp Nh old, possible stale carryover`

**Check**
- `stat -f%m <file>`
- Did today's job run?
- Does the HDR date match today?

**Do**
- Right name, old timestamp usually means the job did nothing and yesterday's file stayed put.
- Worse than a missing file — it looks fine to anything that only checks for presence.

**Escalate**
- Tier1. Call it a silent failure. The job probably exited 0.

**Why it matters:** RTS feed blocks morning outbound staging.

---

## Before you sign off

`check_file_arrival.sh` prints how many feeds it checked. Compare that to the active
lines in `schedule.conf`. If they don't match, something isn't being watched and it
will never alert. That's worse than any single item above.
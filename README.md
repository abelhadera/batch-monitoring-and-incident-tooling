# batchmon

Monitors nightly file transmissions between stores, a DC, and downstream systems.
Checks that expected files arrive on time and that their contents reconcile, runs
the batch sequence in dependency order, logs incidents with escalation routing,
and prints a shift handoff report.

## Layout

    bin/        checks, job runner, reporting
    logs/       batch log + incident log (generated)
    runbook/    what to do for each alert
    schedule.conf   feeds, SLAs, thresholds, business impact

## Run it

    ./bin/seed_env.sh          # build the test environment
    ./bin/run_batch.sh         # run the nightly sequence
    ./bin/log_incidents.sh     # record open incidents
    ./bin/shift_report.sh      # handoff summary

The seed script creates a mix of healthy and broken feeds: on time, zero-byte,
truncated, duplicated, missing, stale, and quarantined.

## Checks

`check_file_arrival.sh` — did the file show up, on time, non-empty, not stale,
not duplicated.

`check_transmission_integrity.sh` — does the trailer's record count and amount
total match the file contents.

Both are Nagios-style: exit 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN.

They stay separate on purpose. A file can arrive clean and still be wrong —
INV_0142 passes the arrival check and fails integrity with three records missing.

## Known limitations

- `date`, `stat`, and `sed -i ''` use BSD syntax. Linux needs `date -d`, `stat -c`, `sed -i`.
- Written for bash 3.2 (what macOS ships). No associative arrays.
- Incidents aren't deduped. Running `log_incidents.sh` twice logs the same open items again.
- No auto-resolve. Incidents stay OPEN until edited by hand.S
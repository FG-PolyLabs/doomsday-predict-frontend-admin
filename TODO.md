# doomsday-predict — Project TODO

Track of open issues, next actions, and in-progress work across all repos.

---

## URGENT — Backfill missing data for 2026-03-25 and 2026-03-26

**Scheduler is fixed as of 2026-03-28.** Root cause was two bugs introduced when recreating the scheduler on 2026-03-24:
1. URI used project ID (`fg-polylabs`) instead of project number (`846376753241`) in the namespace — Cloud Run v1 Knative API requires the number.
2. `doomsday-runner` had `roles/run.invoker` but the v1 endpoint checks `run.executions.create` (requires `roles/run.developer`).

Fixed by updating the scheduler URI and granting `roles/run.developer` on the job. `run.sh schedule-daily` is also updated to set up permissions correctly going forward.

- [x] **Backfill completed 2026-03-28** — execution `doomsday-polymarket-8pjr9` ran successfully
- [x] **Validated 2026-03-28** — 29/33 active market configs have data for 2026-03-25 and 2026-03-26

**4 configs have no data (expected — no active Polymarket events for those dates):**
- `tag: israel / prefix: netanyahu-out`
- `slug: new-stranger-things-episode-released-by-wednesday`
- `tag: us-iran / prefix: us-x-iran-ceasefire`
- `tag: us-iran / prefix: will-the-us-invade-iran`

These are likely stale/expired configs on Polymarket with no active trading — consider deactivating them in `doomsday.markets` to clean up the active list.

- [ ] **Verify tonight's scheduled run** completes (2026-03-29 01:00 UTC)
- [ ] **Review stale market configs** above — deactivate via API if no longer relevant

---

## Open bugs

- [ ] **Drive 403 in doomsday exporter** — post-insert export step logs `warning: post-insert GCS/Drive export failed`. The Drive write was removed from the exporter but the error still surfaces (possibly stale deployment or config). Investigate once the scheduler fix is in.
- [ ] **Unexpected Drive writes in doomsday-polymarket** — similar Drive-related warnings in polymarket job logs. Audit `RunExport()` in the analytics repo to confirm Drive calls are fully removed.

---

## In progress / recently done

- [x] Removed Drive-related code from health-check script and runbook (2026-03-25)
- [x] Added post-deploy validation script and runbook (2026-03-25)
- [x] Added public frontend (`doomsday-predict-frontend`) to the suite
- [x] Created `scripts/job-report.sh` in `doomsday-predict-analytics` — parses Cloud Logging for per-market success/failure from any job execution
- [x] Added default date range (yesterday→today) to admin panel prices page (2026-03-27)
- [x] Added Polymarket links to prices page chart and table (2026-03-27)
- [x] Designed and implemented market theta (time-decay) system (2026-03-28):
  - BigQuery view `fg-polylabs.doomsday.market_theta` using LAG() window functions
  - `theta_export.go` — exports per-event theta JSON to `gs://fg-polylabs-doomsday/theta/`
  - Wired into both `cmd/doomsday/main.go` and `cmd/exporter/main.go`
  - 34 events populated in GCS as of 2026-03-28
- [ ] **Build frontend UI for theta data** — charts showing time-decay curves per event on admin panel

---

## Useful commands (quick reference)

```bash
# Check yesterday's job report
./scripts/job-report.sh                       # from doomsday-predict-analytics/

# Check latest execution regardless of date
./scripts/job-report.sh --latest

# Manually trigger a daily run
./scripts/run.sh daily

# List recent executions
gcloud run jobs executions list --job=doomsday-polymarket --region=us-central1 --project=fg-polylabs

# Check Cloud Scheduler status
gcloud scheduler jobs describe doomsday-daily --project=fg-polylabs --location=us-central1
```

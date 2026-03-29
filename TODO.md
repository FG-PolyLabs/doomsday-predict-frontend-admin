# doomsday-predict — Project TODO

Track of open issues, next actions, and in-progress work across all repos.

---

## Where we left off (2026-03-28 session)

The theta system is fully built and deployed end-to-end. Here is exactly what was done and what to pick up next.

### Completed this session
- [x] Fixed Cloud Scheduler 403 (two bugs: wrong project ID in URI namespace, wrong IAM role)
- [x] Backfilled missing data for 2026-03-25 and 2026-03-26; validated 29/33 configs have data
- [x] Created `scripts/job-report.sh` — checks per-market coverage for any execution
- [x] Created `scripts/validate-backfill.sh` — BQ REST API validation (bq CLI is broken on this machine)
- [x] Admin panel: default date range yesterday→today on Market Prices page
- [x] Admin panel: Polymarket links on chart and table rows in Market Prices page
- [x] BigQuery view `fg-polylabs.doomsday.market_theta` — daily theta via LAG() window function
- [x] `internal/doomsday/theta_export.go` — exports per-event theta JSON to GCS `theta/` prefix
- [x] Wired theta export into `cmd/doomsday/main.go` and `cmd/exporter/main.go`
- [x] Ran exporter (`doomsday-exporter-sb99w`) — 34 events now live at `gs://fg-polylabs-doomsday/theta/`
- [x] Admin panel: new `/theta/` page with days-to-expiry vs theta scatter chart (commit `21df58c`)

### Next up — good starting points for a new session

1. **Verify the 2026-03-29 01:00 UTC scheduled run ran** (it should have by now)
   ```bash
   ./scripts/job-report.sh --latest    # from doomsday-predict-analytics/
   ```

2. **Review 4 stale market configs** — deactivate if no longer active on Polymarket:
   - `tag: israel / prefix: netanyahu-out`
   - `slug: new-stranger-things-episode-released-by-wednesday`
   - `tag: us-iran / prefix: us-x-iran-ceasefire`
   - `tag: us-iran / prefix: will-the-us-invade-iran`
   Use the Markets Tracked admin panel to deactivate, or run:
   ```bash
   # Set active=false via the API
   curl -X PATCH https://doomsday-api-846376753241.us-central1.run.app/api/v1/markets/<id> \
     -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
     -d '{"active": false}'
   ```

3. **Theta UI enhancements** (nice to have, lower priority):
   - Add a second chart on the theta page: x=days_to_expiry, y=yes_price (premium curve)
   - Add ability to overlay multiple events on the same theta chart for comparison
   - Consider adding theta data to the public frontend (`doomsday-predict-frontend`) as a read-only view

4. **Investigate Drive 403 warnings** — these still show in exporter logs. Drive code was removed
   but warnings persist. Run the exporter and check logs:
   ```bash
   gcloud run jobs execute doomsday-exporter --region=us-central1 --project=fg-polylabs --wait
   gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="doomsday-exporter"' \
     --project=fg-polylabs --limit=50 --format="value(textPayload)"
   ```

---

## Open bugs

- [ ] **Drive 403 in doomsday exporter** — post-insert export step logs `warning: post-insert GCS/Drive export failed`. Drive write was removed but error still surfaces. See #4 above.
- [ ] **bq CLI broken on dev machine** — `AttributeError: module 'absl.flags' has no attribute 'FLAGS'`. Use BQ REST API via curl as a workaround (see `validate-backfill.sh`).

---

## Scheduler fix (resolved 2026-03-28, keeping for reference)

Root cause of 403s from Cloud Scheduler:
1. URI used project ID (`fg-polylabs`) instead of project number (`846376753241`) — Cloud Run v1 Knative API requires the number
2. `doomsday-runner` had `roles/run.invoker` but v1 endpoint needs `run.executions.create` (requires `roles/run.developer`)

Fixed in `scripts/run.sh` — `schedule-daily` subcommand now sets both correctly.

**4 configs had no backfill data (expected — no active Polymarket events):**
- `tag: israel / prefix: netanyahu-out`
- `slug: new-stranger-things-episode-released-by-wednesday`
- `tag: us-iran / prefix: us-x-iran-ceasefire`
- `tag: us-iran / prefix: will-the-us-invade-iran`

---

## Useful commands (quick reference)

```bash
# Check yesterday's job report
./scripts/job-report.sh                       # from doomsday-predict-analytics/

# Check latest execution regardless of date
./scripts/job-report.sh --latest

# Manually trigger a daily run
./scripts/run.sh daily

# Manually run the exporter (GCS + theta export)
./scripts/run.sh export                       # from doomsday-predict-analytics/

# List recent executions
gcloud run jobs executions list --job=doomsday-polymarket --region=us-central1 --project=fg-polylabs

# Check Cloud Scheduler status
gcloud scheduler jobs describe doomsday-daily --project=fg-polylabs --location=us-central1

# Spot-check theta GCS output
gcloud storage cat gs://fg-polylabs-doomsday/theta/index.json | python3 -m json.tool | head -40
```

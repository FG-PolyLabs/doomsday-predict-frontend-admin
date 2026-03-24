# Daily Job Health Check Runbook

Run this after the scheduled jobs complete (typically early morning). Work through each step in order — a failure in an earlier step may explain failures downstream.

**GCP project:** `fg-polylabs`
**BigQuery dataset:** `fg-polylabs.doomsday`
**GCS bucket:** `gs://fg-polylabs-doomsday`
**Cloud Run API:** `https://doomsday-api-846376753241.us-central1.run.app`

---

## Step 1 — Daily Exporter

**Purpose:** Exports market snapshots to GCS; commits tracked market lists to GitHub.

**Checks:**
1. Open the [GCS bucket](https://console.cloud.google.com/storage/browser/fg-polylabs-doomsday) and confirm data files were updated today.
2. Open [doomsday-predict-data on GitHub](https://github.com/FG-PolyLabs/doomsday-predict-data) and check recent commits.

**Pass criteria:**
- GCS files show today's date.
- GitHub files may be older — this is expected. The exporter only commits when tracked markets change; data files live exclusively on GCS.

---

## Step 2 — Doomsday Exporter (Cloud Run Job)

**Purpose:** Exports doomsday event data as JSON to GCS (and optionally Drive).

**Checks:**
1. Go to [Cloud Run Jobs](https://console.cloud.google.com/run/jobs?project=fg-polylabs).
2. Find the doomsday exporter job and open the most recent execution.
3. Confirm status is **Succeeded**.
4. Open logs and scan for errors.

**Pass criteria:**
- Execution status: Succeeded.
- No unexpected fatal errors.

**Known issues (do not block validation):**
- `Drive: write <file>.json: googleapi: Error 403: Service Accounts do not have storage quota` — tracked in the backlog below. GCS writes still succeed, so exports are partially functional.

---

## Step 3 — Daily Data Fetch (`doomsday-polymarket`)

**Purpose:** Fetches Polymarket data and writes it into BigQuery.

**Checks:**
1. Go to [Cloud Run Jobs](https://console.cloud.google.com/run/jobs?project=fg-polylabs).
2. Find `doomsday-polymarket` (us-central1) and open the most recent execution.
3. Confirm status is **Succeeded**.
4. Scan logs for errors and warnings. Note any markets that failed to fetch.

**Pass criteria:**
- Execution status: Succeeded.
- Fetch warnings for individual markets are acceptable (closed or delisted markets may not be available).
- No unexpected fatal errors.

**Known issues (do not block validation):**
- Job logs show Drive writes — this feature was believed to be removed. Tracked in the backlog below.
- Recurring fetch warnings for the same markets may indicate those markets should be removed from the tracked list.

---

## Step 4 — BigQuery Data Validation

**Purpose:** Confirm yesterday's Polymarket data was ingested successfully.

**Check:** Run the following in the [BigQuery console](https://console.cloud.google.com/bigquery?project=fg-polylabs):

```sql
SELECT
  DATE(timestamp) AS date,
  COUNT(*)        AS row_count
FROM `fg-polylabs.doomsday.<table_name>`
WHERE DATE(timestamp) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
GROUP BY 1
```

> Replace `<table_name>` with the relevant table (e.g., `polymarket_snapshots`).

**Pass criteria:**
- At least one row returned for yesterday's date.
- Row count is within the normal range for that table (compare against the prior few days).

---

## Step 5 — Service Liveness

**Purpose:** Confirm the admin frontend and backend API are up.

**Checks:**

1. Open the admin frontend and confirm the page loads and auth works.
2. Hit the API to confirm it's responding:

```bash
curl -s -o /dev/null -w "%{http_code}" \
  https://doomsday-api-846376753241.us-central1.run.app/health
```

**Pass criteria:**
- Frontend loads without errors.
- API returns `200` (or whatever the expected health-check status is).

---

## Known Issues Backlog

| # | Component | Issue | Severity | Status |
|---|-----------|-------|----------|--------|
| 1 | Doomsday Exporter | Drive writes fail with `403: Service Accounts do not have storage quota` | Medium — GCS writes still succeed | Open |
| 2 | `doomsday-polymarket` | Unexpected Drive writes in logs — feature believed to have been removed | Low — investigate if intentional | Open |

---

## Suggested Improvements

1. **Automate the BQ validation** — Create a scheduled BigQuery query or Looker Studio dashboard showing daily row counts per table, so the manual query step becomes a single URL to open.
2. **Cloud Monitoring alerts** — Set up job-failure alerts on Cloud Run so you're paged without running this runbook manually every day.
3. **Log-based metrics** — Add Cloud Logging metrics for job success/failure to get a single dashboard across all jobs.
4. **Track expected fetch warnings** — Maintain a list of known-bad or closed markets so new failures are easy to spot against the baseline noise.
5. **Resolve Drive issues** — Either fix the Drive 403 quota problem (issues #1) or remove Drive writes from both exporters if GCS is the sole intended destination (issue #2). Resolving both cleans up the logs and removes ambiguity in future checks.
6. **API health endpoint** — If `/health` doesn't exist on the Cloud Run API, add a lightweight endpoint that returns `200 OK` so Step 5 is reliable and scriptable.

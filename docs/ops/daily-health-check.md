# Daily Job Health Check Runbook

Run this after the scheduled jobs complete (typically early morning).

> For validating a deployment rather than daily job health, see [post-deploy-validation.md](post-deploy-validation.md).

**GCP project:** `fg-polylabs`
**BigQuery dataset:** `fg-polylabs.doomsday`
**GCS bucket:** `gs://fg-polylabs-doomsday`
**Cloud Run API:** `https://doomsday-api-846376753241.us-central1.run.app`

---

## Running the Check

When asked to validate the application or check job health, Claude will execute the health-check script:

```bash
./scripts/health-check.sh
```

The script covers all five steps below and prints a pass/warn/fail summary. It requires `gcloud` (authenticated to `fg-polylabs`) and `python3`.

---

## What the Script Checks

### Step 1 — Cloud Run Jobs: Last Run

Confirms both `doomsday-exporter` and `doomsday-polymarket` ran today.

**Pass:** Last run timestamp is today's date.

---

### Step 2 — Doomsday Exporter

**Purpose:** Exports doomsday event data as JSON to GCS.

Checks latest execution status and scans logs for:
- `GCS done` — confirms data was written to GCS
- Any other errors — flagged as failures

**Pass:** Execution succeeded and GCS write line present in logs.

---

### Step 3 — doomsday-polymarket

**Purpose:** Fetches Polymarket data and writes it into BigQuery.

Checks latest execution status and scans logs for:
- `new rows inserted` — confirms BQ ingest succeeded
- `GCS done` — confirms GCS export succeeded
- Fetch warnings — counted and reported but not a failure
- Any other errors — flagged as failures

**Pass:** Execution succeeded and BQ insert line present in logs.

**Known behavior:**
- Fetch warnings for individual markets are expected (closed/expired markets return HTTP 400 from Polymarket).

---

### Step 4 — BigQuery Data Validation

**Purpose:** Confirm yesterday's data was ingested into `market_snapshots`.

Queries via the BigQuery REST API (the `bq` CLI has a dependency issue in this environment) and prints row counts for the last 5 days.

**Pass:** At least one row exists for yesterday's `snapshot_date`.

---

### Step 5 — Service Liveness

**Purpose:** Confirm the Cloud Run API is responding.

Hits the API root and checks for a valid HTTP response. A `404` at `/` is expected (no root handler exists) and counts as passing. Unreachable (`000`) or unexpected 5xx responses are failures.

**Pass:** HTTP response received from the API (any non-5xx, non-unreachable code).

> **Note:** Frontend liveness is covered by the post-deploy validation script, not this one. See [post-deploy-validation.md](post-deploy-validation.md).

---

## Suggested Improvements

1. **Automate the BQ validation** — Create a scheduled BigQuery query or Looker Studio dashboard showing daily row counts, so trends are visible without running the script.
2. **Cloud Monitoring alerts** — Set up job-failure alerts on Cloud Run so failures page you automatically.
3. **Track expected fetch warnings** — Maintain a list of known-bad or closed markets so new failures stand out against the baseline noise.
4. **API health endpoint** — Add a `/health` endpoint to the Cloud Run API returning `200 OK` so the liveness check is unambiguous.
5. **Fix `bq` CLI** — The `bq` CLI has an `absl.flags` dependency error in this environment; fixing it would simplify the BQ check (currently uses the REST API as a workaround).

# Post-Deploy Validation Runbook

Run after every deployment to confirm the system is healthy. When asked to validate a deploy, Claude will execute the script automatically.

**Frontend:** `https://fg-polylabs.github.io/doomsday-predict-frontend-admin/`
**Cloud Run API:** `https://doomsday-api-846376753241.us-central1.run.app`
**GCP project:** `fg-polylabs`

---

## Running the Validation

```bash
./scripts/post-deploy-validation.sh [expected-sha]
```

- `expected-sha` is the git SHA that should be live (defaults to current `HEAD`)
- Requires `gcloud` (authenticated to `fg-polylabs`) and `python3`
- Wait for GitHub Actions to complete before running (~2–3 min after push)

Example after a push:
```bash
./scripts/post-deploy-validation.sh $(git rev-parse HEAD)
```

---

## What the Script Checks

### Step 1 — Frontend (GitHub Pages)

- Confirms the latest `github-pages` deployment SHA matches the expected commit
- Confirms deployment state is `success`
- Confirms the page returns HTTP 200

**Pass:** SHA matches, deployment succeeded, page loads.

---

### Step 2 — Cloud Scheduler Jobs

Confirms all three scheduled jobs exist and are `ENABLED`:

| Job | Schedule |
|-----|----------|
| `doomsday-daily` | `0 1 * * *` (1 AM UTC) |
| `weather-sync-daily` | `0 3 * * *` (3 AM UTC) |
| `weather-daily` | `0 1 * * *` (1 AM UTC) |

**Pass:** All jobs found and in `ENABLED` state.

---

### Step 3 — API Service Liveness

- Confirms the `doomsday-api` Cloud Run service is in `Ready` state
- Confirms the API root returns a non-5xx, non-unreachable HTTP response

**Pass:** Service ready, API responds. HTTP 404 at `/` is expected (no root handler).

---

### Step 4 — API Image

- Confirms the `doomsday-api` service has an image set
- If the `doomsday-predict-analytics` sibling repo is present on disk, cross-checks the image SHA against that repo's `HEAD`

**Pass:** Image is set. If analytics repo is present, image SHA matches its HEAD.

**Note:** The API image is tagged with the analytics repo SHA, not this repo's SHA. A warning here means the API was not redeployed as part of this push — which is expected for frontend-only changes.

---

## Expected Warnings

- **API image SHA mismatch / analytics repo not found** — Normal for frontend-only deploys where the API image hasn't changed.

---

### Step 5 — Public Frontend Liveness

Confirms `https://fg-polylabs.github.io/doomsday-predict-frontend/` returns HTTP 200.

This is a liveness-only check — SHA validation for the public frontend is handled by its own `scripts/post-deploy-validation.sh` in the `doomsday-predict-frontend` repo.

**Pass:** HTTP 200 from the public frontend URL.

---

## Failure Scenarios

| Failure | Likely cause |
|---------|-------------|
| Frontend SHA mismatch | GitHub Actions deploy not yet complete, or workflow failed |
| Frontend HTTP non-200 | GitHub Pages outage or misconfiguration |
| Scheduler job not found or not ENABLED | Job was manually paused or deleted |
| Cloud Run service not ready | Service crashed or was deleted |
| API unreachable | Cloud Run cold start issue or service down |

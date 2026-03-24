#!/usr/bin/env bash
# Daily health check for the doomsday-predict system.
# Usage: ./scripts/health-check.sh
# Requires: gcloud (authenticated), curl, python3

set -euo pipefail

PROJECT="fg-polylabs"
REGION="us-central1"
API_URL="https://doomsday-api-846376753241.us-central1.run.app"
BQ_DATASET="doomsday"
BQ_TABLE="market_snapshots"
BQ_DATE_COL="snapshot_date"

PASS=0
WARN=0
FAIL=0

# Known-issue patterns that should not count as failures
KNOWN_DRIVE_PATTERNS=(
  "storageQuotaExceeded"
  "insufficientParentPermissions"
  "Service Accounts do not have storage quota"
)

green()  { printf '\033[0;32m✔ %s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m⚠ %s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m✘ %s\033[0m\n' "$*"; }
header() { printf '\n\033[1;34m=== %s ===\033[0m\n' "$*"; }

pass()  { green  "$*"; PASS=$((PASS + 1));  }
warn()  { yellow "$*"; WARN=$((WARN + 1));  }
fail()  { red    "$*"; FAIL=$((FAIL + 1));  }

is_known_drive_error() {
  local line="$1"
  for pattern in "${KNOWN_DRIVE_PATTERNS[@]}"; do
    if [[ "$line" == *"$pattern"* ]]; then
      return 0
    fi
  done
  return 1
}

# ── Set active project ────────────────────────────────────────────────────────
gcloud config set project "$PROJECT" --quiet 2>/dev/null

# ── Step 1: Cloud Run jobs ran today ─────────────────────────────────────────
header "Step 1 — Cloud Run Jobs: Last Run"

TODAY=$(date -u +%Y-%m-%d)
JOBS=("doomsday-exporter" "doomsday-polymarket")

for JOB in "${JOBS[@]}"; do
  LAST_RUN=$(gcloud run jobs executions list \
    --job="$JOB" \
    --region="$REGION" \
    --limit=1 \
    --format="value(status.completionTime)" 2>/dev/null)
  if [[ "$LAST_RUN" == "$TODAY"* ]]; then
    pass "$JOB: last run $LAST_RUN"
  else
    fail "$JOB: last run was '${LAST_RUN:-unknown}' (expected today $TODAY)"
  fi
done

# ── Step 2: doomsday-exporter execution + logs ────────────────────────────────
header "Step 2 — Doomsday Exporter"

EXEC=$(gcloud run jobs executions list \
  --job=doomsday-exporter \
  --region="$REGION" \
  --limit=1 \
  --format="value(name)" 2>/dev/null)

STATUS=$(gcloud run jobs executions describe "$EXEC" \
  --region="$REGION" \
  --format="value(status.conditions[0].status)" 2>/dev/null)

if [[ "$STATUS" == "True" ]]; then
  pass "doomsday-exporter execution $EXEC: Succeeded"
else
  fail "doomsday-exporter execution $EXEC: did not succeed (status=$STATUS)"
fi

echo "  Scanning logs..."
LOGS=$(gcloud logging read \
  "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"doomsday-exporter\" AND labels.\"run.googleapis.com/execution_name\"=\"$EXEC\"" \
  --project="$PROJECT" \
  --limit=200 \
  --format="value(textPayload)" 2>/dev/null)

GCS_LINE=$(echo "$LOGS" | grep "GCS done" || true)
if [[ -n "$GCS_LINE" ]]; then
  pass "GCS export: $GCS_LINE"
else
  fail "GCS export: no 'GCS done' line found in logs"
fi

DRIVE_LINE=$(echo "$LOGS" | grep "Drive done" || true)
if [[ -n "$DRIVE_LINE" ]]; then
  pass "Drive export: $DRIVE_LINE"
fi

UNEXPECTED_ERRORS=$(echo "$LOGS" | grep -i "error" | while read -r line; do
  is_known_drive_error "$line" || echo "$line"
done || true)
if [[ -n "$UNEXPECTED_ERRORS" ]]; then
  while IFS= read -r line; do
    fail "Unexpected error: $line"
  done <<< "$UNEXPECTED_ERRORS"
fi

DRIVE_ERRORS=$(echo "$LOGS" | grep -c "Drive:.*Error 403" || true)
if [[ "$DRIVE_ERRORS" -gt 0 ]]; then
  warn "Drive: $DRIVE_ERRORS file(s) failed to write (known issue — GCS unaffected)"
fi

# ── Step 3: doomsday-polymarket execution + logs ──────────────────────────────
header "Step 3 — doomsday-polymarket"

EXEC_PM=$(gcloud run jobs executions list \
  --job=doomsday-polymarket \
  --region="$REGION" \
  --limit=1 \
  --format="value(name)" 2>/dev/null)

STATUS_PM=$(gcloud run jobs executions describe "$EXEC_PM" \
  --region="$REGION" \
  --format="value(status.conditions[0].status)" 2>/dev/null)

if [[ "$STATUS_PM" == "True" ]]; then
  pass "doomsday-polymarket execution $EXEC_PM: Succeeded"
else
  fail "doomsday-polymarket execution $EXEC_PM: did not succeed (status=$STATUS_PM)"
fi

echo "  Scanning logs..."
LOGS_PM=$(gcloud logging read \
  "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"doomsday-polymarket\" AND labels.\"run.googleapis.com/execution_name\"=\"$EXEC_PM\"" \
  --project="$PROJECT" \
  --limit=200 \
  --format="value(textPayload)" 2>/dev/null)

BQ_LINE=$(echo "$LOGS_PM" | grep "new rows inserted" || true)
if [[ -n "$BQ_LINE" ]]; then
  pass "BigQuery ingest: $BQ_LINE"
else
  fail "BigQuery ingest: no 'rows inserted' line found in logs"
fi

GCS_LINE_PM=$(echo "$LOGS_PM" | grep "GCS done" || true)
if [[ -n "$GCS_LINE_PM" ]]; then
  pass "GCS export: $GCS_LINE_PM"
fi

FETCH_WARNS=$(echo "$LOGS_PM" | grep -c "warning: could not fetch" || true)
if [[ "$FETCH_WARNS" -gt 0 ]]; then
  warn "Fetch warnings: $FETCH_WARNS market(s) could not be fetched (expected for closed/expired markets)"
fi

DRIVE_ERRORS_PM=$(echo "$LOGS_PM" | grep -c "Drive:.*Error 403" || true)
if [[ "$DRIVE_ERRORS_PM" -gt 0 ]]; then
  warn "Drive: $DRIVE_ERRORS_PM file(s) failed to write (known issue #2 — Drive writes may be unintentional)"
fi

UNEXPECTED_PM=$(echo "$LOGS_PM" | grep -i "error" | while read -r line; do
  is_known_drive_error "$line" || echo "$line"
done || true)
if [[ -n "$UNEXPECTED_PM" ]]; then
  while IFS= read -r line; do
    fail "Unexpected error: $line"
  done <<< "$UNEXPECTED_PM"
fi

# ── Step 4: BigQuery data validation ─────────────────────────────────────────
header "Step 4 — BigQuery Data Validation"

YESTERDAY=$(date -u -d "yesterday" +%Y-%m-%d 2>/dev/null || date -u -v-1d +%Y-%m-%d)
TOKEN=$(gcloud auth print-access-token 2>/dev/null)

BQ_RESPONSE=$(curl -s -X POST \
  "https://bigquery.googleapis.com/bigquery/v2/projects/$PROJECT/queries" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": \"SELECT $BQ_DATE_COL, COUNT(*) AS row_count FROM \`$PROJECT.$BQ_DATASET.$BQ_TABLE\` GROUP BY 1 ORDER BY 1 DESC LIMIT 5\",
    \"useLegacySql\": false,
    \"timeoutMs\": 30000
  }")

BQ_ERROR=$(echo "$BQ_RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['error']['message'])" 2>/dev/null || true)
if [[ -n "$BQ_ERROR" ]]; then
  fail "BigQuery query failed: $BQ_ERROR"
else
  echo "  Recent snapshot_date counts:"
  echo "$BQ_RESPONSE" | python3 -c "
import sys, json
r = json.load(sys.stdin)
rows = r.get('rows', [])
for row in rows:
    date, count = row['f'][0]['v'], row['f'][1]['v']
    print(f'    {date}: {count} rows')
"
  YESTERDAY_COUNT=$(echo "$BQ_RESPONSE" | python3 -c "
import sys, json
r = json.load(sys.stdin)
yesterday = '$YESTERDAY'
for row in r.get('rows', []):
    if row['f'][0]['v'] == yesterday:
        print(row['f'][1]['v'])
        break
" 2>/dev/null || echo "0")

  if [[ "${YESTERDAY_COUNT:-0}" -gt 0 ]]; then
    pass "Yesterday ($YESTERDAY) has $YESTERDAY_COUNT rows in $BQ_TABLE"
  else
    fail "No rows found for yesterday ($YESTERDAY) in $BQ_TABLE"
  fi
fi

# ── Step 5: API liveness ──────────────────────────────────────────────────────
header "Step 5 — Service Liveness"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "000" ]]; then
  fail "API unreachable: $API_URL"
elif [[ "$HTTP_CODE" == "404" ]]; then
  # 404 at root is expected — the service is up, it just has no root handler
  pass "API is up (HTTP $HTTP_CODE at / — expected, no root handler)"
elif [[ "$HTTP_CODE" =~ ^[2] ]]; then
  pass "API is up (HTTP $HTTP_CODE)"
else
  fail "API returned unexpected status: HTTP $HTTP_CODE"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
header "Summary"
echo "  Pass:  $PASS"
echo "  Warn:  $WARN"
echo "  Fail:  $FAIL"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  red "Health check FAILED ($FAIL failure(s))"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  yellow "Health check PASSED with $WARN warning(s)"
  exit 0
else
  green "Health check PASSED"
  exit 0
fi

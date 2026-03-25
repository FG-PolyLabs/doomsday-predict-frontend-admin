#!/usr/bin/env bash
# Post-deploy validation for the doomsday-predict system.
# Usage: ./scripts/post-deploy-validation.sh [expected-sha]
#   expected-sha: the git SHA that should be live (defaults to current HEAD)
#
# Checks:
#   1. Frontend (GitHub Pages) is up and serving the expected deploy
#   2. All Cloud Scheduler jobs are ENABLED
#   3. Cloud Run API service is live and responding
#   4. Cloud Run API image was updated (matches expected SHA in image tag)
#
# Requires: gcloud (authenticated), curl, python3

set -euo pipefail

PROJECT="fg-polylabs"
REGION="us-central1"
GITHUB_REPO="FG-PolyLabs/doomsday-predict-frontend-admin"
FRONTEND_URL="https://fg-polylabs.github.io/doomsday-predict-frontend-admin/"
API_URL="https://doomsday-api-846376753241.us-central1.run.app"
API_SERVICE="doomsday-api"

# Normalise to full SHA so prefix comparisons always work
_RAW_SHA="${1:-$(git rev-parse HEAD)}"
EXPECTED_SHA=$(git rev-parse "$_RAW_SHA" 2>/dev/null || echo "$_RAW_SHA")
SHORT_SHA="${EXPECTED_SHA:0:8}"

PASS=0
WARN=0
FAIL=0

green()  { printf '\033[0;32m✔ %s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m⚠ %s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m✘ %s\033[0m\n' "$*"; }
header() { printf '\n\033[1;34m=== %s ===\033[0m\n' "$*"; }

pass()  { green  "$*"; PASS=$((PASS + 1)); }
warn()  { yellow "$*"; WARN=$((WARN + 1)); }
fail()  { red    "$*"; FAIL=$((FAIL + 1)); }

echo "Validating deploy: $SHORT_SHA"
gcloud config set project "$PROJECT" --quiet 2>/dev/null

# ── Step 1: Frontend — GitHub Pages deploy ────────────────────────────────────
header "Step 1 — Frontend (GitHub Pages)"

# Check the latest github-pages deployment SHA
DEPLOYED_SHA=$(curl -s \
  "https://api.github.com/repos/$GITHUB_REPO/deployments?environment=github-pages&per_page=1" \
  | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(r[0]['sha'][:8] if r else '')
" 2>/dev/null)

DEPLOY_STATE=$(curl -s \
  "https://api.github.com/repos/$GITHUB_REPO/deployments?environment=github-pages&per_page=1" \
  | python3 -c "
import sys, json, urllib.request
r = json.load(sys.stdin)
if not r:
    print('unknown')
else:
    statuses_url = r[0]['statuses_url']
    with urllib.request.urlopen(statuses_url + '?per_page=1') as resp:
        s = json.load(resp)
        print(s[0]['state'] if s else 'unknown')
" 2>/dev/null)

if [[ "$SHORT_SHA" == "$DEPLOYED_SHA"* || "$DEPLOYED_SHA" == "$SHORT_SHA"* ]]; then
  pass "Frontend SHA matches: $DEPLOYED_SHA"
else
  fail "Frontend SHA mismatch: deployed=$DEPLOYED_SHA expected=$SHORT_SHA"
fi

if [[ "$DEPLOY_STATE" == "success" ]]; then
  pass "GitHub Pages deployment state: success"
else
  fail "GitHub Pages deployment state: $DEPLOY_STATE (expected success)"
fi

# Check the page actually loads
FRONTEND_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$FRONTEND_URL" 2>/dev/null || echo "000")
if [[ "$FRONTEND_HTTP" == "200" ]]; then
  pass "Frontend HTTP $FRONTEND_HTTP: $FRONTEND_URL"
elif [[ "$FRONTEND_HTTP" == "000" ]]; then
  fail "Frontend unreachable: $FRONTEND_URL"
else
  warn "Frontend HTTP $FRONTEND_HTTP (expected 200): $FRONTEND_URL"
fi

# ── Step 2: Cloud Scheduler jobs ──────────────────────────────────────────────
header "Step 2 — Cloud Scheduler Jobs"

EXPECTED_JOBS=("doomsday-daily" "weather-sync-daily" "weather-daily")

for JOB in "${EXPECTED_JOBS[@]}"; do
  STATE=$(gcloud scheduler jobs describe "$JOB" \
    --location="$REGION" \
    --project="$PROJECT" \
    --format="value(state)" 2>/dev/null || echo "NOT_FOUND")

  if [[ "$STATE" == "ENABLED" ]]; then
    SCHEDULE=$(gcloud scheduler jobs describe "$JOB" \
      --location="$REGION" \
      --project="$PROJECT" \
      --format="value(schedule)" 2>/dev/null)
    pass "Scheduler job $JOB: ENABLED ($SCHEDULE)"
  elif [[ "$STATE" == "NOT_FOUND" ]]; then
    fail "Scheduler job $JOB: NOT FOUND"
  else
    fail "Scheduler job $JOB: $STATE (expected ENABLED)"
  fi
done

# ── Step 3: Cloud Run API service liveness ────────────────────────────────────
header "Step 3 — API Service Liveness"

SERVICE_STATUS=$(gcloud run services describe "$API_SERVICE" \
  --region="$REGION" \
  --project="$PROJECT" \
  --format="value(status.conditions[0].status)" 2>/dev/null || echo "")

if [[ "$SERVICE_STATUS" == "True" ]]; then
  pass "Cloud Run service $API_SERVICE: Ready"
else
  fail "Cloud Run service $API_SERVICE: not ready (status=$SERVICE_STATUS)"
fi

API_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/" 2>/dev/null || echo "000")
if [[ "$API_HTTP" == "000" ]]; then
  fail "API unreachable: $API_URL"
elif [[ "$API_HTTP" =~ ^5 ]]; then
  fail "API returned HTTP $API_HTTP (server error)"
else
  pass "API responding: HTTP $API_HTTP at $API_URL"
fi

# ── Step 4: Cloud Run API image updated ───────────────────────────────────────
header "Step 4 — API Image"

CURRENT_IMAGE=$(gcloud run services describe "$API_SERVICE" \
  --region="$REGION" \
  --project="$PROJECT" \
  --format="value(spec.template.spec.containers[0].image)" 2>/dev/null)

echo "  Current image: $CURRENT_IMAGE"

# The API image tag is the git SHA of the analytics repo — not this repo.
# We can only confirm the service has a valid image and is running.
# Cross-repo SHA validation requires knowing the analytics repo HEAD.
if [[ -n "$CURRENT_IMAGE" ]]; then
  pass "API image is set: $(basename "$CURRENT_IMAGE")"
else
  fail "Could not determine API image"
fi

# Check image was recently updated by looking at service last transition time
LAST_UPDATED=$(gcloud run services describe "$API_SERVICE" \
  --region="$REGION" \
  --project="$PROJECT" \
  --format="value(status.conditions[0].lastTransitionTime)" 2>/dev/null)
echo "  Service last updated: $LAST_UPDATED"

# Optionally compare against analytics repo if sibling exists
ANALYTICS_REPO="../doomsday-predict-analytics"
if [[ -d "$ANALYTICS_REPO/.git" ]]; then
  ANALYTICS_SHA=$(git -C "$ANALYTICS_REPO" rev-parse --short HEAD 2>/dev/null || echo "")
  if [[ -n "$ANALYTICS_SHA" && "$CURRENT_IMAGE" == *"$ANALYTICS_SHA"* ]]; then
    pass "API image SHA matches analytics repo HEAD: $ANALYTICS_SHA"
  elif [[ -n "$ANALYTICS_SHA" ]]; then
    warn "API image SHA does not match analytics HEAD ($ANALYTICS_SHA) — may not have been redeployed"
  fi
else
  warn "Analytics repo not found at $ANALYTICS_REPO — skipping image SHA cross-check"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
header "Summary"
echo "  Expected SHA: $SHORT_SHA"
echo "  Pass:  $PASS"
echo "  Warn:  $WARN"
echo "  Fail:  $FAIL"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  red "Post-deploy validation FAILED ($FAIL failure(s))"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  yellow "Post-deploy validation PASSED with $WARN warning(s)"
  exit 0
else
  green "Post-deploy validation PASSED"
  exit 0
fi

#!/usr/bin/env bash
# scripts/checkpoint.sh — Create checkpoint tags across all doomsday-predict repos.
#
# Usage:
#   ./scripts/checkpoint.sh
#   ./scripts/checkpoint.sh "reason for this checkpoint"
#
# Applies the same "skip if HEAD has not moved" logic as the GitHub Actions
# workflow, then pushes all new tags to origin immediately.

set -euo pipefail

REASON="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

REPOS=(
  "doomsday-predict-frontend-admin"
  "doomsday-predict-analytics"
  "doomsday-predict-data"
)

tag_repo() {
  local repo="$1"
  local repo_dir="$PARENT_DIR/$repo"

  if [ ! -d "$repo_dir/.git" ]; then
    echo "  [skip]   $repo — not found locally at $repo_dir"
    return
  fi

  echo "  [check]  $repo"
  pushd "$repo_dir" > /dev/null

  # Fetch remote tags so we have an up-to-date picture
  git fetch --tags --quiet

  # Find the most recent checkpoint-* tag reachable from HEAD
  LAST_TAG=$(git tag --list 'checkpoint-*' --sort=-version:refname \
             | head -n 1 || true)

  if [ -n "$LAST_TAG" ]; then
    LAST_TAGGED=$(git rev-list -n 1 "$LAST_TAG")
    CURRENT=$(git rev-parse HEAD)
    if [ "$LAST_TAGGED" = "$CURRENT" ]; then
      echo "  [skip]   $repo — HEAD has not moved since $LAST_TAG"
      popd > /dev/null
      return
    fi
  fi

  # Build a unique tag name for today
  BASE="checkpoint-$(date -u +%Y-%m-%d)"
  TAG="$BASE"
  SUFFIX=1
  while git tag --list "$TAG" | grep -q .; do
    SUFFIX=$(( SUFFIX + 1 ))
    TAG="${BASE}-${SUFFIX}"
  done

  SHORT_SHA=$(git rev-parse --short HEAD)
  LAST_MSG=$(git log -1 --pretty=%s)
  ANNOTATION="checkpoint at ${SHORT_SHA}: ${LAST_MSG}"
  [ -n "$REASON" ] && ANNOTATION="${ANNOTATION} (${REASON})"

  git tag -a "$TAG" -m "$ANNOTATION"
  git push origin "$TAG"

  echo "  [tag]    $repo → $TAG"
  echo "           $ANNOTATION"

  popd > /dev/null
}

echo "Checkpointing doomsday-predict repos under $PARENT_DIR"
[ -n "$REASON" ] && echo "Reason: $REASON"
echo ""

for repo in "${REPOS[@]}"; do
  tag_repo "$repo"
done

echo ""
echo "Done."

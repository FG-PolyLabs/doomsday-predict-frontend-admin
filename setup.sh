#!/usr/bin/env bash
# setup.sh — Bootstrap the doomsday-predict multi-repo workspace.
# Run this once after cloning doomsday-predict-frontend-admin.
# Clones the sibling repos into the same parent directory if they are missing.

set -euo pipefail

PARENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ORG="https://github.com/FG-PolyLabs"

repos=(
  "doomsday-predict-analytics"
  "doomsday-predict-data"
)

echo "Bootstrap: ensuring sibling repos exist under $PARENT_DIR"
echo ""

for repo in "${repos[@]}"; do
  target="$PARENT_DIR/$repo"
  if [ -d "$target/.git" ]; then
    echo "  [ok]     $repo — already cloned, pulling latest"
    git -C "$target" pull --ff-only
  else
    echo "  [clone]  $repo"
    git clone "$ORG/$repo.git" "$target"
  fi
done

echo ""
echo "Done. Workspace layout:"
echo "  $PARENT_DIR/"
echo "  ├── doomsday-predict-frontend-admin/  (this repo)"
echo "  ├── doomsday-predict-analytics/        (backend API + scheduled jobs)"
echo "  └── doomsday-predict-data/             (published JSON data files)"
echo ""
echo "Next steps:"
echo "  1. Copy .env.example to .env and fill in Firebase config + backend URL"
echo "  2. Run: source .env && hugo server --port 1313"

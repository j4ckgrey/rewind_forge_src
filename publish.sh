#!/usr/bin/env bash
#
# Publish a Rewind addon as a DIST-ONLY release commit.
#
# Run from an addon repo (each addon symlinks/copies this as ./publish.sh).
# Builds the bundle, then writes an orphan-history `release` branch containing
# ONLY the published artifacts:
#
#   manifest.json
#   dist/index.mjs
#
# No source ever reaches the branch operators install from, and every publish
# is exactly one commit — which is what the Rewind server's commit-based
# update check watches (manifest rewind.repo + rewind.branch:"release").
#
#   ./publish.sh          build + commit to local `release` branch
#   ./publish.sh --push   … and push it to origin
#
set -euo pipefail
cd "$(dirname "$0")"

npm run build

for f in manifest.json dist/index.mjs; do
  [ -f "$f" ] || { echo "missing $f — nothing to publish" >&2; exit 1; }
done

SRC_SHA=$(git rev-parse --short HEAD)

# Stage exactly the artifacts into a throwaway index, snapshot a tree from it,
# and graft that tree onto the release branch's history (orphan on first run).
TMP_INDEX=$(mktemp)
trap 'rm -f "$TMP_INDEX"' EXIT
export GIT_INDEX_FILE="$TMP_INDEX"
git read-tree --empty
git update-index --add manifest.json dist/index.mjs
TREE=$(git write-tree)
unset GIT_INDEX_FILE

PARENT=$(git rev-parse -q --verify refs/heads/release || true)
if [ -n "$PARENT" ] && [ "$(git rev-parse "$PARENT^{tree}")" = "$TREE" ]; then
  echo "release branch already has this exact artifact — nothing new to commit"
  RELEASE_CHANGED=false
else
  MSG="release: $(date -u +%Y-%m-%dT%H:%MZ) (source $SRC_SHA)"
  COMMIT=$(git commit-tree "$TREE" ${PARENT:+-p "$PARENT"} -m "$MSG")
  git update-ref refs/heads/release "$COMMIT"
  echo "release ← $COMMIT ($MSG)"
  RELEASE_CHANGED=true
fi

SRC_BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [ "${1:-}" = "--push" ]; then
  git push origin "$SRC_BRANCH"
  echo "pushed origin/$SRC_BRANCH (source)"
  git push origin release
  echo "pushed origin/release — installed servers will pick it up on their next update check"
elif [ "$RELEASE_CHANGED" = true ]; then
  echo "local only — run './publish.sh --push' (or 'git push origin release') to publish"
fi

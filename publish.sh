#!/usr/bin/env bash
#
# Publish a Rewind addon to BOTH of its GitHub repos in one shot:
#   • source (current branch) → origin-src   (the private *_src repo)
#   • built artifact (manifest.json + dist/index.mjs) → origin/main
#                                             (the public repo servers install)
#
# One command does everything — commit, build, snapshot, push both — so a
# publish always lands on GitHub, not just locally:
#
#   ./publish.sh              commit + build + push BOTH repos   (default)
#   ./publish.sh "message"    … with a custom source commit message
#   ./publish.sh --local      commit + build only, no push (dry run)
#
# Requires two git remotes (git remote -v):
#   origin       git@github.com:<you>/<addon>.git       (public artifacts)
#   origin-src   git@github.com:<you>/<addon>_src.git   (private source)
#
set -euo pipefail
cd "$(dirname "$0")"

PUSH=true
MSG=""
case "${1:-}" in
  --local) PUSH=false ;;
  "") ;;
  *) MSG="$1" ;;
esac

# Fail early with a clear message if the two remotes aren't set up (the #1
# reason "publish isn't publishing" — pushes silently target the wrong place).
for r in origin origin-src; do
  git remote get-url "$r" >/dev/null 2>&1 || {
    echo "✗ missing git remote '$r'. Set it with:" >&2
    echo "    git remote add $r git@github.com:<you>/<repo>.git" >&2
    exit 1
  }
done

# 1. Build FIRST so the fresh dist is part of the commit below.
npm run build
for f in manifest.json dist/index.mjs; do
  [ -f "$f" ] || { echo "✗ missing $f — nothing to publish" >&2; exit 1; }
done

# 2. Commit the whole working tree (source + rebuilt dist) so the SOURCE repo
#    actually gets your latest changes. This is the step the old script skipped,
#    which is why origin-src kept going stale while only the artifact updated.
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -q -m "${MSG:-publish: $(date -u +%Y-%m-%dT%H:%MZ)}"
  echo "✓ committed working tree ($(git rev-parse --short HEAD))"
else
  echo "· no source changes to commit"
fi

SRC_SHA=$(git rev-parse --short HEAD)
SRC_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 3. Snapshot EXACTLY the two artifacts onto an orphan-history `release` branch
#    (staged into a throwaway index so nothing else leaks into the public repo).
TMP_INDEX=$(mktemp)
trap 'rm -f "$TMP_INDEX"' EXIT
export GIT_INDEX_FILE="$TMP_INDEX"
git read-tree --empty
git update-index --add manifest.json dist/index.mjs
TREE=$(git write-tree)
unset GIT_INDEX_FILE

PARENT=$(git rev-parse -q --verify refs/heads/release || true)
if [ -n "$PARENT" ] && [ "$(git rev-parse "$PARENT^{tree}")" = "$TREE" ]; then
  echo "· release artifact unchanged"
else
  MSG_R="release: $(date -u +%Y-%m-%dT%H:%MZ) (source $SRC_SHA)"
  COMMIT=$(git commit-tree "$TREE" ${PARENT:+-p "$PARENT"} -m "$MSG_R")
  git update-ref refs/heads/release "$COMMIT"
  echo "✓ release ← $COMMIT"
fi

# 4. Push BOTH repos. This is a publish — it goes to GitHub every time.
if [ "$PUSH" = true ]; then
  git push origin-src "$SRC_BRANCH"
  echo "✓ pushed source → origin-src/$SRC_BRANCH"
  git push origin release:main
  echo "✓ pushed artifact → origin/main (installed servers pick it up on their next update check)"
  echo "✅ published to both repos"
else
  echo "· --local: committed + built, not pushed"
fi

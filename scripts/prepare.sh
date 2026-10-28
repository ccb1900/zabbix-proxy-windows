#!/usr/bin/env bash
# Build the Windows proxy source tree: upstream Zabbix at the pinned tag,
# plus overlay/ (files this port adds), plus patches/ (changes to upstream
# files), applied in the order of patches/series.
#
#   scripts/prepare.sh [dest]        dest defaults to ./zabbix
#
# The result is a git repository with one commit per step, tagged "upstream"
# at the untouched release, so `git log upstream..` reads as the port and
# scripts/refresh-patches.sh can turn local edits back into patches.
#
# Environment:
#   UPSTREAM_URL   git remote to clone from (default: GitHub mirror of Zabbix)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=${1:-$ROOT/zabbix}
VERSION=$(tr -d '[:space:]' < "$ROOT/UPSTREAM_VERSION")
UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/zabbix/zabbix}

if [ -e "$DEST" ]; then
  echo "error: $DEST already exists; remove it or pass another destination" >&2
  exit 1
fi

git_() { git -C "$DEST" -c user.name="prepare.sh" -c user.email="prepare@localhost" "$@"; }

echo "==> Zabbix $VERSION from $UPSTREAM_URL"
# autocrlf off while patching: overlay and patches are stored with LF.
git -c advice.detachedHead=false -c core.autocrlf=false \
  clone --quiet --depth 1 --branch "$VERSION" "$UPSTREAM_URL" "$DEST"
git_ config core.autocrlf false
git_ checkout --quiet -b windows-proxy
git_ tag upstream

echo "==> overlay"
cp -R "$ROOT/overlay/." "$DEST/"
git_ add -A
git_ commit --quiet -m "Overlay: files added by the Windows proxy port"

while read -r p; do
  [ -z "$p" ] && continue
  case "$p" in \#*) continue ;; esac
  echo "==> $p"
  if ! git_ apply --index --whitespace=nowarn "$ROOT/patches/$p"; then
    echo "error: $p does not apply on Zabbix $VERSION" >&2
    echo "       fix it in the tree, then run scripts/refresh-patches.sh" >&2
    git_ apply --reject --whitespace=nowarn "$ROOT/patches/$p" || true
    exit 1
  fi
  sed '/^diff --git/,$d' "$ROOT/patches/$p" | git_ commit --quiet -F -
done < "$ROOT/patches/series"

# Check the tree out again with the platform's line endings, as a plain
# clone would have: CRLF on Windows (batch files, nmake), LF elsewhere.
platform_crlf=$(git config --global core.autocrlf || git config --system core.autocrlf || echo false)
if [ "$platform_crlf" != "false" ]; then
  git_ config core.autocrlf "$platform_crlf"
  rm -f "$DEST/.git/index"
  git_ reset --quiet --hard HEAD
fi

echo "==> ready: $DEST ($(git_ rev-list --count upstream..HEAD) commits on top of Zabbix $VERSION)"

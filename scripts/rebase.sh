#!/usr/bin/env bash
# Carry the port onto another Zabbix release.
#
#   scripts/rebase.sh <new-version> [dest]     dest defaults to ./zabbix
#
# Unlike prepare.sh, which stops on the first patch that fails, this applies
# every patch with a three-way merge and keeps going. The result is a tree at
# <new-version> with the port applied and conflict markers wherever a patch
# did not merge cleanly, plus a report (REBASE_REPORT.md in the repo root).
#
# Then:
#   1. resolve every conflict marker in ./zabbix (grep -rn '^<<<<<<<' zabbix/src zabbix/include)
#   2. echo <new-version> > UPSTREAM_VERSION
#   3. scripts/refresh-patches.sh
#   4. push a branch, let CI build and test on Windows
#
# Exit status: 0 = everything applied cleanly, 3 = conflicts to resolve,
# anything else = the script itself failed.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NEW=${1:?usage: scripts/rebase.sh <new-version> [dest]}
DEST=${2:-$ROOT/zabbix}
OLD=$(tr -d '[:space:]' < "$ROOT/UPSTREAM_VERSION")
UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/zabbix/zabbix}
REPORT=${REPORT:-$ROOT/REBASE_REPORT.md}

[ -e "$DEST" ] && { echo "error: $DEST already exists" >&2; exit 1; }

git_() { git -C "$DEST" -c user.name="rebase.sh" -c user.email="rebase@localhost" "$@"; }

echo "==> Zabbix $NEW (patches were made against $OLD)"
git -c advice.detachedHead=false -c core.autocrlf=false \
  clone --quiet --depth 1 --branch "$NEW" "$UPSTREAM_URL" "$DEST"
git_ config core.autocrlf false
git_ checkout --quiet -b windows-proxy
git_ tag -f upstream >/dev/null
# A three-way merge needs the files as they were in the release the patches
# were made against; the patches name those blobs (--full-index).
git_ fetch --quiet --depth 1 "$UPSTREAM_URL" tag "$OLD"

conflicts=0
{
  echo "# Rebase report: $OLD -> $NEW"
  echo
  echo "| Step | Result | Files |"
  echo "| --- | --- | --- |"
} > "$REPORT"

# Overlay: a file the port adds may now exist upstream. Keep upstream's and
# report it: the port's version is in overlay/ to compare and merge by hand.
collide=()
while read -r f; do
  rel=${f#"$ROOT/overlay/"}
  if git_ cat-file -e "upstream:$rel" 2>/dev/null; then
    collide+=("$rel")
  else
    mkdir -p "$DEST/$(dirname "$rel")"; cp "$f" "$DEST/$rel"
  fi
done < <(find "$ROOT/overlay" -type f | sort)
git_ add -A
git_ commit --quiet -m "Overlay: files added by the Windows proxy port"
if [ ${#collide[@]} -gt 0 ]; then
  echo "| overlay | now upstream, kept upstream's | ${collide[*]} |" >> "$REPORT"
  conflicts=$((conflicts + ${#collide[@]}))
else
  echo "| overlay | clean | |" >> "$REPORT"
fi

while read -r p; do
  [ -z "$p" ] && continue
  case "$p" in \#*) continue ;; esac
  log=$(mktemp)
  # A file the patch touches may be gone upstream (moved or deleted). git apply
  # refuses the whole patch then, so leave those files out and report them.
  gone=""; excl=()
  while read -r f; do
    git_ cat-file -e "HEAD:$f" 2>/dev/null || { gone+="$f "; excl+=(--exclude="$f"); }
  done < <(grep '^diff --git' "$ROOT/patches/$p" | awk '{print substr($3,3)}')
  for f in $gone; do conflicts=$((conflicts + 1)); done
  if git_ apply --index --3way --whitespace=nowarn "${excl[@]}" "$ROOT/patches/$p" >"$log" 2>&1 && [ -z "$gone" ]; then
    if grep -q 'Applied patch .* with conflicts\|three-way' "$log"; then
      echo "| $p | merged three-way | |" >> "$REPORT"
    else
      echo "| $p | clean | |" >> "$REPORT"
    fi
  else
    unmerged=$(git_ diff --name-only --diff-filter=U | sort -u)
    files=""
    for f in $unmerged; do
      n=$(grep -c '^<<<<<<<' "$DEST/$f" || true)
      files+="$f ($n) "
      conflicts=$((conflicts + n))
    done
    for f in $gone; do files+="$f (gone upstream) "; done
    if [ -z "$unmerged" ] && [ -z "$gone" ]; then
      files="$(head -c 300 "$log" | tr '\n' ' ')"
      conflicts=$((conflicts + 1))
    fi
    echo "| $p | **conflicts** | $files|" >> "$REPORT"
    # Keep the markers in the tree so the next patch builds on top of them.
    git_ add -A
  fi
  rm -f "$log"
  sed '/^diff --git/,$d' "$ROOT/patches/$p" | git_ commit --quiet --allow-empty -F -
done < "$ROOT/patches/series"

{
  echo
  echo "Conflicts to resolve: **$conflicts**"
  echo
  echo "A file marked \"gone upstream\" was moved or removed: find where its code"
  echo "went (git log/grep in the new release) and carry the change there, or drop"
  echo "it if upstream now does the same thing."
} >> "$REPORT"

cat "$REPORT"
echo "==> tree: $DEST"
[ "$conflicts" -eq 0 ] || exit 3

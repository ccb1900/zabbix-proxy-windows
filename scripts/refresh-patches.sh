#!/usr/bin/env bash
# Turn the prepared tree back into overlay/ and patches/ after editing it.
#
#   scripts/refresh-patches.sh [tree]     tree defaults to ./zabbix
#
# Committed or not, every difference between the tree and the "upstream" tag
# is picked up:
#   - a file that does not exist upstream goes to overlay/
#   - a change to an upstream file goes to the patch that already owns that
#     file, keeping the patch's description header
#   - a change to an upstream file no patch owns yet goes to
#     patches/9999-unsorted.patch, with a warning: move it to the right patch
#     (or give it a new one) by editing the file lists, then run this again
#
# Typical upgrade to a new Zabbix release:
#   echo 7.4.17 > UPSTREAM_VERSION
#   rm -rf zabbix && scripts/prepare.sh       # stops on the first patch that breaks
#   ...fix the conflict in zabbix/, resume by hand or re-run...
#   scripts/refresh-patches.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TREE=${1:-$ROOT/zabbix}
UNSORTED=9999-unsorted.patch

git -C "$TREE" rev-parse --verify --quiet upstream >/dev/null || {
  echo "error: $TREE has no 'upstream' tag; was it made by scripts/prepare.sh?" >&2; exit 1; }

# Stage everything so the index holds the normalised (LF) content.
git -C "$TREE" add -A

# --- which patch owns which file, from the current series
declare -A owner header
while read -r p; do
  [ -z "$p" ] && continue
  case "$p" in \#*) continue ;; esac
  header[$p]=$(sed '/^diff --git/,$d' "$ROOT/patches/$p")
  while read -r f; do owner[$f]=$p; done < <(grep '^diff --git' "$ROOT/patches/$p" | awk '{print substr($3,3)}')
done < "$ROOT/patches/series"

# --- overlay: rebuild from the files that do not exist upstream
rm -rf "$ROOT/overlay"; mkdir -p "$ROOT/overlay"
while read -r f; do
  mkdir -p "$ROOT/overlay/$(dirname "$f")"
  git -C "$TREE" show ":$f" > "$ROOT/overlay/$f"
done < <(git -C "$TREE" diff --cached --diff-filter=A --name-only upstream)

# --- patches: changed or removed upstream files, grouped by owner
declare -A files_of
unsorted=()
while read -r f; do
  p=${owner[$f]:-}
  if [ -z "$p" ] || [ "$p" = "$UNSORTED" ]; then unsorted+=("$f"); continue; fi
  files_of[$p]+="$f"$'\n'
done < <(git -C "$TREE" diff --cached --diff-filter=MDT --name-only upstream)

new_series=()
while read -r p; do
  [ -z "$p" ] && continue
  case "$p" in \#*) continue ;; esac
  [ "$p" = "$UNSORTED" ] && continue
  if [ -z "${files_of[$p]:-}" ]; then
    echo "note: $p no longer changes anything; dropped" >&2
    rm -f "$ROOT/patches/$p"; continue
  fi
  mapfile -t fl < <(printf '%s' "${files_of[$p]}")
  { printf '%s\n\n' "${header[$p]}"; git -C "$TREE" diff --cached --full-index upstream -- "${fl[@]}"; } > "$ROOT/patches/$p"
  new_series+=("$p")
done < "$ROOT/patches/series"

rm -f "$ROOT/patches/$UNSORTED"
if [ ${#unsorted[@]} -gt 0 ]; then
  { printf 'Unsorted: changes not yet assigned to a themed patch\n\n'
    git -C "$TREE" diff --cached --full-index upstream -- "${unsorted[@]}"; } > "$ROOT/patches/$UNSORTED"
  new_series+=("$UNSORTED")
  echo "warning: ${#unsorted[@]} file(s) in patches/$UNSORTED:" >&2
  printf '  %s\n' "${unsorted[@]}" >&2
fi

printf '%s\n' "${new_series[@]}" > "$ROOT/patches/series"
echo "==> overlay: $(find "$ROOT/overlay" -type f | wc -l) files, patches: ${#new_series[@]}"

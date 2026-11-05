#!/usr/bin/env bash
# Removes only what install.sh created. Files you have edited since are kept.
#
#   ./uninstall.sh                    global install
#   ./uninstall.sh --project [path]   a project install
#   ./uninstall.sh --dry-run          show what would be removed
#
# Feature snapshots (refs/flutter-review/*) and saved reports (.claude/review/) in your
# projects are not touched. See UNINSTALL.md.

set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TOOLKIT_DIR/scripts/lib.sh"
parse_scope "$@"

if [ ! -f "$MANIFEST" ]; then
    echo "No manifest at $MANIFEST — nothing recorded as installed by flutter-review."
    exit 0
fi

removed=(); kept=()
while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -e "$f" ] || continue
    src="$SRC/${f#"$SKILLS_DIR"/}"
    if [ -f "$src" ] && render "$src" | cmp -s - "$f"; then
        if [ "$DRY_RUN" -eq 1 ]; then echo "  [dry-run] rm $f"; else rm "$f"; fi
        removed+=("$f")
    else
        kept+=("$f (modified since install — kept)")
    fi
done < <(sort -u "$MANIFEST")

# Remove folders that are now empty, deepest first; never non-empty ones.
if [ "$DRY_RUN" -eq 0 ]; then
    for d in "$SRC"/*/; do
        target="$SKILLS_DIR/$(basename "$d")"
        [ -d "$target" ] || continue
        find "$target" -depth -type d -empty -exec rmdir {} \; 2>/dev/null || true
    done
    [ "${#kept[@]}" -eq 0 ] && rm -f "$MANIFEST"
fi

echo "Removed (${#removed[@]}):"; for f in "${removed[@]+"${removed[@]}"}"; do echo "  - $f"; done
echo "Kept (${#kept[@]}):";       for f in "${kept[@]+"${kept[@]}"}"; do echo "  = $f"; done
[ "$DRY_RUN" -eq 1 ] && echo "(dry run — nothing was changed)"
exit 0

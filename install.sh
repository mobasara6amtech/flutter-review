#!/usr/bin/env bash
# Installs the flutter-review skills into Claude Code without overwriting anything.
#
#   ./install.sh                    global: ~/.claude/skills, works in every project (default)
#   ./install.sh --project [path]   one project: <path or current git root>/.claude/skills
#   ./install.sh --dry-run          show what would happen, change nothing
#
# Every file it creates is recorded in <claude dir>/.flutter-review-manifest so that
# uninstall.sh removes exactly those files and nothing else.

set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TOOLKIT_DIR/scripts/lib.sh"
parse_scope "$@"

run() { if [ "$DRY_RUN" -eq 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

echo "flutter-review ($SCOPE) → $SKILLS_DIR"
command -v git  >/dev/null 2>&1 || { echo "git is required." >&2; exit 1; }
command -v dart >/dev/null 2>&1 \
    && echo "Dart: $(dart --version 2>&1 | head -1)" \
    || echo "Warning: 'dart' is not on PATH. The skills need it at review time (it ships with Flutter)."

installed=(); skipped=()

while IFS= read -r rel; do
    to="$SKILLS_DIR/$rel"
    if [ -e "$to" ]; then
        if render "$SRC/$rel" | cmp -s - "$to"; then
            skipped+=("$to (already installed, identical)")
        else
            skipped+=("$to (exists and differs — left untouched)")
        fi
        continue
    fi
    run mkdir -p "$(dirname "$to")"
    if [ "$DRY_RUN" -eq 1 ]; then echo "  [dry-run] write $to"; else render "$SRC/$rel" > "$to"; fi
    installed+=("$to")
done < <(toolkit_files)

if [ "$DRY_RUN" -eq 0 ] && [ "${#installed[@]}" -gt 0 ]; then
    printf '%s\n' "${installed[@]}" >> "$MANIFEST"
fi

echo
echo "Installed (${#installed[@]}):"
for f in "${installed[@]+"${installed[@]}"}"; do echo "  + $f"; done
echo "Skipped (${#skipped[@]}):"
for f in "${skipped[@]+"${skipped[@]}"}"; do echo "  = $f"; done
[ "$DRY_RUN" -eq 1 ] && echo "(dry run — nothing was changed)"
echo
if [ "$SCOPE" = "project" ]; then
    echo "Commit .claude/skills/flutter-review* to share it with your team."
    echo "Keep .claude/.flutter-review-manifest out of git (it lists paths on your machine)."
fi
echo "Next: ./verify.sh $( [ "$SCOPE" = project ] && echo "--project ${CLAUDE_DIR%/.claude}" ), then in a new"
echo "Claude Code session type /flutter-review-help."

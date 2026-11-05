#!/usr/bin/env bash
# Verifies an installed flutter-review. Read-only.
#
#   ./verify.sh                    check the global install
#   ./verify.sh --project [path]   check a project install
#   ./verify.sh --test             also run the end-to-end tests (in a throwaway repo)

set -uo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_TESTS=0; args=()
for a in "$@"; do [ "$a" = "--test" ] && RUN_TESTS=1 || args+=("$a"); done
source "$TOOLKIT_DIR/scripts/lib.sh"
parse_scope "${args[@]+"${args[@]}"}"

fails=0; warns=0
pass() { echo "  ✅ $*"; }
fail() { echo "  ❌ $*"; fails=$((fails + 1)); }
warn() { echo "  ⚠️  $*"; warns=$((warns + 1)); }

echo "Tools"
command -v git  >/dev/null 2>&1 && pass "$(git --version)" || fail "git not on PATH"
command -v dart >/dev/null 2>&1 && pass "$(dart --version 2>&1 | head -1)" || fail "dart not on PATH"
command -v claude >/dev/null 2>&1 && pass "Claude Code $(claude --version 2>/dev/null | head -1)" \
    || warn "'claude' not on PATH (fine if you only use the VS Code extension)"

echo "Skills ($SCOPE: $SKILLS_DIR)"
for d in "$SRC"/*/; do
    name="$(basename "$d")"; f="$SKILLS_DIR/$name/SKILL.md"
    if [ ! -f "$f" ]; then fail "$f missing"; continue; fi
    head -1 "$f" | grep -q '^---$' && grep -q "^name: $name$" "$f" \
        && pass "$name" || fail "$f: frontmatter missing or name is not '$name'"
    grep -q '{{' "$f" && fail "$f still has unfilled {{placeholders}}"
done

echo "Review script"
script="$SKILLS_DIR/flutter-review/scripts/review.dart"
if [ ! -f "$script" ]; then
    fail "$script missing"
elif command -v dart >/dev/null 2>&1; then
    dart analyze "$script" >/dev/null 2>&1 && pass "dart analyze: no issues" || fail "dart analyze reported issues in $script"
fi

if [ "$RUN_TESTS" -eq 1 ]; then
    echo "End-to-end tests"
    bash "$TOOLKIT_DIR/tests/e2e.sh" || fails=$((fails + 1))
fi

echo
echo "Result: $fails failure(s), $warns warning(s)"
[ "$fails" -eq 0 ]

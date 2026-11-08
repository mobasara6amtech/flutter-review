#!/usr/bin/env bash
# End-to-end tests in throwaway folders. Touches nothing outside a temp dir.
#
#   bash tests/e2e.sh

set -uo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R="$TOOLKIT_DIR/skills/flutter-review/scripts/review.dart"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok()    { echo "  ✅ $*"; }
bad()   { echo "  ❌ $*"; fails=$((fails + 1)); }
check() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
has()   { grep -qE -- "$2" <<<"$1"; }
review() { dart run "$R" "$@"; }

# Repo state that must never change: status, stash, HEAD, branches, real index, staged and unstaged diffs.
state() {
    git status --porcelain=v2 --branch --untracked-files=all; echo ---
    git stash list; git rev-parse HEAD; git branch -a
    git hash-object .git/index; git diff --cached | git hash-object --stdin; git diff | git hash-object --stdin
}

echo "Review script"
T="$TMP/app"; mkdir -p "$T"; cd "$T"
git init -q; git config user.name t; git config user.email t@t
mkdir -p lib/features/cart/{domain/models,domain/repositories,controllers,screens,widgets} lib/helper lib/misc assets/language test
echo "class CartModel { int id = 0; }" > lib/features/cart/domain/models/cart_model.dart
echo "class OldWidget {}" > lib/features/cart/widgets/old_widget.dart
printf 'line1\nline2\nline3\n' > lib/features/cart/controllers/cart_controller.dart
printf 'class PriceHelper {\n  static double round(double v) => v;\n}\n' > lib/helper/price_helper.dart
echo "name: app" > pubspec.yaml; echo "build/" > .gitignore; echo "x" > notes.txt
git add -A; git commit -qm init
echo "stash me" >> notes.txt; git stash push -q -m "unrelated user stash" -- notes.txt

out=$(review start "Cart Feature")
check "start saves a baseline ref" has "$out" "refs/flutter-review/cart-feature/baseline"

echo "class CartModel { int id = 0; String? name; }" > lib/features/cart/domain/models/cart_model.dart
echo "abstract class CartRepositoryInterface {}" > lib/features/cart/domain/repositories/cart_repository_interface.dart
echo "class CartRepository implements CartRepositoryInterface {}" > lib/features/cart/domain/repositories/cart_repository.dart
git add lib/features/cart/domain/repositories/cart_repository_interface.dart
git commit -qm "commit made after the baseline"
rm lib/features/cart/widgets/old_widget.dart
git mv lib/helper/price_helper.dart lib/helper/money_helper.dart
printf 'line1\nline2 changed\nline3\n' > lib/features/cart/controllers/cart_controller.dart
echo "class CartScreen {}" > lib/features/cart/screens/cart_screen.dart
echo "class X {}" > lib/misc/random.dart
echo "// generated" > lib/features/cart/domain/models/cart_model.g.dart
printf '{"a":"b"}\n' > assets/language/en.json
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR' > assets/logo.png
mkdir -p build; echo junk > build/out.txt
echo "void main(){}" > test/cart_test.dart
echo "half staged" >> pubspec.yaml; git add pubspec.yaml; echo "and unstaged" >> pubspec.yaml

before=$(state)
out=$(review prepare review)
F=$(sed -n 's/^FROM=//p' <<<"$out"); TO=$(sed -n 's/^TO=//p' <<<"$out")
report=$(sed -n 's/^REPORT=//p' <<<"$out")

check "13 changed files"                      has "$out" "Changed files: 13 "
check "modified model → Models"               has "$out" "\[1\] Models"$'\n'"  modified  lib/features/cart/domain/models/cart_model.dart"
check "repository interface listed first"     has "$out" "\[2\] Repository"$'\n'"  added     lib/features/cart/domain/repositories/cart_repository_interface.dart"
check "file committed after baseline is kept" has "$out" "added     lib/features/cart/domain/repositories/cart_repository_interface.dart"
check "untracked screen → UI"                 has "$out" "added     lib/features/cart/screens/cart_screen.dart"
check "deleted widget"                        has "$out" "deleted   lib/features/cart/widgets/old_widget.dart"
check "rename detected"                       has "$out" "renamed   lib/helper/price_helper.dart -> lib/helper/money_helper.dart"
check "binary shown as binary"                has "$out" "assets/logo.png  \(binary\)"
check "half-staged pubspec → Config"          has "$out" "modified  pubspec.yaml"
check "unknown folder → Unclassified"         has "$out" "\[10\] Unclassified"$'\n'"  added     lib/misc/random.dart"
check ".g.dart → Generated"                   has "$out" "\[9\] Generated"$'\n'"  added     lib/features/cart/domain/models/cart_model.g.dart"
check "ignored build/ not included"           bash -c "! grep -q build/out.txt <<<\"\$1\"" _ "$out"
check "report file written"                   test -s "$report"
check "report has every non-empty layer"      test "$(grep -c '^## Layer' "$report")" -eq 9
check "report folder git-excluded"            grep -qx '/.code-review/' .git/info/exclude

layer5=$(review layer 5 "$F" "$TO")
check "layer diff shows hunks"                has "$layer5" "^\+class CartScreen \{\}"
full5=$(review layer 5 "$F" "$TO" --full)
check "--full shows removed content"          has "$full5" "1 \| class OldWidget \{\}"
check "binary shows size only"                has "$(review layer 7 "$F" "$TO")" "Binary file, [0-9]+ bytes"
check "review leaves the repo untouched"      test "$before" = "$(state)"

echo "class CartModel { int id = 0; String name = ''; }" > lib/features/cart/domain/models/cart_model.dart
before=$(state)
out=$(review prepare recheck "Cart Feature")
check "recheck shows only the fix"            has "$out" "Changed files: 1 "
report2=$(sed -n 's/^REPORT=//p' <<<"$out")
check "recheck does not overwrite the report" test "$report" != "$report2" -a -s "$report"
check "list shows the baseline"               has "$(review list)" "Cart Feature +cart-feature"
check "done deletes the refs"                 has "$(review done "Cart Feature")" "Deleted 2 ref"
review prepare review >/dev/null 2>&1; code=$?
check "no baseline exits 3"                   test "$code" -eq 3
check "--since HEAD works"                    has "$(review prepare review adhoc --since HEAD)" "^FROM=$(git rev-parse HEAD)"
review done adhoc >/dev/null
check "recheck/list/done leave repo untouched" test "$before" = "$(state)"
check "no temp index files left"              bash -c "! ls '${TMPDIR:-/tmp}' | grep -q flutter-review-"

echo "Install / uninstall"
export CLAUDE_CONFIG_DIR="$TMP/home/.claude"
out=$(bash "$TOOLKIT_DIR/install.sh")
check "global install writes 7 files"         has "$out" "Installed \(7\)"
check "global paths are absolute"             grep -q "$CLAUDE_CONFIG_DIR/skills/flutter-review/scripts/review.dart" "$CLAUDE_CONFIG_DIR/skills/flutter-review-list/SKILL.md"
check "no placeholders left"                  bash -c "! grep -rq '{{' '$CLAUDE_CONFIG_DIR/skills'"
check "verify passes"                         bash -c "bash '$TOOLKIT_DIR/verify.sh' >/dev/null"
check "reinstall skips identical files"       has "$(bash "$TOOLKIT_DIR/install.sh")" "Installed \(0\)"
echo "my note" >> "$CLAUDE_CONFIG_DIR/skills/flutter-review-help/SKILL.md"
out=$(bash "$TOOLKIT_DIR/uninstall.sh")
check "uninstall removes unchanged files"     has "$out" "Removed \(6\)"
check "uninstall keeps an edited file"        test -f "$CLAUDE_CONFIG_DIR/skills/flutter-review-help/SKILL.md"
check "uninstall removes emptied folders"     test ! -d "$CLAUDE_CONFIG_DIR/skills/flutter-review"

P="$TMP/proj"; mkdir -p "$P/lib"; (cd "$P" && git init -q)
out=$(cd "$P/lib" && bash "$TOOLKIT_DIR/install.sh" --project)
check "project install uses the git root"     test -f "$P/.claude/skills/flutter-review/SKILL.md"
check "project paths are relative"            grep -q '"\.claude/skills/flutter-review/scripts/review.dart"' "$P/.claude/skills/flutter-review-list/SKILL.md"
check "dry-run changes nothing"               bash -c "bash '$TOOLKIT_DIR/uninstall.sh' --project '$P' --dry-run >/dev/null && test -f '$P/.claude/skills/flutter-review/SKILL.md'"
bash "$TOOLKIT_DIR/uninstall.sh" --project "$P" >/dev/null
check "project uninstall removes everything"  test ! -e "$P/.claude/skills/flutter-review" -a ! -e "$P/.claude/.flutter-review-manifest"

echo
echo "Tests: $fails failure(s)"
[ "$fails" -eq 0 ]

# Shared by install.sh, uninstall.sh and verify.sh. Sourced, not run.
#
# parse_scope "$@" sets:
#   SCOPE       global | project
#   CLAUDE_DIR  ~/.claude (or $CLAUDE_CONFIG_DIR), or <project>/.claude
#   SKILLS_DIR  $CLAUDE_DIR/skills
#   PREFIX      path written into SKILL.md files: absolute for global, relative for project
#   MANIFEST    $CLAUDE_DIR/.flutter-review-manifest
#   DRY_RUN     0 | 1

SRC="$TOOLKIT_DIR/skills"

parse_scope() {
    SCOPE="global"; DRY_RUN=0; local project_path=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --global)  SCOPE="global" ;;
            --project)
                SCOPE="project"
                if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then project_path="$2"; shift; fi
                ;;
            --dry-run) DRY_RUN=1 ;;
            -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
            *) echo "Unknown option: $1" >&2; exit 2 ;;
        esac
        shift
    done

    if [ "$SCOPE" = "global" ]; then
        CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
        PREFIX="$CLAUDE_DIR/skills"
    else
        local root="${project_path:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
        [ -d "$root" ] || { echo "No such project folder: $root" >&2; exit 2; }
        # Physical path, so install and uninstall agree even through symlinks.
        root="$(cd "$root" && pwd -P)"
        CLAUDE_DIR="$root/.claude"
        # Relative, so a committed copy works for every teammate.
        PREFIX=".claude/skills"
    fi
    SKILLS_DIR="$CLAUDE_DIR/skills"
    MANIFEST="$CLAUDE_DIR/.flutter-review-manifest"
}

# Print a toolkit file with its {{placeholders}} filled in for the chosen scope.
render() {
    sed -e "s|{{REVIEW_SCRIPT}}|$PREFIX/flutter-review/scripts/review.dart|g" \
        -e "s|{{SKILLS_DIR}}|$PREFIX|g" "$1"
}

# Every file the toolkit ships, relative to skills/.
toolkit_files() {
    (cd "$SRC" && find . -type f ! -name '.DS_Store' | sed 's|^\./||' | sort)
}

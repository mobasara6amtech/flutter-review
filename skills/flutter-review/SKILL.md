---
name: flutter-review
description: Layer-by-layer walkthrough of ALL code changed while building one feature in a Flutter project (models → repository → service → controller → UI → helpers → config → tests → generated), based on working-tree snapshots, so it works without commits or pushes. Use when the user says "review the code", "show me what you changed", "walk me through the feature code", "start a feature baseline", "recheck my fixes", or types /flutter-review (start | review | recheck | list | done | help).
argument-hint: [start <name> | review | recheck | list | done <name> | help]
---

# flutter-review

## Commands

| Command | What it does | Example |
|---|---|---|
| `/flutter-review-start <name>` | Save a baseline of the working tree before you build a feature | `/flutter-review-start pharmacy checkout` |
| `/flutter-review [name]` | Diff baseline → now and walk it layer by layer (latest baseline if no name) | `/flutter-review pharmacy checkout` |
| `/flutter-review-recheck [name]` | Diff the last review → now, to review only the fixes made since | `/flutter-review-recheck` |
| `/flutter-review-list` | List baselines with their date and changed-file count | `/flutter-review-list` |
| `/flutter-review-done <name>` | Delete a feature's baseline and review refs | `/flutter-review-done pharmacy checkout` |
| `/flutter-review-help` | Show this list | `/flutter-review-help` |

Each command is its own skill (`{{SKILLS_DIR}}/flutter-review-*`) that runs this skill's
script. The older `/flutter-review start <name>` style still works.

Snapshot-based review of one feature's changes. A snapshot is the full working tree
(tracked + untracked, minus ignored) stored as a commit under `refs/flutter-review/<slug>/`
using a throwaway index. Diffs are always snapshot-tree to snapshot-tree, so committing,
pushing, amending or doing nothing during the feature makes no difference.

## Script

Always run the script. Never build diffs yourself (no `git diff` of your own, no reading
files to reconstruct a change).

```bash
R="{{REVIEW_SCRIPT}}"
dart run "$R" <command> ...
```

Run it from the project directory (any folder inside the repo works).

| Command | What it does |
|---|---|
| `start <name>` | Save `refs/flutter-review/<slug>/baseline` = current state |
| `prepare review [name] [--since <rev>]` | Snapshot now, diff baseline → now, save `reviewed`, write report, print summary |
| `prepare recheck [name]` | Snapshot now, diff `reviewed` → now, save new `reviewed`, write report, print summary |
| `list` | Baselines with name, date, changed-file count |
| `done <name>` | Delete that feature's refs |
| `summary <a> <b>` | Layer table + file list |
| `layer <n> <a> <b> [--full]` | Complete diff of one layer (`--full` = whole new file with line numbers) |

`prepare` prints `FEATURE=`, `SLUG=`, `FROM=`, `TO=`, `REPORT=` lines, then the summary.
Use the `FROM` / `TO` SHAs for every `layer` call in that walkthrough.

## Mapping user arguments

- `/flutter-review start <name>` → `start <name>`. Report the saved ref.
- `/flutter-review` or `/flutter-review review [name]` → `prepare review [name]`.
  With no name the most recent baseline is used.
- `/flutter-review recheck [name]` → `prepare recheck [name]`.
- `/flutter-review list` → `list`. `/flutter-review done <name>` → `done <name>`.
- `/flutter-review help` → `help`. Show its output exactly as printed.
- Any other first word (unknown command) → run `help` and show its output. Do not guess what was meant.

## No baseline (exit code 3, `NO_BASELINE`)

Do not guess. Ask the user (AskUserQuestion) to choose:

a) **Everything uncommitted** — HEAD → current working tree incl. untracked files.
   Warn: this may include other unfinished features.
   → `prepare review [name] --since HEAD`
b) **Since a commit** — show the last 15 of `git log --oneline`, let them pick.
   → `prepare review [name] --since <sha>`
c) **Since a branch** (e.g. `origin/main`). → `prepare review [name] --since <branch>`

`--since` also saves that point as the feature's baseline (if none exists), so `recheck`
works afterwards.

## Walkthrough

The review lives in the report file only. Do **not** print the summary, diffs or notes
in the terminal.

1. `prepare` has already written every layer's full diff to the `REPORT=` file.
2. Read the report file. For each non-empty layer, write **at most 5 short notes**: what
   this layer does for the feature, plus anything worth checking, for example:
   - null safety, unchecked `!`, missing null/empty states
   - API error handling (non-200, parse failures, timeouts)
   - controller `update()` after state changes, `dispose()` of controllers/streams
   - hardcoded user-facing strings instead of translation keys
   - magic numbers instead of the project's existing constants / dimensions / styles
   - logic in the wrong layer (UI doing business logic, controller touching API, etc.)
   - unused code, imports, parameters
   - new widgets/helpers that duplicate something already in the project
   - single-use private widgets or tiny functions
   - slower-than-needed code: wrong data structure, nested loops, repeated passes, recomputing in loops or `build`, needless allocations (e.g. `.map(...).toList()` where a for loop does)
3. Append the notes to the end of the report file under `## Review notes`, with one
   `### Layer <n> — <name>` subsection per non-empty layer. Never edit the diffs above it.
4. Reply in the terminal with only: the report path (as a clickable link), the total
   changed-file count, and the number of notes. Nothing else.
5. Later the user may ask a question about the report, ask for a `--full` view of a
   layer, or ask for a change. Answer or make the change. A `--full` request goes into a
   new file next to the report (`<report-name>-layer<n>-full.md`), not into the terminal.
   After any change, remind the user they can run `/flutter-review-recheck`.

## Layers

Classified by path; first match wins; every changed file appears in exactly one layer.
Check order: Generated, Tests, then 1–7; anything left is Config & Assets (non-Dart) or
Unclassified (Dart). Rules live in the `LAYER RULES` block at the top of `review.dart`.

1 Models · 2 Repository (interface first) · 3 Service (interface first) · 4 Controller ·
5 UI · 6 Helper & Util · 7 Config & Assets · 8 Tests · 9 Generated · 10 Unclassified

## Safety rules

Read-only toward the user's work:

- Never commit, push, stash, reset, checkout, merge, rebase, or modify the real index,
  HEAD, or branches as part of this skill.
- The only things this skill writes: refs under `refs/flutter-review/`, temp index files
  in the system temp dir (deleted after each snapshot), files under `.claude/review/`,
  and one `/.claude/review/` line in `.git/info/exclude` (never `.gitignore`).
- The refs are local only; a normal `git push` never sends them.
- Code edits happen only when the user explicitly asks for a change during the walkthrough.

## Help

`help` (also `-h` or `--help`, or running the script with no arguments) prints the command list above
with an example for each. `/flutter-review` alone still means `review`. An unknown command prints `Unknown command: <word>` followed by the same list and exits 2.

# flutter-review

**Review every line you changed for one feature in a Flutter app, sorted layer by layer —
without committing, pushing, or remembering which files you touched.**

flutter-review is a set of [Claude Code](https://claude.com/claude-code) skills. You tell it when
you start a feature; when you're done, it collects every change since then and writes one review
file, ordered the way a Flutter app is built:

```
Models → Repository → Service → Controller → UI → Helpers → Config & Assets → Tests → Generated
```

Each layer shows the full diff, plus Claude's notes on what to check (null safety, missing
`update()` / `dispose()`, hard-coded strings instead of translation keys, logic in the wrong layer,
unused or duplicated code, and so on).

---

## Contents

1. [Why](#1-why)
2. [What you need](#2-what-you-need)
3. [Install](#3-install)
4. [Connect it to your project](#4-connect-it-to-your-project)
5. [Daily use](#5-daily-use)
6. [Commands](#6-commands)
7. [The review file](#7-the-review-file)
8. [How it works](#8-how-it-works)
9. [Customise the layers](#9-customise-the-layers)
10. [Safety](#10-safety)
11. [Update and uninstall](#11-update-and-uninstall)
12. [FAQ and troubleshooting](#12-faq-and-troubleshooting)

---

## 1. Why

`git diff` only shows what is not committed yet. `git log` only shows what you committed. Real
work is messier: half a feature is committed, some files are staged, some are brand new, and you
may have started a second feature before finishing the first.

flutter-review takes a **snapshot of your whole working folder** when you start a feature and
compares it with a snapshot taken when you ask for a review. Whatever you did in between —
commit, amend, push, or nothing at all — the review shows exactly what changed for that
feature.

---

## 2. What you need

| Requirement | Check with |
|---|---|
| Claude Code — the CLI or the VS Code / JetBrains extension | `claude --version` |
| git | `git --version` |
| Dart on your `PATH` (it ships with Flutter) | `dart --version` |
| macOS or Linux shell (Windows: Git Bash) | — |

Your Flutter project must be a git repository (`git init` if it isn't). It does **not** need any
commits on a remote, and you don't need to add any package to `pubspec.yaml`.

---

## 3. Install

### Step 1 — Get the toolkit

```bash
git clone https://github.com/mobasara6amtech/flutter-review.git
cd flutter-review
```

Keep this folder — you'll use it to update or uninstall later.

### Step 2 — Choose where to install

| | Global | Project |
|---|---|---|
| Command | `./install.sh` | `./install.sh --project <path-to-flutter-app>` |
| Installs into | `~/.claude/skills/` | `<your-app>/.claude/skills/` |
| Works in | every project on your machine | that one project |
| Share with your team | no | yes — commit the folder |
| Best for | your own use | a team that wants the same review on every machine |

Preview first if you like — `--dry-run` changes nothing:

```bash
./install.sh --dry-run
```

Then install:

```bash
./install.sh                                  # global
# or
./install.sh --project ~/code/my_flutter_app  # one project
```

If you run `./install.sh --project` from inside your app's folder, you can leave the path out.

The installer **never overwrites** an existing file. Anything already there is listed as skipped.

### Step 3 — Check it

```bash
./verify.sh                                   # global
./verify.sh --project ~/code/my_flutter_app   # project
```

You should see a ✅ for git, Dart, each of the six skills, and the review script, ending with
`Result: 0 failure(s)`. Add `--test` to also run the toolkit's own end-to-end tests in a throwaway
folder.

### Step 4 — Restart Claude Code

Close and reopen Claude Code (or reload the VS Code window). Then type `/flutter-review` — you
should see all six commands in the menu.

---

## 4. Connect it to your project

There is nothing to configure. "Connecting" just means opening your Flutter project in Claude
Code:

```bash
cd ~/code/my_flutter_app
claude                     # or open the folder in VS Code and start Claude Code there
```

and typing `/flutter-review-help`. If you see the command list, it's connected.

**Global install:** works in every git project you open — nothing else to do.

**Project install:** to give your team the same skills, commit them:

```bash
cd ~/code/my_flutter_app
git add .claude/skills/flutter-review*
git commit -m "Add flutter-review skills"
```

Teammates get the skills on their next `git pull`; they only need Dart and Claude Code. Do **not**
commit `.claude/.flutter-review-manifest` — it only lists paths on your machine. Add it to your
`.gitignore` if you like.

What flutter-review adds to your project the first time you run it:

| What | Where | Committed? |
|---|---|---|
| Review reports | `.claude/review/*.md` | no — added to `.git/info/exclude` automatically |
| Feature snapshots | `refs/flutter-review/<feature>/…` inside `.git` | no — local refs, `git push` never sends them |

Your `.gitignore` and other tracked files are never changed.

---

## 5. Daily use

```
1. /flutter-review-start cart checkout     before you write any code for the feature
2.   ... build the feature ...              commit, amend, switch files — it doesn't matter
3. /flutter-review                          writes the review to .claude/review/
4.   ... read it, ask Claude to fix things ...
5. /flutter-review-recheck                  reviews only the fixes since step 3
6. /flutter-review-done cart checkout       when the feature is finished
```

- You can have **several features running at once** — give each its own name in step 1, and pass
  the name in steps 3 and 5 (`/flutter-review cart checkout`). Without a name, the most recently
  started feature is used.
- **Forgot step 1?** Run `/flutter-review` anyway. Claude won't guess; it asks you to pick a
  starting point:
  - everything not committed yet (warns that this may include other unfinished work),
  - since one of your last 15 commits, or
  - since a branch, e.g. `origin/main`.
- After reading the review, ask questions about it or ask for changes in plain words
  ("make the repository return an empty list instead of null"). Then run
  `/flutter-review-recheck` to see just those changes.

---

## 6. Commands

| Command | What it does |
|---|---|
| `/flutter-review-start <name>` | Save the starting point for a feature |
| `/flutter-review [name]` | Review everything changed since the start |
| `/flutter-review-recheck [name]` | Review only what changed since the last review |
| `/flutter-review-list` | Show all features with their start date and number of changed files |
| `/flutter-review-done <name>` | Delete that feature's snapshots (reports are kept) |
| `/flutter-review-help` | Show this list |

You can also ask in plain words — "review the code", "show me what you changed",
"start a feature baseline" — and Claude will pick the right command.

The same script runs from any terminal inside a git repo, without Claude:

```bash
R=~/.claude/skills/flutter-review/scripts/review.dart   # project install: .claude/skills/flutter-review/scripts/review.dart
dart run $R start "cart checkout"
dart run $R list
dart run $R done "cart checkout"
dart run $R help
```

---

## 7. The review file

Each review is saved as `.claude/review/<feature>-<yyyyMMdd-HHmm>.md`. The terminal only shows a
link to it; open it in your IDE (Markdown preview works well) whenever you like. Old reviews are
kept, so you can compare.

It contains:

**A summary** of every layer and every file:

```
Changed files: 13

  #  Layer             Files      +lines   -lines
   1 Models                1         +1       -1
   2 Repository            2         +2       -0
   4 Controller            1         +1       -1
   5 UI                    2         +1       -1
  ...

[2] Repository
  added     lib/features/cart/domain/repositories/cart_repository_interface.dart  (+1 -0)
  added     lib/features/cart/domain/repositories/cart_repository.dart  (+1 -0)
[5] UI
  added     lib/features/cart/screens/cart_screen.dart  (+1 -0)
  deleted   lib/features/cart/widgets/old_widget.dart  (+0 -1)
```

**The complete diff of every layer**, 15 lines of context around each change — never shortened.
Deleted files show their full removed content; binary files (images, fonts) show only name and
size.

**Review notes** at the end — up to five per layer: what the layer does for the feature, and
anything worth checking.

You can ask Claude for the full content of one layer's files (not just the changed parts); it is
written to a separate file next to the report.

---

## 8. How it works

### Snapshots

A snapshot records your whole working folder — committed, modified, staged and brand-new files,
but not anything in `.gitignore` — as a git object, **without touching your work**:

1. Copy `.git/index` to a temporary file and point git at the copy (`GIT_INDEX_FILE`).
2. `git add -A` into the copy, then `git write-tree`.
3. `git commit-tree <tree> -p HEAD` to make a snapshot commit.
4. Save it as `refs/flutter-review/<feature>/baseline` (at start) or `…/reviewed` (at each review).
5. Delete the temporary index.

Your real index, working files, `HEAD`, branches and stash are never touched.

### Reviews

A review takes a new snapshot and compares the two trees: `git diff -M <baseline> <now>` for a
review, `<last review> <now>` for a recheck. Because it compares snapshots, not commits, it
doesn't matter what you did with git in between. Renames are detected (`-M`).

### Layers

Every changed file is placed in exactly one layer, by its path. Nothing is dropped.

| # | Layer | Path contains |
|---|---|---|
| 1 | Models | `/models/`, `/model/` |
| 2 | Repository | `/repositories/`, `/repository/`, `/repo/` — interfaces first |
| 3 | Service | `/services/`, `/service/` — interfaces first |
| 4 | Controller | `/controllers/`, `/controller/`, `/bloc/`, `/cubit/`, `/provider/` |
| 5 | UI | `/screens/`, `/screen/`, `/view/`, `/views/`, `/widgets/`, `/widget/`, `/pages/` |
| 6 | Helper & Util | `/helper/`, `/helpers/`, `/util/`, `/utils/`, `/common/` |
| 7 | Config & Assets | `pubspec.yaml`, `assets/`, `android/`, `ios/`, and any other non-Dart file |
| 8 | Tests | `test/`, `integration_test/` |
| 9 | Generated | `*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`, `pubspec.lock` |
| 10 | Unclassified | Dart files that matched nothing above |

Generated and Tests are checked first, then 1 to 7; the first match wins. Inside a layer, files are
sorted by feature folder, then file name.

### What's in this repo

```
flutter-review/
├── install.sh            install globally or into a project
├── uninstall.sh          remove only what install.sh created
├── verify.sh             check an install (read-only); --test runs the tests
├── scripts/lib.sh        shared helpers for the three scripts above
├── skills/
│   ├── flutter-review/              the main skill: review walkthrough and rules
│   │   └── scripts/review.dart      the engine: snapshots, diffs, layers, reports (pure Dart)
│   ├── flutter-review-start/        one small skill per command
│   ├── flutter-review-recheck/
│   ├── flutter-review-list/
│   ├── flutter-review-done/
│   └── flutter-review-help/
├── tests/e2e.sh          40 end-to-end checks in a throwaway folder
├── README.md
├── UNINSTALL.md
└── LICENSE
```

`review.dart` uses only `dart:io` — no packages, no `pub get`.

---

## 9. Customise the layers

If your project uses different folder names (say `/data/` for repositories or `/presentation/`
for UI), edit the `LAYER RULES` block at the top of `skills/flutter-review/scripts/review.dart`:

```dart
2: {
  'contains': ['/repositories/', '/repository/', '/repo/', '/data/'],
},
```

Then reinstall (see [Update](#11-update-and-uninstall)). Because the installer doesn't overwrite
files, you can also edit the installed copy directly. Uninstall will keep it as "modified".

---

## 10. Safety

flutter-review is **read-only toward your work**. It never commits, pushes, stashes, resets,
checks out, or changes your index or branches. The only things it ever writes are:

- refs under `refs/flutter-review/` (local only)
- one temporary index file in your system temp folder, deleted after each snapshot
- review reports under `.claude/review/`
- one line, `/.claude/review/`, in `.git/info/exclude`

Claude only edits your code when you ask for a change after a review.

The test suite checks this: `git status`, `git stash list`, `HEAD`, branches, the index, and the
staged and unstaged diffs are compared before and after every command.

---

## 11. Update and uninstall

### Update

```bash
cd flutter-review
git pull
./uninstall.sh && ./install.sh                         # global
./uninstall.sh --project <path> && ./install.sh --project <path>
```

Files you edited are kept by uninstall and skipped by install, so your changes survive.

### Uninstall

```bash
./uninstall.sh --dry-run          # see what would be removed
./uninstall.sh                    # global
./uninstall.sh --project <path>   # a project
```

It removes only files the installer created, and only if you haven't edited them. Your feature
snapshots and saved reports stay in your projects. [UNINSTALL.md](UNINSTALL.md) shows how to
remove those too, and how to remove everything by hand.

---

## 12. FAQ and troubleshooting

**Do I have to commit before reviewing?**
No. Uncommitted, staged and brand-new files are all included.

**Will my teammates see my snapshots?**
No. They live under `refs/flutter-review/`, which `git push` never sends.

**Does it slow down my repo?**
No. A snapshot reuses git's file cache and only stores file contents git doesn't already have.
Old snapshots are cleaned up by git's normal garbage collection after `/flutter-review-done`.

**The commands don't show up after installing.**
Restart Claude Code or reload the VS Code window. Then run `./verify.sh` — every line should be ✅.

**`./install.sh` says "exists and differs — left untouched".**
You already have a different version in that folder (for example a copy made by hand). Remove it
(`rm -r ~/.claude/skills/flutter-review*`) and run `./install.sh` again.

**`dart: command not found`.**
Add Flutter's `bin` folder to your `PATH` — the same one that has `flutter`.

**`Not inside a git repository`.**
Run `git init` in your Flutter project once. No commits are needed, though with no commits only
`/flutter-review-start` can set the starting point.

**A file landed in "Unclassified".**
Its path matched none of the layer rules. Add its folder to the right layer — see
[Customise the layers](#9-customise-the-layers).

**Windows?**
Use Git Bash for `install.sh`. The review script itself is plain Dart and runs anywhere Dart runs.

---

## License

[MIT](LICENSE)

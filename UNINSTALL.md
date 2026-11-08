# Uninstall

## Automatic

```bash
cd flutter-review
./uninstall.sh --dry-run          # list what would be removed
./uninstall.sh                    # global install
./uninstall.sh --project <path>   # a project install
```

- Removes only files listed in `<claude dir>/.flutter-review-manifest` (the files `install.sh`
  created), and only if they are **unchanged** since install. Files you edited are kept and listed.
- Removes skill folders it emptied; never a folder that still has content.
- Never touches your code, your feature snapshots or your saved reports.

## Manual removal

```bash
rm -r ~/.claude/skills/flutter-review ~/.claude/skills/flutter-review-{start,recheck,list,done,help}
rm ~/.claude/.flutter-review-manifest
```

For a project install, run the same inside `<project>/.claude/`.

## Snapshots and reports in your projects

Uninstalling the skills leaves these in each project where you used them. To remove them, from
inside the project:

```bash
git for-each-ref --format='%(refname)' refs/flutter-review/ | xargs -n1 git update-ref -d
rm -r .code-review
```

Then delete the `/.code-review/` line from `.git/info/exclude` if you like. The snapshot commit
objects are unreferenced after the refs are gone; git's normal garbage collection removes them.

## Temporarily disable without uninstalling

Move the `flutter-review*` folders out of `~/.claude/skills/` and restart Claude Code.

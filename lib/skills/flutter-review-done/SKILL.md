---
name: flutter-review-done
description: Delete a feature's flutter-review baseline and review refs when the feature is finished. Use for /flutter-review-done <name>.
argument-hint: <feature-name>
disable-model-invocation: true
---

If no name was given, run `list` (below) and ask which one. Then run from the project
directory and show the output exactly as printed:

```bash
dart run "{{REVIEW_SCRIPT}}" done <feature-name>
```

This only deletes refs under `refs/flutter-review/<slug>/`. Saved reports in
`.claude/review/` stay.

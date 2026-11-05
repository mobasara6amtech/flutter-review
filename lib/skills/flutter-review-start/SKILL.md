---
name: flutter-review-start
description: Save a flutter-review baseline snapshot of the working tree before starting a feature. Use for /flutter-review-start <name> or "start a feature baseline".
argument-hint: <feature-name>
---

Run from the project directory:

```bash
dart run "{{REVIEW_SCRIPT}}" start <feature-name>
```

If no name was given, ask for one. Show the output exactly as printed.
Safety rules are in `{{SKILLS_DIR}}/flutter-review/SKILL.md`.

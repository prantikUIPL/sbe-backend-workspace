---
name: feature-branch-creator
description: Sync local `dev` with `origin/dev`, cut a new `feature/<jira-ticket-small-description>` branch off of it, and push it to `origin` with upstream tracking. In this project, feature branches are always cut from `dev`. Takes the description as the slash-command argument; prompts for it if missing. Invoke via `/feature-branch-creator <jira-ticket-small-description>`.
---

# feature-branch-creator

## Resolve argument

If the user did not supply a description (no argument or only whitespace), ask:
*"What's the description for the new branch (the part after `feature/`)?"*
— do not guess, do not proceed without it.

## Run

Once you have the description, run from within the target git repository:

```sh
bash scripts/feature-branch-creator.sh "<description>"
```

On non-zero exit, relay the error to the user verbatim. On success, relay the one-line confirmation. Do not editorialize or add flags to the command.

---
name: rebase-feature-on-dev
description: Sync local `dev` with `origin/dev`, then rebase a feature branch on top of the freshly-synced `dev`. Takes the feature branch name as the slash-command argument; prompts for it if missing. Composes the `sync-dev-branch` skill. Invoke via `/rebase-feature-on-dev <feature-branch-name>`.
---

# rebase-feature-on-dev

## Resolve argument

If the user did not supply a branch name (no argument or only whitespace), ask:
*"Which feature branch should I rebase onto dev?"*
— do not guess, do not fall back to the current branch silently.

## Run

Once you have the branch name, run from within the target git repository:

```sh
bash scripts/rebase-feature-on-dev.sh "<branch-name>"
```

On non-zero exit, relay the error to the user verbatim. On success, relay the one-line confirmation (the script notes it has not pushed). Do not editorialize or add flags to the command.

---
name: sync-dev-branch
description: Sync the local `dev` branch with `origin/dev` via a hard reset, treating the remote as the source of truth. Aborts if the working tree is dirty. Invoke via `/sync-dev-branch`.
---

# sync-dev-branch

Run the sync script from within the target git repository. No arguments.

```sh
bash scripts/sync-dev-branch.sh
```

On non-zero exit, relay the error to the user verbatim. On success, relay the one-line HEAD summary. Do not editorialize or add next-steps.

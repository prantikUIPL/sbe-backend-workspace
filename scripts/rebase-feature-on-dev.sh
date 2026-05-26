#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sync-dev-branch.sh"

if [[ -z "${1:-}" ]]; then
    echo "ERROR: No branch name provided." >&2
    echo "Usage: bash scripts/rebase-feature-on-dev.sh <branch-name>" >&2
    exit 1
fi

BRANCH="$1"

# Normalize: prepend feature/ if no "/" present
if [[ "$BRANCH" != */* ]]; then
    BRANCH="feature/$BRANCH"
fi

if [[ -z "$BRANCH" ]]; then
    echo "ERROR: Branch name is empty after normalization." >&2
    exit 1
fi

if ! [[ "$BRANCH" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
    echo "ERROR: Branch name contains invalid characters." >&2
    echo "Allowed: letters, digits, '.', '_', '/', '-'" >&2
    echo "Got: $BRANCH" >&2
    exit 1
fi

# Refuse protected branches
if [[ "$BRANCH" == "dev" || "$BRANCH" == "master" || "$BRANCH" == "main" ]]; then
    echo "ERROR: Cannot rebase '$BRANCH' — this skill is for feature branches only." >&2
    exit 1
fi

# Preconditions
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Not inside a git repository." >&2
    exit 2
fi

if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "ERROR: Branch '$BRANCH' does not exist locally." >&2
    exit 2
fi

status="$(git status --porcelain)"
if [[ -n "$status" ]]; then
    echo "ERROR: Working tree is dirty." >&2
    echo "$status" >&2
    exit 2
fi

# Check no rebase in progress
REBASE_MERGE="$(git rev-parse --git-path rebase-merge)"
REBASE_APPLY="$(git rev-parse --git-path rebase-apply)"
if [[ -d "$REBASE_MERGE" || -d "$REBASE_APPLY" ]]; then
    echo "ERROR: A rebase is already in progress. Finish or abort it first." >&2
    exit 2
fi

# Sync dev
if ! sync_dev_branch; then
    exit 3
fi

# Checkout feature branch
git checkout "$BRANCH"

# Re-check clean after checkout
status="$(git status --porcelain)"
if [[ -n "$status" ]]; then
    echo "ERROR: Working tree is dirty after checkout to '$BRANCH'." >&2
    echo "$status" >&2
    exit 2
fi

# Capture pre-rebase state
OLD_HEAD="$(git rev-parse --short HEAD)"

# Attempt rebase
if ! git rebase dev 2>&1; then
    CONFLICTED="$(git diff --name-only --diff-filter=U 2>/dev/null || true)"
    git rebase --abort
    echo "Rebase of '$BRANCH' onto dev hit conflicts — aborted."
    if [[ -n "$CONFLICTED" ]]; then
        echo "Conflicted files:"
        echo "$CONFLICTED"
    fi
    exit 4
fi

NEW_HEAD="$(git rev-parse --short HEAD)"
DEV_SHA="$(git rev-parse --short dev)"
echo "Rebased '$BRANCH' onto dev (was $OLD_HEAD, now $NEW_HEAD based on origin/dev $DEV_SHA). Not pushed — use 'git push --force-with-lease' when ready."

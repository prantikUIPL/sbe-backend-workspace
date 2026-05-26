#!/usr/bin/env bash
set -euo pipefail

sync_dev_branch() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "ERROR: Not inside a git repository." >&2
        return 1
    fi

    if ! git show-ref --verify --quiet refs/heads/dev; then
        echo "ERROR: Local branch 'dev' does not exist." >&2
        return 1
    fi

    local status
    status="$(git status --porcelain)"
    if [[ -n "$status" ]]; then
        echo "ERROR: Working tree is dirty. Clean it before syncing." >&2
        echo "$status" >&2
        return 1
    fi

    local current_branch
    current_branch="$(git rev-parse --abbrev-ref HEAD)"
    if [[ "$current_branch" != "dev" ]]; then
        git checkout dev
    fi

    git fetch origin

    if ! git show-ref --verify --quiet refs/remotes/origin/dev; then
        echo "ERROR: Remote branch 'origin/dev' does not exist." >&2
        return 1
    fi

    # Re-check tree clean after checkout
    status="$(git status --porcelain)"
    if [[ -n "$status" ]]; then
        echo "ERROR: Working tree is dirty after checkout to dev." >&2
        echo "$status" >&2
        return 1
    fi

    git reset --hard origin/dev

    echo "Synced dev to origin/dev."
    git log -1 --oneline
    git status -sb
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sync_dev_branch
fi

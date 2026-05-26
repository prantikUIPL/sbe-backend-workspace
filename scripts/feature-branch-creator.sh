#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sync-dev-branch.sh"

if [[ -z "${1:-}" ]]; then
    echo "ERROR: No branch description provided." >&2
    echo "Usage: bash scripts/feature-branch-creator.sh <description>" >&2
    exit 1
fi

DESC="$1"

# Strip leading "feature/" if present
DESC="${DESC#feature/}"

if [[ -z "$DESC" ]]; then
    echo "ERROR: Description is empty after stripping 'feature/' prefix." >&2
    exit 1
fi

if ! [[ "$DESC" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
    echo "ERROR: Description contains invalid characters." >&2
    echo "Allowed: letters, digits, '.', '_', '/', '-'" >&2
    echo "Got: $DESC" >&2
    exit 1
fi

# Check branch doesn't exist locally
if git show-ref --verify --quiet "refs/heads/feature/$DESC"; then
    echo "ERROR: Branch 'feature/$DESC' already exists locally." >&2
    exit 2
fi

# Sync dev (this also does git fetch origin, refreshing remote refs)
if ! sync_dev_branch; then
    exit 3
fi

# Check branch doesn't exist on remote (after fetch)
if git show-ref --verify --quiet "refs/remotes/origin/feature/$DESC"; then
    echo "ERROR: Branch 'feature/$DESC' already exists on origin." >&2
    exit 2
fi

# Create and checkout new branch off dev
git checkout -b "feature/$DESC"

# Push with upstream tracking
if ! git push -u origin "feature/$DESC"; then
    echo "ERROR: Failed to push 'feature/$DESC' to origin." >&2
    exit 4
fi

BASE_SHA="$(git rev-parse --short dev)"
echo "Pushed feature/$DESC to origin, tracking origin/feature/$DESC, based on origin/dev at $BASE_SHA."
git status -sb

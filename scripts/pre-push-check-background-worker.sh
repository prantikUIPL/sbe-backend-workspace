#!/usr/bin/env bash
set -euo pipefail

# Pre-push stability gate for background-worker-service (5 steps)

step() { echo "Step $1: $2…"; }
fail() { echo "FAILED at step $1: $2" >&2; exit 1; }

# --- Preconditions ---

PKG_NAME="$(node -p "require('./package.json').name" 2>/dev/null || true)"
if [[ "$PKG_NAME" != "sbe-background-worker" ]]; then
    echo "ERROR: Must run from background-worker-service root (found package: '$PKG_NAME')." >&2
    exit 1
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Not inside a git repository." >&2
    exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" == "master" || "$BRANCH" == "dev" ]]; then
    echo "ERROR: Cannot run on '$BRANCH' — switch to a feature branch." >&2
    exit 1
fi

NODE_MAJOR="$(node -v | sed 's/v\([0-9]*\).*/\1/')"
if [[ "$NODE_MAJOR" != "24" ]]; then
    echo "WARNING: Expected Node 24, got v$NODE_MAJOR. Continuing anyway."
fi

# --- Pipeline ---

step "1/5" "prisma generate"
npx prisma generate || fail "1/5" "prisma generate failed"

step "2/5" "typecheck"
npm run typecheck || fail "2/5" "typecheck failed"

step "3/5" "lint:check"
npm run lint:check || fail "3/5" "lint:check failed"

step "4/5" "test:cov"
npm run test:cov || fail "4/5" "test:cov failed"

step "5/5" "build"
npm run build || fail "5/5" "build failed"

echo "All 5 checks passed — branch is push-ready."

#!/usr/bin/env bash
set -euo pipefail

# Pre-push stability gate for exhibitor-backend-api (6 steps)

step() { echo "Step $1: $2…"; }
fail() { echo "FAILED at step $1: $2" >&2; exit 1; }

# --- Preconditions ---

PKG_NAME="$(node -p "require('./package.json').name" 2>/dev/null || true)"
if [[ "$PKG_NAME" != "exhibitor-backend-api" ]]; then
    echo "ERROR: Must run from exhibitor-backend-api root (found package: '$PKG_NAME')." >&2
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

step "1/6" "npm ci"
if [[ ! -f package-lock.json ]]; then
    fail "1/6" "package-lock.json missing — cannot run npm ci"
fi
npm ci || fail "1/6" "npm ci failed"

step "2/6" "prisma generate"
npx prisma generate || fail "2/6" "prisma generate failed"

step "3/6" "typecheck"
npm run typecheck || fail "3/6" "typecheck failed"

step "4/6" "lint:check"
npm run lint:check || fail "4/6" "lint:check failed"

step "5/6" "test:cov"
npm run test:cov || fail "5/6" "test:cov failed"

step "6/6" "build"
npm run build || fail "6/6" "build failed"

echo "All 6 checks passed — branch is push-ready."

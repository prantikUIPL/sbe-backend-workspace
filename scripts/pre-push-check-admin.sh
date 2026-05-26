#!/usr/bin/env bash
set -euo pipefail

# Pre-push stability gate for admin-backend-api (8 steps)
# Expects PRISMA_USER_CONSENT_FOR_DANGEROUS_AI_ACTION env var for db:reset step.

step() { echo "Step $1: $2…"; }
fail() { echo "FAILED at step $1: $2" >&2; exit 1; }

# --- Preconditions ---

PKG_NAME="$(node -p "require('./package.json').name" 2>/dev/null || true)"
if [[ "$PKG_NAME" != "sbe-admin-backend-api" ]]; then
    echo "ERROR: Must run from admin-backend-api root (found package: '$PKG_NAME')." >&2
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

if [[ ! -f .env ]]; then
    echo "ERROR: .env file missing. Populate it with DATABASE_URL." >&2
    exit 1
fi

NODE_MAJOR="$(node -v | sed 's/v\([0-9]*\).*/\1/')"
if [[ "$NODE_MAJOR" != "24" ]]; then
    echo "WARNING: Expected Node 24, got v$NODE_MAJOR. Continuing anyway."
fi

NODE_ENV_VAL="$(grep -E '^NODE_ENV=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
if [[ -n "$NODE_ENV_VAL" && "$NODE_ENV_VAL" != "local" && "$NODE_ENV_VAL" != "dev" && "$NODE_ENV_VAL" != "development" ]]; then
    echo "ERROR: NODE_ENV='$NODE_ENV_VAL' looks production-adjacent. Refusing to reset database." >&2
    exit 1
fi

if [[ -z "${PRISMA_USER_CONSENT_FOR_DANGEROUS_AI_ACTION:-}" ]]; then
    DB_URL="$(grep -E '^DATABASE_URL=' .env | cut -d= -f2 | tr -d '"')"
    DB_TARGET="$(echo "$DB_URL" | sed 's|.*@||; s|?.*||')"
    echo "NEEDS_CONSENT"
    echo "DB_TARGET: $DB_TARGET"
    exit 5
fi

# --- Pipeline ---

step "1/8" "npm ci"
if [[ ! -f package-lock.json ]]; then
    fail "1/8" "package-lock.json missing — cannot run npm ci"
fi
npm ci || fail "1/8" "npm ci failed"

step "2/8" "prisma generate"
npx prisma generate || fail "2/8" "prisma generate failed"

step "3/8" "db:reset"
npm run db:reset || fail "3/8" "db:reset failed"

step "4/8" "seed"
npx ts-node -r tsconfig-paths/register src/database/seeds/run-seeds.ts || fail "4/8" "seeding failed"

step "5/8" "typecheck"
npm run typecheck || fail "5/8" "typecheck failed"

step "6/8" "lint:check"
npm run lint:check || fail "6/8" "lint:check failed"

step "7/8" "test:cov"
npm run test:cov || fail "7/8" "test:cov failed"

step "8/8" "build"
npm run build || fail "8/8" "build failed"

echo "All 8 checks passed — branch is push-ready."

# SBE APIs

Five NestJS backends sharing the same PostgreSQL database. Each sub-folder is its own git repo; feature branches cut from `dev`.

- `admin-backend-api/` — Admin panel backend
- `exhibitor-backend-api/` — Exhibitor-facing backend
- `background-worker-service/` — Background jobs / async workers
- `external-api-service/` — External-facing API service
- `pulse-broker-service/` — Event/message broker service

## Database & Prisma

All five have `prisma/schema.prisma`. When out of sync, **`admin-backend-api` is the source of truth** — it owns migrations (`prisma/migrations/`) and seeding. The other four services use `db push` only.

## Node

Requires Node 24 (`>=24 <25`).

## Scripts

Branch management scripts in `scripts/` (sync-dev, create feature branch, rebase onto dev).

## CI / Bitbucket Pipelines

All five repos live in Bitbucket workspace `unified-dev-cls-a` and run Pipelines (incl. SonarQube). Check build status with `scripts/check-pipelines.sh`:

- `./scripts/check-pipelines.sh` — latest pipeline per repo (all 5)
- `./scripts/check-pipelines.sh <repo> [--branch <b>]` — one repo, optionally a branch
- `./scripts/check-pipelines.sh <repo> --logs <build#>` — dump failed-step logs (where SonarQube failures appear)

Auth: a scoped **Atlassian API token** (basic auth, `email:token`) read from gitignored `scripts/.bitbucket-creds` (`BB_EMAIL` + `BB_API_TOKEN`) or matching env vars. Used on demand to verify builds and triage SonarQube quality-gate failures.

The pipeline steps run in order: **Secret scan (gitleaks)** → **Lint, typecheck, and test** → **SonarQube scan and quality gate**. A later step shows `NOT_RUN` when an earlier one fails, so always confirm *which* step actually failed before assuming SonarQube.

## SonarQube

Self-hosted **SonarQube Community Edition** at `https://sonar.techbreeze.in`. Community has **no per-branch / per-PR analysis** — every scan overwrites a single main project, so only the *latest* analysis is queryable (no historical PR snapshots). Each repo's `sonar.projectKey` is in its `sonar-project.properties`.

Read gate status and issues with `scripts/check-sonar.sh` (auth: `SONAR_HOST_URL` + `SONAR_TOKEN` user token in gitignored `scripts/.sonar-creds`):

- `./scripts/check-sonar.sh` — quality gate for all 5 repos
- `./scripts/check-sonar.sh <repo> --issues` — open **new-code** issues + hotspots, each tagged with its SonarQube author (git-blame email)

**SonarQube is READ-ONLY** — never write to it (no marking hotspots reviewed, no changing issue status/gates).

### When a code push trips SonarQube

1. **Check the pipeline first** (`check-pipelines.sh <repo> --logs <build#>`) to confirm the failure was the **SonarQube quality gate** — not gitleaks or lint/test.
2. If SonarQube: look at **new-code issues only** (`check-sonar.sh <repo> --issues`).
3. For each, **verify it's from our change** (cross-check the author / `git blame` on the file+line). Only fix issues introduced by our own code.
4. **Do not touch issues introduced by someone else.**

All fixes are proposed for the user to review and commit (no auto-commit/push).

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

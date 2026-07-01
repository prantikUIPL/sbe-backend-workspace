# SBE APIs

Five NestJS backends sharing one PostgreSQL database. Each sub-folder is its own git repo; feature branches cut from `dev`. Requires Node 24 (`>=24 <25`).

- `admin-backend-api/` — Admin panel backend
- `exhibitor-backend-api/` — Exhibitor-facing backend
- `background-worker-service/` — Background jobs / async workers
- `external-api-service/` — External-facing API service
- `pulse-broker-service/` — Event/message broker service

## Database & Prisma

All five have `prisma/schema.prisma`. When out of sync, **`admin-backend-api` is the source of truth** — it owns migrations (`prisma/migrations/`) and seeding; the other four use `db push` only.

## Scripts

Branch management in `scripts/` (sync-dev, create feature branch, rebase onto dev).

## Jira & Confluence

Live access via Atlassian MCP tools — use **on demand** to pull the authoritative source when work references a ticket/story (don't guess from local docs). Read-only by default: no creating/editing/transitioning Jira issues or editing Confluence pages unless explicitly asked.

- **Jira** — fetch a ticket by key (e.g. `SBE-xxx`, carried in the feature branch name) for description, acceptance criteria, status, links.
- **Confluence** — fetch story/epic pages for full requirements. Reference pages:
  - **SBE — Exhibitor Store Application** (`3858137106`): https://unifiedinfotech.atlassian.net/wiki/spaces/SBE/pages/3858137106/SBE+-+Exhibitor+Store+Application
  - **SBE — Admin Panel** (`3859742741`): https://unifiedinfotech.atlassian.net/wiki/spaces/SBE/pages/3859742741/SBE+-+Admin+Panel

## CI / Bitbucket Pipelines

All five repos live in Bitbucket workspace `unified-dev-cls-a` and run Pipelines (incl. SonarQube). Check build status with `scripts/check-pipelines.sh`:

- `./scripts/check-pipelines.sh` — latest pipeline per repo (all 5)
- `./scripts/check-pipelines.sh <repo> [--branch <b>]` — one repo, optionally a branch
- `./scripts/check-pipelines.sh <repo> --logs <build#>` — dump failed-step logs (where SonarQube failures appear)

Auth: scoped **Atlassian API token** (basic auth, `email:token`) from gitignored `scripts/.bitbucket-creds` (`BB_EMAIL` + `BB_API_TOKEN`) or matching env vars.

Steps run in order: **Secret scan (gitleaks)** → **Lint, typecheck, test** → **SonarQube scan and quality gate**. A later step shows `NOT_RUN` when an earlier one fails — always confirm *which* step failed before assuming SonarQube.

## SonarQube

Self-hosted **Community Edition** at `https://sonar.techbreeze.in`. Community has **no per-branch/per-PR analysis** — every scan overwrites one main project, so only the *latest* analysis is queryable. Each repo's `sonar.projectKey` is in its `sonar-project.properties`.

Read gate + issues with `scripts/check-sonar.sh` (auth: `SONAR_HOST_URL` + `SONAR_TOKEN` in gitignored `scripts/.sonar-creds`):

- `./scripts/check-sonar.sh` — quality gate for all 5 repos
- `./scripts/check-sonar.sh <repo> --issues` — open **new-code** issues + hotspots, each tagged with its SonarQube author (git-blame email)

**SonarQube is READ-ONLY** — never write to it (no marking hotspots reviewed, no changing issue status/gates).

### When a code push trips SonarQube

1. **Check the pipeline first** (`check-pipelines.sh <repo> --logs <build#>`) to confirm the failure was the **SonarQube quality gate** — not gitleaks or lint/test.
2. If SonarQube: look at **new-code issues only** (`check-sonar.sh <repo> --issues`).
3. For each, **verify it's from our change** (author / `git blame` on file+line) — fix only issues our own code introduced.
4. **Do not touch issues introduced by someone else.**

All fixes are proposed for the user to review and commit (no auto-commit/push).

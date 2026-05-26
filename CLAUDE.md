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

# Schema Drift Register — SBE APIs

> **Recorded:** 2026-06-08 (during SBE-671, Email & SMS Management schema foundation)
> **Scope:** PostgreSQL `sbe_database` shared by all five NestJS services.
> **Purpose:** A point-in-time record of the schema drift that exists *today*, so it
> can be reconciled deliberately in a future, dedicated effort. This drift is
> **pre-existing and unrelated to SBE-671** — SBE-671's own objects are clean (see
> [SBE-671 exclusion](#sbe-671-changes-are-not-drift)).

---

## TL;DR

- **`prisma migrate reset` / fresh rebuild WORKS** — all 106 migrations apply cleanly from an
  empty database with no errors.
- **But a freshly-rebuilt DB still drifts from `admin-backend-api/prisma/schema.prisma`** by
  **201 statements**. This drift is **baked into the migration history vs the Prisma schema** —
  it is *not* an artifact of `db push` dirtying the live DB, and it reproduces identically on a
  clean reset.
- **~95% of the drift is cosmetic** (legacy index/FK naming, `updated_at` defaults) and harmless
  at runtime. **A small set is genuine and worth fixing** — most importantly **missing unique
  constraints** (`users.email`, `exhibitors.email`, …) and a **table declared in the schema but
  never migrated** (`role_permission_audit_logs`).

---

## How this was measured

```bash
# 1. Confirm a clean rebuild works (into a throwaway DB, non-destructive):
createdb sbe_drift_check
DATABASE_URL=...sbe_drift_check npx prisma migrate deploy      # -> all 106 apply, no errors

# 2. Measure drift of the rebuilt DB vs the Prisma schema:
DATABASE_URL=...sbe_drift_check \
  npx prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --exit-code
#   exit 2 = drift present

# 3. Dump the exact SQL it would take to reconcile DB -> schema:
npx prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --script
```

The live `sbe_database` and the freshly-rebuilt `sbe_drift_check` produced the **identical**
201-statement diff — proving the drift originates in `migrations ⇄ schema.prisma`, not in the
live database's history.

---

## Per-repo / per-database status

All five services share `localhost:5432/sbe_database`. Drift was checked with
`prisma migrate diff --from-config-datasource --to-schema <repo>/prisma/schema.prisma --exit-code`.

| Repo | Owns migrations? | Has local `DATABASE_URL`? | Drift vs shared DB |
|---|---|---|---|
| **admin-backend-api** | ✅ yes | ✅ | **DRIFT — 201 stmts** (the subject of this doc) |
| exhibitor-backend-api | ❌ `db push` | ✅ | in sync* |
| external-api-service | ❌ `db push` | ✅ | in sync* |
| background-worker-service | ❌ `db push` | ❌ (none) | DRIFT (missing cols/enum values) |
| pulse-broker-service | ❌ `db push` | ❌ (none) | DRIFT (most stale) |

\* "in sync" is partly a **Prisma blind spot**: `migrate diff` does **not** report DB enum values
that are *absent* from a schema (removing enum values is unsupported), so a stale enum reads as
"in sync." See [Cross-repo enum staleness](#cross-repo-enum-staleness).

---

## Drift breakdown (admin schema, 201 statements)

| Category | Count | Nature | Severity |
|---|---|---|---|
| DropIndex | 94 | Legacy `idx_*` single-column indexes exist in migrations but aren't declared in `schema.prisma` | Cosmetic |
| AlterTable | 45 | Mostly `updated_at` default `Now → None`; a few genuine column changes | Mixed |
| RenameForeignKey | 29 | `fk_*` → Prisma's `*_fkey` | Cosmetic |
| RenameIndex | 11 | `idx_*` → Prisma's `*_idx` / `*_key` | Cosmetic |
| CreateIndex | 11 | Unique/index constraints in schema but not in migrations | **Some genuine** |
| AddForeignKey | 6 | FKs re-added (naming / `role_permission_audit_logs`) | Mixed |
| DropForeignKey | 4 | FKs dropped then re-added (naming normalization) | Cosmetic |
| CreateTable | 1 | `role_permission_audit_logs` — in schema, not in migrations | **Genuine** |

---

## What needs to be corrected, and how

### Priority 1 — Genuine correctness gaps (fix these)

These are differences where the **migration-built database is missing guarantees the schema
promises**. On a fresh reset, these constraints/objects would not exist.

1. **`role_permission_audit_logs` table is declared in `schema.prisma` but no migration creates it.**
   - *Risk:* a fresh reset produces a DB without this table; any code writing role-permission
     audit rows would fail. It only exists on the current live DB because `db push` created it.
   - *Fix:* add a migration that `CREATE TABLE "role_permission_audit_logs"` plus its indexes
     (`role_id`, `performed_by`, `created_at`) and FKs (`role_id → roles`, `performed_by → users`).

2. **Missing UNIQUE constraints that the schema declares:**
   | Table | Unique columns | Why it matters |
   |---|---|---|
   | `users` | `email` | login identity — duplicates must be impossible |
   | `exhibitors` | `email` | login identity |
   | `exhibitors` | `company_id` | 1:1 exhibitor↔company invariant |
   | `gift_certificates` | `name` | business uniqueness |
   | `company_industries` | `(company_id, industry_id)` | prevents duplicate links |
   | `shows` | `(city_id, title)` | prevents duplicate shows |
   - *Fix:* one migration adding these `CREATE UNIQUE INDEX … _key` constraints. **Before adding,
     audit existing data for duplicates** (each `ADD UNIQUE` fails if duplicates exist).

3. **Nullable → Required column tightenings declared in schema but not migrated:**
   - `attendees.full_name` — present in migrations, **removed in schema** (drop the column, or
     re-add it to schema if still used — confirm first).
   - `gift_certificate_purchases`: `uuid`, `created_at`, `updated_at` → NOT NULL; `expire_at` → `TIMESTAMPTZ(6)`.
   - `gift_certificates`: `status`, `created_at`, `updated_at` → NOT NULL.
   - `notification_logs.language`, `notification_templates.language` → NOT NULL.
   - `shows.nunify_event_code`, `shows.nunify_event_id` → NOT NULL.
   - `subscription_plans.currency` → NOT NULL.
   - *Fix:* per column, **backfill any NULLs first**, then a migration `ALTER COLUMN … SET NOT NULL`
     (and `SET DATA TYPE` for `expire_at`). Decide explicitly on `attendees.full_name` (drop vs keep).

4. **Removed unique indexes** (schema no longer wants them, migrations still create them):
   - `permissions (module, method, url)`, `user_sessions.access_token`, `user_sessions.refresh_token`.
   - *Fix:* confirm intent (were these deliberately relaxed?), then a migration `DROP INDEX` if so.

### Priority 2 — Cosmetic naming normalization (large, low-risk, optional)

The bulk of the 201 statements: legacy `idx_*` / `fk_*` names from the hand-authored
`20260303120000_init` migration (derived from `src/database/sql/seed.sql`) vs Prisma's
`*_idx` / `*_fkey` / `*_key` conventions, plus `updated_at` columns carrying
`DEFAULT CURRENT_TIMESTAMP` while the schema's `@updatedAt` expects no DB default.

- **Two ways to resolve:**
  - **(a) Make schema match reality** — add the legacy `@@index`/`@map` declarations and the
    `updated_at` defaults to `schema.prisma`. Lowest-risk; no DB change; shrinks the diff to near-zero.
  - **(b) Make the DB match the schema** — generate one big normalization migration that renames
    everything to Prisma conventions and drops the extra defaults. Cleaner long-term, but a large,
    churny migration.
- **Recommendation:** option (a) for the 94 dropped indexes + 40 `updated_at` defaults (declare them
  in schema), so the only *real* migration work is the Priority-1 list.

### Cross-repo enum staleness

`AdminAuditEntityType` is **out of sync across the four non-owner schemas** (DB has 21 values):

| Schema | `AdminAuditEntityType` values |
|---|---|
| live DB / admin | **21** (current) |
| exhibitor-backend-api | 15 (stale) |
| background-worker-service | 15 (stale) |
| external-api-service | 15 (stale) |
| pulse-broker-service | **8** (most stale) |

- *Why it's invisible:* the four read this enum but don't own migrations; Prisma's drift check
  ignores DB enum values missing from a schema, so they don't surface as drift.
- *Fix:* when the four next touch admin-audit functionality, sync their `AdminAuditEntityType`
  enum to the full 21-value list (source of truth: `admin-backend-api/prisma/schema.prisma`).
  Not urgent — none of the four write these audit rows today.

---

## SBE-671 changes are NOT drift

The Email & SMS schema foundation (this branch) is fully consistent between the migrations and
`schema.prisma`. Verified: none of `trigger_events`, `allowed_from_domains`, the `NotificationChannel`
/ `NotificationTemplateType` enums, the new `notification_templates` columns, the channel→enum
conversion, or the `notification_type → trigger_events.slug` FK appear in the drift diff.

The only notification-related lines in the drift are **pre-existing** and predate SBE-671:
`DROP INDEX idx_notification_templates_{channel,is_active,notification_type}` (legacy init indexes)
and `notification_templates.language SET NOT NULL` (Priority-1 item #3).

---

## Recommended reconciliation plan (future ticket)

1. **Audit data** for duplicates / NULLs against every Priority-1 constraint (read-only queries).
2. **Migration A — genuine fixes:** create `role_permission_audit_logs`; add the 6 unique
   constraints; apply the NOT NULL tightenings (after backfill); resolve `attendees.full_name`.
3. **Migration B (optional) — cosmetic:** either declare legacy indexes/defaults in `schema.prisma`
   (preferred) or rename DB objects to Prisma conventions.
4. **Sync the four non-owner schemas'** `AdminAuditEntityType` (and any other stale enums) to admin.
5. **Verify:** `migrate diff --from-config-datasource --to-schema --exit-code` returns **0**.

**Do not run `prisma migrate dev` against `sbe_database` before this is done** — it would
auto-generate the entire 201-statement reconciliation in one shot, including the destructive
`DROP COLUMN attendees.full_name` and index drops. Use targeted, reviewed migrations + `migrate deploy`.

---

## Appendix — reproduce this report

```bash
cd admin-backend-api
# Full human-readable summary:
npx prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma
# Full SQL the reconciliation would emit:
npx prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --script
```

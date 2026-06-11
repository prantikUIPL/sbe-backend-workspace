# SBE-671 Re-implementation Introduced No New Schema Drift — Evidence

> **Date:** 2026-06-11
> **Branch:** `feature/SBE-671` (Email & SMS Management — schema foundation, re-applied after teardown)
> **Companion:** [`schema-drift-2026-06-08.md`](./schema-drift-2026-06-08.md) — the pre-existing
> drift register; [`sbe-671-no-new-drift-2026-06-08.md`](./sbe-671-no-new-drift-2026-06-08.md) — the
> prior (torn-down) implementation's evidence, kept for history.

## Claim

The re-applied SBE-671 schema foundation added **zero** new schema drift. The drift between
`admin-backend-api/prisma/schema.prisma` and a migration-built database is **201 statements,
bucket-for-bucket identical** to the pre-existing register:

| Drift bucket | Register (2026-06-08, pre-SBE-671) | Current (2026-06-11, with SBE-671) |
|---|---|---|
| DropIndex | 94 | 94 |
| AlterTable | 45 | 45 |
| RenameForeignKey | 29 | 29 |
| RenameIndex | 11 | 11 |
| CreateIndex | 11 | 11 |
| AddForeignKey | 6 | 6 |
| DropForeignKey | 4 | 4 |
| CreateTable | 1 | 1 |
| **Total** | **201** | **201** |

## What this implementation changed (differences vs the 2026-06-08 attempt)

- **One** hand-authored migration instead of two: `20260611120000_sbe671_email_sms_management`
  (migration #106; the enum value, id conversion, channel promotion, new columns + backfill,
  new tables, and FK all in one file).
- Column is **`tag`**, not `type` (TL review 2026-06-10).
- **FK design amended**: `trigger_events.slug` is **globally unique** (`@unique`) and the FK +
  relation are declared natively in Prisma — the previously designed composite-unique
  `(slug, is_custom)` + partial-index FK is not implementable (Postgres FKs cannot reference
  partial unique indexes). Because every SBE-671 object is now fully declared in `schema.prisma`,
  a `db push` from any of the 5 repos cannot drop SBE-671 objects.
- **Int PKs**: `notification_templates.id` converted BigInt→Int (with
  `notification_logs.notification_template_id`); `trigger_events` / `allowed_from_domains` use
  `SERIAL` Int PKs. The `notification_logs` FK was re-created under its **original legacy name**
  (`fk_notification_logs_notification_template_id`) so the pre-existing RenameForeignKey drift
  count is unchanged.
- `template_name` / `tag` are **NOT NULL** (migration backfills placeholders, seeder overwrites).
- New-table `updated_at` columns carry `DEFAULT CURRENT_TIMESTAMP` in SQL **and**
  `@default(now()) @updatedAt` in Prisma — checked specifically because the first draft omitted the
  Prisma-side default and produced 2 new drift lines; fixed before commit.

## Evidence (drift diff contains no SBE-671 object)

`npx prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --script`
against the freshly `migrate reset` database (all 106 migrations + seeds): grepping for
`trigger_events`, `allowed_from_domains`, `channel_config`, `is_predefined`, `template_name`,
`"tag"`, `NotificationChannel`, `NotificationTemplateType`, or
`notification_templates_notification_type_fkey` returns **nothing**. The only
notification-related lines are the **pre-existing** legacy items already in the register
(init-era `idx_notification_*` index drops, `language SET NOT NULL`, legacy FK-name renames).

## Reproduce

```bash
cd admin-backend-api
npx prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --script \
  | grep -E '^-- ' | sed -E 's/^-- //' | sort | uniq -c | sort -rn   # -> 201 total, buckets above
```

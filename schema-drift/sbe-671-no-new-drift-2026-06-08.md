# SBE-671 Introduced No New Schema Drift — Evidence

> **Date:** 2026-06-08
> **Branch:** `feature/SBE-671` (Email & SMS Management — schema foundation, Phase 1)
> **Companion:** [`schema-drift-2026-06-08.md`](./schema-drift-2026-06-08.md) — the pre-existing
> drift register this document refers to.

## Claim

The schema changes delivered under SBE-671 added **zero** new schema drift. The **201-statement**
drift between `admin-backend-api/prisma/schema.prisma` and a migration-built database is
**entirely pre-existing** and is unchanged by this branch.

## What SBE-671 changed (the surface under test)

- `notification_templates`: 6 new columns (`template_name`, `type`, `channel_config`,
  `is_predefined`, `schedule_config`, `follow_up_config`); `channel` promoted `VARCHAR → enum`;
  new FK `notification_type → trigger_events.slug`.
- New enums `NotificationChannel`, `NotificationTemplateType`; new value `notification_template`
  on `AdminAuditEntityType`.
- New tables `trigger_events`, `allowed_from_domains`.
- Two new migrations: `20260608120000_add_notification_template_at_admin_audit_log_entity_type`,
  `20260608120100_email_sms_management_schema_foundation`.
- Mirrored schema edits in the other four services; DTO/spec/seeder code (not schema-affecting).

## Evidence

Three independent checks, all consistent.

### 1. The drift diff does not contain any SBE-671 object

`prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --script`, grepped
for our objects, returns **only pre-existing legacy items** — never our new tables/enums/columns/FK:

```
DROP INDEX "idx_notification_templates_channel";          # legacy init index, not ours
DROP INDEX "idx_notification_templates_is_active";        # legacy init index, not ours
DROP INDEX "idx_notification_templates_notification_type"; # legacy init index, not ours
ALTER TABLE "notification_templates" ALTER COLUMN "language" SET NOT NULL;  # pre-existing (P1 item)
```

No line references `trigger_events`, `allowed_from_domains`, `channel_config`, `is_predefined`,
`NotificationChannel`, `NotificationTemplateType`, or `notification_templates_notification_type_fkey`.
→ Our migrations and the schema **agree perfectly** on every SBE-671 object.

### 2. A clean reset reproduces the same drift (so it is structural, not environmental)

Rebuilt **all** migrations into a throwaway DB (`migrate deploy` → all applied, no errors), then
diffed against the schema: **201 statements**, identical buckets to the live DB. The drift is baked
into `migrations ⇄ schema`, not a side-effect of the live database or of `db push`.

### 3. Pre-change reconstruction: drift is identical with our changes removed

The decisive test. We rebuilt the **exact pre-SBE-671 state** and measured its drift:

- Source schema: `git show HEAD:prisma/schema.prisma` — verified it contains **0** of our new models.
- Migrations: only the original **104** (our 2 new ones moved aside).
- Fresh DB built from those 104, diffed against the original schema.

| Drift bucket | Pre-SBE-671 (104 migrations, HEAD schema) | Current (106 migrations, branch schema) |
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

**201 = 201**, bucket for bucket. The drift is the same with or without SBE-671 → our branch added none of it.

## How to reproduce

```bash
cd admin-backend-api
set -a; source .env; set +a
BASE="${DATABASE_URL%/*}"

# --- Current drift (with SBE-671) ---
npx prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --script \
  | grep -E '^-- ' | sed -E 's/^-- //' | sort | uniq -c | sort -rn        # -> 201 total

# --- Pre-change drift (reconstruct, non-destructive) ---
git show HEAD:prisma/schema.prisma > /tmp/schema_prechange.prisma          # 0 TriggerEvent models
mkdir /tmp/stash && mv prisma/migrations/20260608120000_* prisma/migrations/20260608120100_* /tmp/stash/
psql "$DATABASE_URL" -c "CREATE DATABASE sbe_prechange_check;"
DATABASE_URL="$BASE/sbe_prechange_check" npx prisma migrate deploy        # 104 migrations apply
DATABASE_URL="$BASE/sbe_prechange_check" \
  npx prisma migrate diff --from-config-datasource --to-schema /tmp/schema_prechange.prisma --script \
  | grep -E '^-- ' | sed -E 's/^-- //' | sort | uniq -c | sort -rn        # -> 201 total (identical)
# restore + cleanup
mv /tmp/stash/* prisma/migrations/ && psql "$DATABASE_URL" -c "DROP DATABASE sbe_prechange_check;"
```

## Additional safeguards taken in SBE-671

- **Did not run `prisma migrate dev`** against `sbe_database` (it would have auto-generated the full
  201-statement reconciliation, including destructive drops). Used a **hand-authored, focused
  migration + `migrate deploy`** instead — so only our intended objects entered the history.
- **Channel conversion is data-preserving** (`ALTER COLUMN ... USING`, not Prisma's destructive
  `DROP/ADD`); verified all 20 existing rows survived as `EMAIL`.
- **All 106 migrations apply cleanly from an empty DB** — `migrate reset` / fresh rebuild works,
  including our two new migrations.

## Conclusion

SBE-671's schema changes are **fully consistent** between the migrations and `schema.prisma`.
The 201-statement drift is **pre-existing, project-wide, and unchanged** by this branch, and is
tracked for future reconciliation in [`schema-drift-2026-06-08.md`](./schema-drift-2026-06-08.md).

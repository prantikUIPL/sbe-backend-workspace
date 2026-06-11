# Email & SMS Management — API Changelog

Append-only record of changes to **existing** API endpoints made during the SBE-671 Email & SMS Management implementation. Each entry documents what changed, why, and what callers must do. Share with the frontend / consuming teams.

Companion docs: design plan `.claude/plans/email-sms-management-crud-design.md`, known-issues register `EMAIL_SMS_KNOWN_ISSUES.md`.

---

## 2026-06-11 — `GET /admin/notification-templates` (listing)

**Repo:** `admin-backend-api`, branch `feature/SBE-671`
**Stories:** 76.1–76.3 (predefined listing/search/filter), 77.2–77.4 (custom listing/search/filter) — both UIs use this one endpoint, branching on `is_predefined`.

### Query parameters — ADDITIVE (no caller impact)

`page` / `limit` behave exactly as before (defaults 1 / 10, limit max 100). New **optional** params:

| Param | Type | Behaviour |
|---|---|---|
| `search` | string (≤150) | case-insensitive substring over `template_name`, `subject`, `notification_type` |
| `tag` | enum `Store \| Internal \| Vendor \| Product \| PPL \| System` | exact match |
| `channel` | enum `EMAIL \| SMS` | exact match |
| `is_active` | boolean (`true`/`false`) | exact match |
| `is_predefined` | boolean (`true`/`false`) | `true` = predefined (76.x), `false` = custom (77.x) |
| `notification_type` | string (≤150) | exact trigger-event slug match |

Invalid enum/boolean values → `400` with a field-specific message.

### Response — **BREAKING** (lean list shape)

| Change | Before | After |
|---|---|---|
| Fields **removed** from list rows | `subject`, `body`, `language`, `created_at` | — (use `GET /:id` for the full row) |
| `id` type | string (`"42"`) | number (`42`) |
| Fields **added** to list rows | — | `template_name`, `tag`, `is_predefined` |
| Ordering | `created_at desc` | `updated_at desc, id desc` |
| `meta` shape | `{ page, limit, total, totalPages, hasNext, hasPrev }` | unchanged |

New list row:

```json
{
  "id": 42,
  "template_name": "Welcome Email",
  "notification_type": "welcome_email",
  "tag": "System",
  "channel": "EMAIL",
  "is_active": true,
  "is_predefined": true,
  "updated_at": "2026-06-11T00:00:00.000Z"
}
```

### Justifications

1. **Columns = the V2 listing spec.** 76.1/77.2 define the list columns as `template_name`, `notification_type`, `tag`, `channel`, `is_active`, `updated_at` (+ `is_predefined` for the two-UI branch). The removed fields are not listing columns in any story.
2. **Payload weight.** `body` is full HTML per template; shipping it for every row on every page of a listing is waste. The detail endpoint (`GET /:id`) serves it.
3. **`id` as number** matches the schema's Int primary key (SBE-671 decision: Int PKs, not BigInt) — the previous string serialization was a BigInt-era artifact.
4. **`updated_at` ordering** matches the column the listing actually displays, and follows the house listing convention (booth-agreements: business field desc, `id` desc tiebreak).
5. **No `last_modified_by` in list rows** (decision 2026-06-11): audit info lives in the separate `admin_audit_logs` table and will be exposed via a separate audit-logs endpoint in a later phase — known-issues #8, BA to update story 76.1.

### Caller impact

- Any consumer reading `subject`, `body`, `language` or `created_at` from the **list** response must switch to `GET /notification-templates/:id`.
- Strictly-typed consumers must treat `id` as a number.
- No known existing consumers: no backend service calls this endpoint (only the permission seeder references the URL); the admin frontend for this module is being built against the new spec.

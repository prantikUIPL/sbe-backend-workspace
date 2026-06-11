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

---

## 2026-06-11 — `GET /admin/notification-templates/:id` (detail)

**Repo:** `admin-backend-api`, branch `feature/SBE-671`
**Stories:** 76.4 (predefined detail view), 77.5 (custom detail view) — both UIs use this one endpoint; 76.7 (placeholders) is served by the joined `trigger_event.available_placeholders`.

### Response — **BREAKING**

| Change | Before | After |
|---|---|---|
| `id` type | string (`"42"`) | number (`42`) |
| `subject` when absent (SMS rows) | key **omitted** (old mapper converted `null` → `undefined`) | explicit `null` |
| Non-numeric `:id` (e.g. `/abc`) | undefined behavior (`NaN` → Prisma error / 500) | `400` `Validation failed (numeric string is expected)` — behavior fix, listed here because it changes observable responses |

### Response — ADDITIVE

New top-level fields (returned **as stored**; the mailer does not consume them this phase):

| Field | Type | Notes |
|---|---|---|
| `template_name` | string | display name |
| `tag` | enum `Store \| Internal \| Vendor \| Product \| PPL \| System` | |
| `channel_config` | object \| null | EMAIL: `from_address`/`from_name`/`reply_to`/`to_recipients`/`cc_recipients`/`bcc_recipients`; SMS: `sender_id`/`to_recipients`. For **predefined** templates FROM/TO/`sender_id` are system-managed — render read-only (76.4) |
| `is_predefined` | boolean | `true` = 76.x epic, `false` = 77.x epic |
| `schedule_config` | array \| null | scheduling UI is a later phase; returned as stored |
| `follow_up_config` | array \| null | later phase; returned as stored |

New **required** nested object (the FK `notification_type` → `trigger_events.slug` is NOT NULL, so it is always present):

```json
"trigger_event": {
  "id": 7,
  "slug": "welcome_email",
  "label": "Admin User Created",
  "available_placeholders": ["name", "siteName", "loginUrl", "tempPassword", "supportEmail"],
  "is_custom": false
}
```

`available_placeholders` is a string array or `null` — drives the WYSIWYG placeholder picker (code-controlled; not admin-editable).

### Full example response

```json
{
  "id": 1,
  "notification_type": "welcome_email",
  "template_name": "Welcome Email",
  "tag": "System",
  "channel": "EMAIL",
  "subject": "Welcome to {{siteName}}",
  "body": "<p>Hello {{name}}</p>",
  "language": "en",
  "channel_config": null,
  "is_predefined": true,
  "schedule_config": null,
  "follow_up_config": null,
  "is_active": true,
  "created_at": "2026-06-11T00:00:00.000Z",
  "updated_at": "2026-06-11T00:00:00.000Z",
  "trigger_event": {
    "id": 7,
    "slug": "welcome_email",
    "label": "Admin User Created",
    "available_placeholders": ["name", "siteName", "loginUrl", "tempPassword", "supportEmail"],
    "is_custom": false
  }
}
```

### Justifications

1. **Full row + joined placeholders = the 76.4/77.5 spec** ("returns full row + `available_placeholders` joined from `trigger_events`"). The nested `trigger_event` object carries both the human-readable `label` (read-only display field) and the placeholder list (picker) in one shape that mirrors the DB relation; `is_custom` is included now so the edit phase doesn't need another contract change.
2. **`id` as number** — same Int-PK justification as the listing entry above.
3. **Explicit `null` over omitted keys** — the row is now returned exactly as selected from the DB (no mapping layer, house convention); strictly-typed consumers get a stable shape.
4. **No `last_modified_by`** — same as listing entry justification #5: audit info via a separate audit-logs endpoint in a later phase (known-issues #8).

### Caller impact

- Strictly-typed consumers must treat `id` as a number and `subject` as `string | null` (key always present).
- Frontends checking `'subject' in response` must switch to a null check.
- `POST` / `PUT` responses are **unchanged** this phase (still the old baseline shape, `id` as string) — they get reworked in the edit-endpoint phase.
- No known existing consumers (same as listing entry).

---

## 2026-06-11 — `GET /admin/notification-templates/:id` — out-of-range id now `400` (was `500`/`404`)

**Repo:** `admin-backend-api`, branch `feature/SBE-671` (behavior fix, found in code review)

| Request | Before | After |
|---|---|---|
| `:id` beyond Postgres INT4 (e.g. `/2147483648`) | Prisma `P2020` → raw `500` | `400` `Validation failed (id out of range)` |
| `:id` zero or negative (e.g. `/0`, `/-1`) | `404` (id can never exist) | `400` `Validation failed (id out of range)` |

`id` is a positive INT4 autoincrement primary key; the stock `ParseIntPipe` has no range check, so over-range values passed validation and blew up at the database layer, while zero/negative values burned a DB round-trip to 404. Replaced with a shared `ParseIntIdPipe` (`src/common/pipes/parse-int-id.pipe.ts`) that rejects ids outside `[1, 2147483647]` at the request boundary. The endpoint's error contract is now fully 400/404 as documented.

Note: the same pipe was applied to the booth-agreements `:id` routes (GET/PATCH/DELETE), which had the identical hole — recorded here for traceability only; that module is outside the Email & SMS scope.

---

## 2026-06-11 — `GET /admin/trigger-events` + `GET /admin/allowed-from-domains` (new supporting endpoints)

**Repo:** `admin-backend-api`, branch `feature/SBE-671`
**Purpose:** reference dropdowns for the custom-template create/edit UI (77.x) — trigger picker / placeholder picker, and the fixed-domain dropdown of the FROM address.

**ADDITIVE — no existing endpoint changed.** Recorded because the paths deviate from the design doc, which originally nested them under `/notification-templates/...`. Decision: separate controllers/modules with standalone paths (avoids the `/notification-templates/:id` route-shadowing coupling). The design doc's "Supporting endpoints" table has been updated to match.

### `GET /admin/trigger-events`

Unpaginated array of the full trigger-event catalog (code-controlled, seeded — no admin CRUD), ordered by `label` asc:

```json
[
  {
    "id": 7,
    "slug": "welcome_email",
    "label": "Admin User Created",
    "available_placeholders": ["name", "siteName", "loginUrl", "tempPassword", "supportEmail"],
    "is_custom": false
  }
]
```

`available_placeholders` is the placeholder-picker source for the selected trigger (`null` possible — column is nullable). `is_custom` is included ahead of the 77.x edit rules.

### `GET /admin/allowed-from-domains`

Unpaginated array of **active** (`is_active = true`) whitelist domains a custom EMAIL template may send FROM, ordered by `domain` asc. Inactive domains are excluded — they must not be offered in the dropdown. `is_active` is omitted from the payload (always true by construction):

```json
[
  { "id": 1, "domain": "theshowproducers.com" },
  { "id": 2, "domain": "thesmallbusinessexpo.com" }
]
```

### Permissions (action required)

Two new permission keys: `trigger-events.list` and `allowed-from-domains.list`. Seeded by `permission.seeder.ts`, granted to **Admin/Super Administrator only** by `role.seeder.ts`, and mapped to permission groups (`View Trigger Events` / `View Allowed FROM Domains`) by `permission-group.seeder.ts`. **Environments must re-run the seeders** — until then even Admin gets `403` on both endpoints. The re-run fixes Admin/Super Administrator only; **every other role** (the other seeded roles, e.g. the SBE team roles, and all custom roles) additionally needs the two new groups enabled per role via the role-permissions UI (or the raw `POST /roles/:id/permissions`) before its users can load the dropdowns. (The seed re-run is safe for manually deactivated FROM domains: the domain seeder no longer touches existing rows on re-run.) Other errors follow the standard auth contract (401/403/500); no request parameters, so no 400s.

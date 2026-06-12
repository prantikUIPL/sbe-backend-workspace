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

---

## 2026-06-11 — `POST` / `PUT` / `DELETE /admin/notification-templates` (custom create, two-tier edit, custom delete)

**Repo:** `admin-backend-api`, branch `feature/SBE-671`
**Stories:** 77.1 (create custom EMAIL template), 76.5 + 77.6 (edit predefined/custom), design-doc DELETE (custom-only). Replaces the interim scaffolding handlers wholesale.

### `POST /notification-templates` — **BREAKING** (payload + response reworked)

| Change | Before | After |
|---|---|---|
| Required body fields | `notification_type`, `channel`, `subject`, `body` | + `template_name` (≤255), `tag` (enum), `channel_config` (object, see below); `subject` stays required (≤255) |
| `channel` | `EMAIL` or `SMS` accepted | **`EMAIL` only** — anything else → `400` `Only EMAIL channel is supported` |
| `template_name` / `tag` | hardcoded server-side (slug / `System`) | caller-supplied |
| Duplicate check | `409` on same `(notification_type, channel, language)` | **removed** — no uniqueness for custom templates; the same payload twice creates two rows |
| `201` body | old baseline shape, `id` as string | **detail shape** (same as `GET /:id`, incl. `trigger_event` join), `id` as number |
| `Location` header | — | `/api/v1/notification-templates/<id>` |

New required `channel_config` object (unknown keys, e.g. `sender_id`, → `400 property sender_id should not exist`):

| Key | Rules |
|---|---|
| `from_address` | required, valid email ≤255; **domain must be an active allowed FROM domain** (else `400` with `errorType: "from_address_domain"`); local part free-form |
| `from_name` | required, string ≤255 |
| `reply_to` | required, valid email ≤255 |
| `to_recipients` | required, array of 1–50 **literal email addresses** |
| `cc_recipients` / `bcc_recipients` | optional, arrays of ≤50 literal email addresses |

New server-side validations (all `400`):

- `notification_type` must match an existing trigger event (unchanged from interim handler).
- **Placeholder whitelist:** every `{{token}}` in `subject`/`body` must be in the trigger event's `available_placeholders` — `Unknown placeholder(s) for trigger "...": {{...}}`. Handlebars block tokens (`{{#if}}`/`{{/if}}`/`{{else}}`) are ignored by the check.
- **Recipients are literal email addresses only** — `{placeholder}` tokens in recipient arrays are rejected until the dynamic-recipient-resolution phase (77.9 / known-issues #3) loosens this.

Created rows are always `is_predefined: false`. Every create writes an admin-audit row (see Audit below).

### `PUT /notification-templates/:id` — **BREAKING** (two-tier edit matrix enforced)

Previously only `subject`/`body`/`is_active` were accepted, on any row, unaudited. Now all of `notification_type`, `template_name`, `tag`, `subject`, `body`, `is_active`, `channel_config` (all optional) are accepted, gated per tier:

| Field | Predefined | Custom |
|---|---|---|
| `notification_type` | `400` (system-controlled) | editable (must match an existing trigger event) |
| `template_name`, `tag`, `body`, `is_active` | editable | editable |
| `subject` | editable on EMAIL rows; `400` on SMS rows | editable |
| `channel_config.from_address` / `to_recipients` | `400` (system-controlled) | editable (FROM-domain whitelist re-checked) |
| `channel_config.from_name` / `reply_to` / `cc_recipients` / `bcc_recipients` | editable on EMAIL rows; **any** config key on a predefined SMS row → `400` | editable |
| `channel` / `is_predefined` | not in the payload — never editable | never editable |

- **`channel_config` merge:** provided keys replace the stored keys wholesale (`cc_recipients: []` clears the list); unprovided keys are preserved.
- **Placeholder whitelist** applies to both tiers; re-pointing a custom template's `notification_type` re-validates the *unchanged* subject/body against the new trigger's placeholders.
- The duplicate-`409` is gone (same reasoning as POST).
- `200` body is now the **detail shape** (was the old string-id baseline); `:id` is now validated (`400` instead of undefined behavior on non-numeric/out-of-range ids).
- **Per-field audit:** each changed field (scalars and individual `channel_config` keys) writes its own admin-audit row. A no-change request writes nothing and returns the stored row.

### `DELETE /notification-templates/:id` — **BREAKING** (custom-only)

- Predefined rows → `400` `Predefined templates cannot be deleted` (previously any row could be deleted).
- `notification_logs` rows referencing the template are removed with it (FK cascade) — intended behavior; a no-op today since nothing sends custom templates yet, but once custom sending ships, deleting a template deletes its send history.
- Deletion writes an admin-audit row with the pre-delete snapshot.
- `:id` validated as in PUT. Response stays `{ "message": "Notification template deleted successfully" }`.

### Audit (amends the detail-entry note of 2026-06-11)

Create/edit/delete history is recorded in `admin_audit_logs` (`entity_type = notification_template`, `entity_id` = template id, `performed_by` = JWT admin) inside the write transaction, booth-agreements style. It is consumed via the **central audit-log endpoint's `entity_type`/`entity_id` filters** — there is **no scoped `GET /notification-templates/:id/audit-logs` endpoint** (the earlier detail entry anticipated one; decision 2026-06-11: central endpoint instead, no extra permission key).

### Predefined-uniqueness decision (recorded)

Predefined templates are unique per `(notification_type, channel)` so a send-time query by trigger + predefined returns a single row. Enforced by a **seeder catalog assertion + service construction** (create always writes `is_predefined: false`; edit never flips the flag) — **no DB constraint**, because Prisma PSL cannot declare partial unique indexes and a sibling repo's `db push` would silently drop a raw-SQL one. Holds for all 20 seeded rows today.

### Seeders & permissions (action required)

- `notification-template.seeder.ts` is now **create-only** (closes known-issues #15): existing rows are skipped on re-run, so admin edits to predefined copy are never clobbered. It also fail-loudly asserts the catalog has no duplicate `(notification_type, channel)` pair.
- `permission-group.seeder.ts` adds four `notification_template` groups — View / Create / Update / Delete Notification Template(s), Create/Update/Delete depending on View (closes known-issues #14). **Environments must re-run the seeders** for the groups to appear in the role-permissions UI; the five permission keys themselves were already seeded and granted to Admin/Super Administrator. Other roles need the new groups enabled per role.

### Caller impact

- Any consumer of the old POST payload must add `template_name`, `tag` and `channel_config`, and stop sending `channel: "SMS"`.
- Consumers reading the old string-id `201`/`200` bodies must switch to the detail shape (number `id`, explicit nulls, nested `trigger_event`).
- Code relying on the duplicate-`409` must drop that handling.
- No known existing consumers (same as the listing entry).

---

## 2026-06-12 — Story-alignment fixes: listing filters/search, optional `from_name`/`reply_to`, CC/BCC dedup, HTML sanitization

**Repo:** `admin-backend-api`, branch `feature/SBE-671`
**Why:** an implementation-vs-stories audit (2026-06-12) found six deviations from the V2 story text; five are code fixes recorded here (the sixth — DELETE has no backing story — is documentation-only, see known-issues #18). All changes are pre-release; no known existing consumers.

### `GET /notification-templates` — search cap & multi-select filters

| Change | Before | After |
|---|---|---|
| `search` max length | 150 | **254** (story 76.2/77.3: "Max length: 254 characters") |
| `tag` | single enum value | **multi-select**: repeat the param (`?tag=Store&tag=PPL`) or CSV (`?tag=Store,PPL`) — OR among values, AND across filters (76.3/77.4) |
| `channel` | single enum value | **multi-select**, same syntax (`?channel=EMAIL,SMS`) |
| invalid filter value message | `tag must be one of: …` | `each tag must be one of: …` (likewise `each channel …`) |

Single-value calls keep working unchanged (a lone value is a one-element selection). An empty filter (`?tag=`) is treated as no filter. `is_active` stays single-valued (the stories specify multi-select for Type/Channel only).

### `POST` / `PUT /notification-templates` — recipient & sanitization alignment

| Change | Before | After |
|---|---|---|
| `channel_config.from_name` (POST) | required | **optional** (story 77.1 "if provided"); stored as `null` when omitted |
| `channel_config.reply_to` (POST) | required | **optional** (story 77.1 "if provided"); stored as `null` when omitted |
| `cc_recipients` / `bcc_recipients` | stored as sent | **de-duplicated case-insensitively** on write (first occurrence's casing kept) — POST and PUT (76.5/77.1/77.6). `to_recipients` is not deduped (not story-specified; cross-field dedup stays deferred with DRR, known-issues #3) |
| `body` | stored verbatim | **sanitized on write**: `script`/`iframe`/`object`/`svg` blocks (contents included) and `embed`/`form`/`base`/`meta`/`link` tags removed; `on*` event-handler and `srcdoc` attributes stripped; `href`/`src`/`action`/`formaction`/`background`/`xlink:href` values resolving to `javascript:`/`vbscript:`/non-image `data:` removed (`data:image/*` kept for WYSIWYG inline images). Formatting tags, tables, inline styles, hyperlinks, hosted/inline images and Handlebars `{{tokens}}`/block helpers pass through unchanged |
| `subject` / `template_name` / `channel_config.from_name` | stored verbatim | **HTML tags stripped** (plain-text fields; same `SanitizeText` strip used by the Shows module) |

Sanitization runs before validation, so a body that is *only* a script block now 400s as `body cannot be empty`. Sanitizer: `src/admin/notification-template/utils/email-html-sanitizer.util.ts` (blocklist, not allowlist — chosen so the seeded predefined bodies, which use tables/headings/links, round-trip through PUT byte-identical; rationale in the file header).

### Caller impact

- Frontends may now omit `from_name`/`reply_to` on create; rendered detail views must handle `null` for both.
- A consumer sending duplicate CC/BCC entries gets the deduped list back in the detail-shape response (the stored truth).
- Anything relying on `<script>`-bearing bodies surviving a write must stop; no legitimate flow did.
- Strictly-typed consumers of the listing query: `tag`/`channel` are now `string[]` in the OpenAPI schema.

---

## 2026-06-12 — `GET /admin/notification-templates` — trigger label in list rows + searchable

**Repo:** `admin-backend-api`, branch `feature/SBE-671`
**Stories:** 76.1/77.2 (listing "Trigger Event" column), 76.2/77.3 (search by Template Name and **Trigger Event**).
**Why:** a re-verification audit (2026-06-12, 2nd pass) noted the listing exposed only the trigger slug (`notification_type`) — the human-readable label lived solely in the detail join, so a search for the displayed label text (e.g. "Admin User Created") matched nothing.

### Response — ADDITIVE

Each list row now includes the joined trigger-event label (same nested shape as the detail endpoint, label only):

```json
{
  "id": 42,
  "template_name": "Welcome Email",
  "notification_type": "welcome_email",
  "tag": "System",
  "channel": "EMAIL",
  "is_active": true,
  "is_predefined": true,
  "updated_at": "2026-06-11T00:00:00.000Z",
  "trigger_event": { "label": "Admin User Created" }
}
```

The FK is NOT NULL, so `trigger_event` is always present. Use `trigger_event.label` for the listing's Trigger Event column; `notification_type` remains the slug.

### Behavior — ADDITIVE

`search` now also matches the trigger event `label` (case-insensitive substring), alongside `template_name`, `subject` and `notification_type`. A keyword can therefore return rows it previously missed; no previously-matching row stops matching.

### Caller impact

- None breaking. Strictly-typed consumers gain a required `trigger_event: { label: string }` key on list rows.
- Note: `subject` participating in search is a code-side extension beyond the search stories — recorded in known-issues #17.

---

## 2026-06-12 — `:id` routes — hex/exponent id strings now rejected (was: resolved to wrong rows)

**Repo:** `admin-backend-api`, branch `feature/SBE-671`
**Routes:** `GET`/`PUT`/`DELETE /notification-templates/:id` and `GET`/`PATCH`/`DELETE /booth-agreements/:id` (the six routes guarded by `ParseIntIdPipe`).
**Why:** the 2026-06-12 live HTTP smoke found `GET /notification-templates/0x10` returning **200 with row 16**. The global `ValidationPipe({ transform: true })` coerces Number-typed `@Param` values with `+value` *before* the param-scoped pipe runs, so `"0x10"` (and `"1e2"`, `" 16 "`, …) reached `ParseIntIdPipe` as an already-valid integer and its numeric-string check (`/^-?\d+$/`) never saw the original text.

### Behavior — CORRECTIVE (technically breaking)

| id string | Before | After |
|---|---|---|
| `0x10`, `0b101` (hex/binary) | 200/404 — silently resolved as the coerced number (`0x10` → row 16) | **400** `Validation failed (numeric string is expected)` |
| `1e2` (exponent) | resolved as 100 | **400** same message |
| `" 16 "` (whitespace-padded) | resolved as 16 | **400** same message |
| plain decimal (`16`) | works | works, unchanged |
| `abc`, `1.5`, `0`, `-1`, `> INT4_MAX` | 400 | 400, unchanged |

### Implementation

New `RawParam` custom param decorator (`src/common/decorators/raw-param.decorator.ts`) extracts the route param as its **raw string** — custom-decorator args are exempt from the global pipe's primitive coercion — so `ParseIntIdPipe` validates the original text. The six call sites changed from `@Param('id', ParseIntIdPipe)` to `@RawParam('id', ParseIntIdPipe)`; the pipe itself, its 400 messages, and the Swagger docs are unchanged.

### Caller impact

- None for well-behaved callers: canonical decimal ids behave identically.
- Anything that relied on hex/exponent/padded id strings resolving (no legitimate flow did) now gets the already-documented 400.
- **Scope note:** all other admin routes using plain `ParseIntPipe` (~60 call sites) still accept coerced forms — the repo-wide hole and its durable fix remain a separate, undecided item (same standing decision as the INT4/global-filter question recorded 2026-06-11).

# Notification-template CRUD rewrite — custom EMAIL create + two-tier edit + custom delete (SBE-671, 76.5/77.1/77.6)

## Context

The existing POST/PUT/DELETE handlers are interim scaffolding: POST hardcodes `template_name`/`tag`, never writes `channel_config`, accepts SMS, and enforces a duplicate check the design forbids; PUT edits only subject/body/is_active with no predefined/custom branching; nothing is audited. Stories 77.1 (create custom EMAIL), 76.5/77.6 (two-tier edit matrix), and the design's custom-only DELETE complete the CRUD.

**User decisions (this session):**
- **Custom create: no uniqueness check** — drop the `(type, channel, language)` ConflictException; multiple templates (predefined + custom) may share a trigger; duplicate names allowed.
- **Predefined-uniqueness invariant**: predefined rows unique per `(notification_type, channel)` — enforced at **seeder + service layer only**, no DB partial index (not declarable in Prisma PSL; a sibling `db push` would silently drop a raw-SQL one). Verified safe today: 20 seeded templates, 20 unique slugs, all EMAIL. API writes can't violate it (create forces `is_predefined: false`; edit never flips it).
- **Audit now, booth-agreements approach** — `AdminAuditService.record`/`recordMany` rows inside the write transaction; **no scoped GET audit endpoint** (history consumed via the central audit-log module's `entity_type`/`entity_id` filters; no new permission key). Verified: `notification_template` is already in `AdminAuditEntityType` in admin's schema + committed migration AND all four sibling schemas — zero schema work.
- **201/200 return the detail shape** — same as `GET /:id` (`NOTIFICATION_TEMPLATE_DETAIL_SELECT` incl. `trigger_event` join). `NotificationTemplateResponseDto` + `toResponse` are deleted (nothing uses them after this).
- **Known-issues #15 fix: create-only seeder** — the template seeder never updates existing rows; admins own predefined copy once the edit UI ships.
- **Close known-issues #14** — add the `notification_template` permission groups.
- **DELETE included** — custom-only; predefined rejected 400.

**Scope guard:** GET list/detail untouched. No `schedule_config`/`follow_up_config` in any payload (77.8/76.6 deferred; columns stay null). No `language` in the update DTO (not in the 76.5 edit matrix).

## The 76.5 two-tier edit matrix (service-enforced)

| Field | Predefined | Custom (EMAIL) |
|---|---|---|
| `notification_type` (trigger) | reject if present | editable (FK pre-check) |
| `template_name` | editable *(user amendment — design doc's predefined allow-list omitted it; safe: display-only column, create-only seeder won't revert renames, rename is audited)* | editable |
| `tag`, `body`, `is_active` | editable | editable |
| `subject` | editable (EMAIL rows only; reject on SMS rows) | editable |
| `channel_config.from_address` / `to_recipients` | reject if present (system-controlled) | editable (domain rules) |
| `channel_config.from_name` / `reply_to` / `cc` / `bcc` | editable (EMAIL rows; **any** config key on a predefined SMS row → 400) | editable |
| `channel` / `is_predefined` | never editable (not in DTO) | never editable |

SMS `channel_config` shape validation (sender_id/E.164) is unreachable this sprint — predefined SMS allows no config edits and custom SMS doesn't exist — so no SMS config DTO is built.

## Changes (all in `admin-backend-api` unless noted)

### 1. Recipient validation — emails only (user decision)

Recipients (`to_recipients` / `cc_recipients` / `bcc_recipients`) accept **literal email addresses only**, validated with the built-in `@IsEmail({}, { each: true })`. `{placeholder}` tokens are **rejected (400)** — token acceptance/resolution is wholly deferred to the Dynamic Recipient Resolution story (77.9, known-issues #3); when DRR lands, the validation loosens. No custom validator file is needed. (`IsDeepEmail` deliberately not used — MX/SMTP-level checks are the wrong strictness for stored config.)

### 2. DTOs — `src/admin/notification-template/dto/notification-template.dto.ts`

Nested validation under the global `ValidationPipe { whitelist, forbidNonWhitelisted, transform }` follows the universal-booth precedent (`@ValidateNested` + `@Type`); whitelisting recurses into nested classes, so an SMS-only `sender_id` key 400s automatically (`channel_config.property sender_id should not exist`).

**`EmailChannelConfigDto`** (create — all required except cc/bcc):
- `from_address` — `@Transform(trim) @IsEmail @IsNotEmpty @MaxLength(255)`; ApiProperty notes domain must be an active allowed FROM domain, local part free-form
- `from_name` — trim, `@IsString @IsNotEmpty @MaxLength(255)`
- `reply_to` — trim, `@IsEmail @IsNotEmpty @MaxLength(255)`
- `to_recipients` — `@IsArray @ArrayMinSize(1) @ArrayMaxSize(50) @IsEmail({}, { each: true })`, literal-email examples only
- `cc_recipients` / `bcc_recipients` — optional, `@IsArray @ArrayMaxSize(50) @IsEmail({}, { each: true })`, default `[]`

**`UpdateEmailChannelConfigDto`** — same keys/validators, **every key optional** (provided keys are validated; predefined-row key rejection is service-layer since the DTO can't see `is_predefined`).

**`CreateNotificationTemplateDto`** — rewrite wholesale:
- `notification_type` — trim, `@IsString @IsNotEmpty @MaxLength(150)` (existing trigger slug)
- `channel` — `@IsIn(['EMAIL'], { message: 'Only EMAIL channel is supported' })`, ApiProperty `enum: ['EMAIL']` (positive phrasing — supported channels only, no mention of what isn't)
- `template_name` — trim, required, `@MaxLength(255)`
- `tag` — `@IsEnum(NotificationTemplateType)`
- `subject` — trim, required, `@MaxLength(255)` (77.5: subject always present for custom email)
- `body` — `@IsString @IsNotEmpty` (HTML)
- `channel_config` — `@IsDefined @IsObject @ValidateNested @Type(() => EmailChannelConfigDto)`
- `language?` — optional, default 'en'; `is_active?` — optional `@IsBoolean`, default true

**`UpdateNotificationTemplateDto`** — rewrite wholesale, all optional: `notification_type?`, `template_name?`, `tag?`, `subject?`, `body?`, `is_active?`, `channel_config?` (`@ValidateNested @Type(() => UpdateEmailChannelConfigDto)`). When provided, fields carry the same validators as create (`@MinLength(1)` non-empty etc.).

Delete `NotificationTemplateResponseDto`. Keep `NOTIFICATION_CHANNELS`/`NotificationChannelType` (create DTO property type) and the list-query DTO. New imports: `ValidateNested, IsObject, IsDefined, IsArray, ArrayMinSize, ArrayMaxSize, IsEmail` (class-validator), `Type` (class-transformer).

### 3. Service — `createTemplate(dto, performedBy?: number): Promise<NotificationTemplateDetail>`

Constructor gains `private readonly adminAudit: AdminAuditService`. Flow:
1. Defensive channel guard: non-EMAIL → `BadRequestException` `Only EMAIL channel is supported` (DTO already gates; keeps the rule unit-testable).
2. Trigger pre-check (kept, now also selects `available_placeholders`): `triggerEvent.findUnique({ where: { slug }, select: { id: true, available_placeholders: true } })` → null → 400 `Unknown notification_type "…" — no matching trigger event`.
2b. **Placeholder whitelist** (new — user requirement): `assertPlaceholdersAllowed(subject, body, trigger.available_placeholders)` — extract every `{{token}}` from subject + body (regex over simple identifiers), **skip Handlebars block tokens** (`{{#…}}`, `{{/…}}`, `{{else}}` — seeded bodies use `{{#if}}` conditionals), and 400 listing any token not in the trigger's `available_placeholders` (e.g. `Unknown placeholder(s) for trigger "…": {{foo}}, {{bar}}`). Null/empty `available_placeholders` → any placeholder is rejected.
3. FROM-domain whitelist: `domain = from_address.split('@').pop()!.toLowerCase()`; `allowedFromDomain.findFirst({ where: { domain: { equals: domain, mode: 'insensitive' }, is_active: true } })` → null → `BadRequestException` with house error object incl. `errorType: 'from_address_domain'` (booth-agreements convention).
4. **No duplicate check** — delete the `findFirst` + `ConflictException` block.
5. `prisma.$transaction`: `tx.notificationTemplate.create` with `channel: EMAIL`, `language ?? 'en'`, `channel_config: { ...dto.channel_config } as Prisma.InputJsonObject` (class instance isn't assignable to `InputJsonValue`), `is_predefined: false` (comment: predefined rows are seeder-owned; uniqueness per trigger+channel holds by construction), `is_active ?? true`, **`select: NOTIFICATION_TEMPLATE_DETAIL_SELECT`**; then `adminAudit.record({ entityType: notification_template, entityId, previousValue: null, newValue: JSON.stringify(snapshot), performedBy, note: buildNotificationTemplateCreateNote(snapshot) }, tx)`.
6. Keep `logger.logActivity`. Return the row.

### 4. Service — `updateTemplate(id, dto, performedBy?): Promise<NotificationTemplateDetail>`

1. Load existing full row (`findUnique`) → 404 `NotFoundException` if missing.
2. **Branch on `existing.is_predefined`** (76.5 matrix):
   - **Predefined**: presence of `notification_type` → 400 (explicit "read-only for predefined templates" message). `template_name` is editable (user amendment to the design allow-list). `subject` present on an SMS row → 400. `channel_config` present: on SMS rows any key → 400; on EMAIL rows only `from_name`/`reply_to`/`cc_recipients`/`bcc_recipients` allowed — `from_address`/`to_recipients` present → 400 (system-controlled).
   - **Custom**: all fields allowed. `notification_type` provided → trigger FK pre-check (as create). `channel_config.from_address` provided → domain whitelist check (as create).
   - **Placeholder whitelist (both tiers)**: when `subject` and/or `body` is provided, run `assertPlaceholdersAllowed` against the *effective* trigger's `available_placeholders` (the new trigger if `notification_type` is changing, else the row's current trigger — fetch its placeholders). Applies to predefined edits too since `body` is editable there.
3. **`channel_config` merge semantics**: top-level key replacement — `{ ...(existing.channel_config ?? {}), ...providedKeys }` cast to `Prisma.InputJsonObject`. Aligns with the per-key audit rule; `cc_recipients: []` clears a list.
4. **Diff + audit**: compare old vs new — one `AdminAuditRecordInput` per changed scalar (`template_name`, `notification_type`, `tag`, `subject`, `body`, `is_active`) + one per changed top-level `channel_config` key (`previous_value`/`new_value` hold the JSON-stringified single values; note via `buildNotificationTemplateUpdateNote(templateName, field)` — design example: "Updated CC recipients on Contract Sent"). No changes → skip the write entirely and return the current detail row (no empty audit).
5. `prisma.$transaction`: `tx.notificationTemplate.update({ where: { id }, data, select: NOTIFICATION_TEMPLATE_DETAIL_SELECT })` + `adminAudit.recordMany(rows, tx)`.
6. Delete `toResponse` (now unused). Drop `ConflictException` import if no longer used anywhere in the service.

### 5. Service — `deleteTemplate(id, performedBy?)`

1. Load row → 404. `is_predefined` → 400 `Predefined templates cannot be deleted`.
2. `prisma.$transaction`: snapshot → `tx.notificationTemplate.delete({ where: { id } })` + `adminAudit.record({ …, previousValue: JSON.stringify(snapshot), newValue: null, note: buildNotificationTemplateDeleteNote(snapshot) }, tx)`. Note: `notification_logs.notification_template_id` is `onDelete: Cascade` (send-history rows) — nothing sends custom templates yet so the cascade is a no-op today, but once custom sending ships, deleting a template deletes its send history with it; documented as intended behavior in the changelog.
3. Keep the existing `{ message }` response shape.

### 6. Audit note builders — `src/admin/common/audit/audit-note.builder.ts`

Append (BoothAddonType section style): `NotificationTemplateAuditSnapshot` type (`template_name, notification_type, channel, tag, language, is_active, from_address`) + three builders: `buildNotificationTemplateCreateNote(s)` (`Action: Created; Entity Affected: Notification Template '<name>' (trigger: …; channel: …; tag: …; enabled/disabled)`), `buildNotificationTemplateUpdateNote(templateName, field)` (`Action: Updated; … Field: <field>` — match house update-note style), `buildNotificationTemplateDeleteNote(s)`. Test blocks in `audit-note.builder.spec.ts`.

### 7. Module — `notification-template.module.ts`

`imports: [..., AdminAuditModule]` (provides/exports `AdminAuditService`).

### 8. Controller — POST / PUT / DELETE handlers

Booth-agreements conventions throughout; class-level `@ApiAuthResponses()` covers 401/403/500; no ticket refs; descriptions via `[...].join('\n')`.

**POST** — keep `@Permissions('notification_template.create')`, `@HttpCode(HttpStatus.CREATED)`, `@ApiBody`. Signature `(@Body() dto, @Req() req: AuthenticatedRequest, @Res({ passthrough: true }) res: Response)`; pass `req.user.id`; set `Location` header `${req.originalUrl}/${created.id}`. Return `NotificationTemplateDetail`. `@ApiResponse 201` with `headers: { Location }` + full detail-shape `schema.example` (`is_predefined: false`, populated `channel_config`). `@ApiBadRequestErrorResponse` with the realistic message list (DTO + nested `channel_config.…` prefixes, `Only EMAIL channel is supported`, unknown-trigger, unknown-placeholder, disallowed-domain, `sender_id should not exist`). **Remove** `@ApiConflictErrorResponse`. Operation description: custom EMAIL only; SMS rejected; FROM domain whitelist; recipients are literal email addresses only (placeholder tokens arrive with the dynamic-recipient-resolution phase); multiple templates may share a trigger.

**PUT** — keep `@Permissions('notification_template.update')`, 200 detail-shape `schema.example`; pass `req.user.id`. Operation description spells out the two-tier matrix (predefined: trigger/name/FROM/TO read-only, SMS rows lock subject + entire config; custom: full edit, domain rules) and the per-field audit trail. `@ApiBadRequestErrorResponse` incl. the predefined read-only messages; `@ApiNotFoundErrorResponse`; remove any conflict decorator.

**DELETE** — keep `@Permissions('notification_template.delete')`, `{ message }` 200 example, `@ApiBadRequestErrorResponse` ('Predefined templates cannot be deleted'), `@ApiNotFoundErrorResponse`; pass `req.user.id`. Description: custom-only; predefined rows are seeder-owned.

### 9. Permission groups — `src/database/seeds/permission-group.seeder.ts` (closes known-issues #14)

Booth-agreements group pattern (~lines 549-573), module string `notification_template` (matches key prefix):
- `View Notification Templates` (depends_on null) → `['notification_template.list', 'notification_template.read']`
- `Create Notification Template` (depends_on View) → `['notification_template.create']`
- `Update Notification Template` (depends_on View) → `['notification_template.update']`
- `Delete Notification Template` (depends_on View) → `['notification_template.delete']`

All five keys already seeded + granted to Admin/Super Administrator — no permission/role seeder changes. No audit-log key (booth-agreements approach: no scoped audit endpoint).

### 10. Template seeder — create-only (#15) + catalog guard — `src/database/seeds/notification-template.seeder.ts`

- Replace the findFirst-then-**update**/create flow with **create-only**: row exists (by `notification_type` + `channel` + `language`) → skip with a log line; else create. Comment why: admins own predefined copy via the edit endpoint; a seed re-run must never clobber their edits (same philosophy as the allowed-from-domain seeder).
- Before the loop, assert the catalog has no duplicate `(notification_type, channel)` pair — throw with the offending slug (same fail-loudly style as the missing-`TEMPLATE_META` throw). This is the predefined-uniqueness invariant guard.

### 11. Specs

**service.spec**: mocks gain `allowedFromDomain.findFirst`, `$transaction.mockImplementation((cb) => cb(mockPrisma))` (pricing-tier pattern), `mockAdminAudit = { record: jest.fn(), recordMany: jest.fn() }` provider. `buildCreateDto()` / `buildUpdateDto()` helpers.
- *create*: happy path (`is_predefined: false`, DETAIL_SELECT, defaults, returns row as-is); SMS → 400; unknown trigger → 400; disallowed domain → 400 with `errorType` + lowercased-domain/`is_active` query assert; audit `record` called with tx client, `previousValue: null`, `performedBy`; no duplicate-probe `findFirst`.
- *placeholder validation* (create + update): body with a known `{{placeholder}}` passes; unknown `{{token}}` → 400 listing it; Handlebars block tokens (`{{#if x}}`/`{{/if}}`/`{{else}}`) ignored; null `available_placeholders` + any token → 400; update validates against the new trigger when `notification_type` changes.
- *update*: predefined EMAIL — template_name/subject/body/is_active/tag + allowed config keys succeed; `notification_type`/`from_address`/`to_recipients` each → 400; predefined SMS — subject → 400, any config key → 400; custom — trigger change FK-checked, domain re-validated, config merge preserves unprovided keys; per-field audit rows via `recordMany` (count + field contents asserted); no-change call writes nothing; 404.
- *delete*: custom deletes + audit row (snapshot in `previous_value`, `newValue: null`); predefined → 400; 404.
- Remove the duplicate-conflict tests + `ConflictException` import (verify nothing else in the file uses it).

**controller.spec**: booth-agreements `buildReq`/`buildResponse` helpers. POST: service called with `(dto, req.user.id)`, detail row returned, `setHeader('Location', …/<id>)`. PUT/DELETE: delegation with `req.user.id`, returned shapes. Remove duplicate-Conflict and "should support SMS channel" tests.

DTO-level rejections (invalid emails, `{placeholder}` tokens, `sender_id` whitelisting) are exercised through the global ValidationPipe — covered by the Swagger 400 message list and live smoke, not unit specs. Seeder: if no spec exists, the duplicate-pair throw is exercised by running the seeder (verification step).

### 12. Docs (parent repo — user commits separately)

- **`EMAIL_SMS_API_CHANGELOG.md`** — dated entry, **breaking** for POST/PUT: POST payload reworked (required `template_name`/`tag`/`channel_config`, subject required, EMAIL-only, no schedule/follow-up fields) and duplicate-409 removed; PUT now enforces the 76.5 two-tier matrix (field list per tier; `template_name` editable on predefined too — user amendment to the design allow-list) with per-field audit rows; DELETE custom-only; 201/200 now detail shape with Int `id` (+ `Location` on create) replacing the string-id baseline; edit history via the central audit-log endpoint (`entity_type=notification_template`, `entity_id`) — no scoped endpoint (booth-agreements approach); recipients accept literal email addresses only — `{placeholder}` tokens rejected until the dynamic-recipient-resolution phase (77.9 / known-issues #3); permission groups added (visible after `permission-group` seeder re-run); template seeder now create-only. Record the predefined-uniqueness decision: unique `(notification_type, channel)` among predefined rows, seeder/service-enforced, no DB constraint (Prisma can't declare partial indexes; sibling `db push` would drop a raw-SQL one).
- **`EMAIL_SMS_KNOWN_ISSUES.md`** — close #14 (groups added) and #15 (seeder create-only). New rows: (a) predefined-uniqueness invariant is constraint-less by design (revisit if Prisma gains partial-index support or siblings move off `db push`); (b) **BA to define/confirm the validation rules the code enforces but the stories don't specify** — channel EMAIL-only message, subject/template_name/from_name 255-char and trigger-slug 150-char limits, recipient array cap (50), email-format strictness, placeholder whitelist behavior (unknown `{{token}}` → 400, block helpers ignored), recipients-emails-only-until-DRR — owner: BA, factual record per house practice.
- **`.claude/plans/email-sms-management-crud-design.md`** — mark POST/PUT/DELETE built (2026-06-11); amend the supporting-endpoints `GET /:id/audit-logs` row to "not built — central audit-log endpoint with entity filters (booth-agreements approach)".

## Traps

- `channel_config` **must** be a typed nested class — with a plain `object` type, `forbidNonWhitelisted` rejects the whole property instead of whitelisting its keys.
- `{ ...config } as Prisma.InputJsonObject` cast required (Prisma 7 `InputJsonValue` rejects class instances) — for both create and the update merge.
- Do NOT add an enum migration — `notification_template` already shipped in `20260611120000_sbe671_email_sms_management`; sibling repos already have it.
- The update DTO cannot reject predefined-locked fields itself (it can't see `is_predefined`) — those rejections are service-layer with explicit messages.
- **Placeholder-whitelist pre-flight**: before shipping, diff every simple `{{token}}` in the 20 seeded bodies/subjects against that trigger's seeded `available_placeholders`. Any gap means an admin re-saving an *unchanged* predefined body would 400 — fix by extending the trigger-event seeder's placeholder lists (code-controlled, ours) before the validation goes live. Handlebars block tokens (`{{#if x}}`, `{{/if}}`, `{{else}}` — present in `ppl_product_order_payment`) are skipped by the validator, not whitelisted.
- Existing `update`/`delete` tests and the `toResponse`/`NotificationTemplateResponseDto` removal ripple through both spec files — sweep imports.
- `GET` list/detail and the trigger-events / allowed-from-domains modules stay untouched.

## Verification (no commits — user reviews & commits per repo)

From `admin-backend-api/`:
1. `npx tsc --noEmit`
2. `npm run lint`
3. `npx jest src/admin/notification-template src/admin/common/audit` — then full `npm test` once
4. Live smoke — create: valid POST → 201 detail body + `Location` + audit row (`entity_type='notification_template'`, `performed_by` = JWT user); same payload twice → both 201; SMS → 400; unknown trigger → 400; bad FROM domain → 400 with `errorType`; `sender_id` key → 400; `{token}` recipient → 400 (emails only until DRR); `schedule_config` in payload → 400.
5. Live smoke — edit: predefined row: template_name/body/tag/is_active + `from_name`/`cc_recipients` succeed (one audit row per changed field), `notification_type`/`from_address`/`to_recipients` each → 400; re-saving an unchanged seeded body (incl. `ppl_product_order_payment` with its `{{#if}}` blocks) passes the placeholder check; body with `{{unknown_token}}` → 400; custom row: trigger + full config edit succeeds, partial config merge preserves unprovided keys; no-op PUT writes no audit rows.
6. Live smoke — delete: custom → 200 + audit row; predefined → 400.
7. Re-run seeders: template seeder skips all 20 existing rows (create-only) and the duplicate-pair assertion passes; four `notification_template` groups appear in the role-permissions UI.
8. Swagger UI: POST/PUT/DELETE show EMAIL-only enum, nested channel_config schemas, detail-shape examples, no 409s; central audit-log endpoint returns the new rows filtered by `entity_type=notification_template&entity_id=<id>`.

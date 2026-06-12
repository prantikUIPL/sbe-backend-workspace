# Email & SMS Management — Known Issues Register

> **Purpose:** a running list of open items, deferrals, and contradictions for the Email & SMS Management module. This register records *what is known* for downstream teams (engineering, BA, documentation, and the teams owning adjacent services). It does **not** decide ownership or applicability of resources we do not own.
>
> **Source epic:** `Email & SMS Management Upadated Epic.xlsx` — restructured into two epics:
> - **76.x — Predefined Email & SMS Management** (edit-only; Email + SMS)
> - **77.x — Custom Email Management** (full CRUD; Email only)
>
> Predefined and custom are shown separately in the UI with separate CRUD screens but use the **same API endpoints** (backend branches on `is_predefined`). The previously-agreed schema (`.claude/plans/email-sms-management-crud-design.md`) is reused as-is.
>
> **Updated user stories:** `Email & SMS Management V2.xlsx` (full-text stories, 21 rows across the two epics). This register was reconciled against V2 on the date below. The V2 stories **fully specify** Scheduling, SMS provider, and (custom) Dynamic Recipient Resolution; those remain **out of current-sprint scope per a verbal agreement with the BA team (2026-06-03)** — documented here, not built this sprint. **Exception:** the Dynamic Recipient Resolution story V2 added to the *predefined* epic is **not a deferral** — it does not apply and must be removed (see issue #3).
>
> **Last updated:** 2026-06-12 (latest: **dev schema collision found & resolved while rebasing onto `dev` — new #20.** Another team's merged work re-declared the shared `notification_templates` model with a pre-SBE-671 shape and added five `coupon_codes` BIGINT FK columns referencing its id; the rebase kept the SBE-671 schema, retyped those five columns to INTEGER, and extended migration `20260611120000` to drop/recreate the coupon FKs around the id type change — see #20 and the 2026-06-12 schema entry in `EMAIL_SMS_API_CHANGELOG.md`. Payment-flow team informed same day — #20 closed. Earlier same day: live HTTP smoke, full module — 33/35 checks passed against a locally booted server; both findings actioned same day: hex/exponent id bypass of `ParseIntIdPipe` **fixed in code** — global `ValidationPipe` coerced `"0x10"`→16 before the pipe ran; raw-string param extraction restores the numeric-string check on all six guarded `:id` routes incl. booth-agreements, see `EMAIL_SMS_API_CHANGELOG.md` — and **new #19**: predefined `channel_config` has no API path back to its system-default `null` once an editable key is written. Earlier same day — re-verification audit, 2nd pass: listing now joins `trigger_event.label` — returned in list rows and matched by `search`, so searching the displayed Trigger Event label works per 76.2/77.3; `subject` participating in search recorded as code-only in #17; stale "push" wording removed from the Swagger tag description. Earlier same day — implementation-vs-stories audit: five story deviations **fixed in code** — search cap 150→254, multi-select `tag`/`channel` filters, `from_name`/`reply_to` now optional on create, CC/BCC de-duplication, HTML/XSS body sanitization — see the 2026-06-12 entry in `EMAIL_SMS_API_CHANGELOG.md`; #17 amended accordingly. New: **#18 — DELETE endpoint has no backing user story** in either epic; BA to add one or confirm the design-doc justification. Previous 2026-06-11: template CRUD **implemented** — POST custom-EMAIL create / PUT two-tier edit / DELETE custom-only, see `EMAIL_SMS_API_CHANGELOG.md`. Closes #14 (permission groups added) and #15 (template seeder now create-only). New: #16 constraint-less predefined-uniqueness invariant; #17 BA to define validation rules the code enforces but the stories don't. #8 amended: no scoped audit endpoint — central audit-log endpoint with entity filters. Earlier same-day: schema foundation implemented across all 5 repos — migration `20260611120000_sbe671_email_sms_management`, seeders, mirrored schemas; FK via globally-unique `trigger_events.slug` — see issue #13; `notification_templates.id` converted BigInt→Int; 20 trigger rows seeded, not 18 — the 2 extra pre-existing slugs are FK-required. Prior 2026-06-10 reconciliations: `type`→`tag` rename — #11; custom-DRR reopened-but-still-deferred — #3; custom-SMS scoped out — #12)

---

## Main issues

| # | Issue | Status | Owner | Schema impact |
|---|-------|--------|-------|---------------|
| 1 | Email & SMS Scheduling (predefined Scheduling + `77.8`) | Deferred — out of scope (verbal BA agreement 2026-06-03); fully specified in V2, not built this sprint | TBD (later phase) | None |
| 2 | Integrate an SMS provider (`76.8`) | Deferred — client dependency; specified in V2 | Client / later phase | None |
| 3 | Dynamic Recipient Resolution Engine — custom (`77.9`) **deferred**; predefined (new in V2 row 10) **does not apply — remove from predefined epic** | Custom: deferred (later phase). Predefined: contradiction — predefined recipients are system-defined / read-only | Custom: later phase · Predefined: BA to remove | None |
| 4 | Recipient picker source lists | Open — depends on endpoints we don't own | Owning service / BA | None |
| 5 | Template Type enum: `Event` vs `System` contradiction | Open — V2 did **not** reconcile; we use `System` | BA / Documentation | None |
| 6 | `Both` channel in predefined Listing / Detail | Open — unsupported by single-channel model | BA / Documentation | None |
| 7 | From-Email domain text replaced by brand titles (auto-link/crawler artifact) | Open — BA to restore the two domain strings in the stories | BA / Documentation | None |
| 8 | Audit "last modified by" wording — stored on record vs derived | Resolved (ours) — derived from `admin_audit_logs`; functionally equivalent. **Amended 2026-06-11:** the listing response does **not** include last-modified info at all. **Re-amended 2026-06-11 (CRUD phase):** there is **no scoped `GET /:id/audit-logs` endpoint** — audit rows are written by the CRUD handlers and consumed via the **central audit-log endpoint's** `entity_type`/`entity_id` filters (booth-agreements approach). **BA to update story 76.1** (remove "last modified by/date" from the listing columns or re-point it to the central audit-log screen) | Us → BA to update 76.1 | None |
| 9 | WYSIWYG "images" vs separate image-upload module | Open — confirm URL-reference only this sprint | BA / Documentation | None |
| 10 | Custom listing "event selector" ambiguity | Open — clarify intent | BA / Documentation | None |
| 11 | Column rename `type` → `tag` (TL design review, 2026-06-10) | Resolved — applied to design docs; column is `tag`, enum name `NotificationTemplateType` unchanged. Carry into `schema.prisma`/DTO/query param (`?tag=`)/seeder when code is implemented | Us | None (rename only) |
| 12 | Custom SMS templates — schema-supported but **out of current scope** | Resolved (scope) — V2 `77.x` Custom epic is **Email only** (Change Log #2); custom create rejects `channel = SMS`. Predefined SMS (`76.x`) stays in scope, edit-only. `NotificationChannel.SMS` + the SMS `channel_config` variant remain, so re-introducing custom SMS later needs **zero schema change** | BA (if custom SMS wanted later) | None |
| 13 | `trigger_events` FK design amended at implementation (2026-06-11): composite unique `(slug, is_custom)` + partial-index FK → **globally unique `slug`** | Resolved (ours) — **Postgres FKs cannot reference partial unique indexes**, so the reviewed design was not implementable. Global unique `slug` preserves the 1:1 predefined-trigger ↔ slug mapping and keeps the FK Prisma-native in all 5 schemas. Consequence: a future *custom* trigger cannot reuse a predefined slug (distinct slugs required). Routed to TL for sign-off | Us → TL sign-off | Implemented — `slug` UNIQUE; `is_custom` retained as a flag column |
| 14 | `notification_template.*` permission keys are not mapped in `permission-group.seeder.ts` (2026-06-11) | **Resolved 2026-06-11 (CRUD phase)** — four groups added to `permission-group.seeder.ts` (View / Create / Update / Delete Notification Template(s), module `notification_template`; Create/Update/Delete depend on View, cf. `booth-agreements`). Environments must re-run the seeders for the groups to appear in the role-permissions UI | Us | None |
| 15 | `notification-template.seeder.ts` re-run **clobbers admin edits** to predefined templates (2026-06-11) | **Resolved 2026-06-11 (CRUD phase)** — seeder is now **create-only**: existing rows (matched by `notification_type` + `channel` + `language`) are skipped on re-run, never updated, so admin edits to predefined copy survive seed re-runs. Trade-off accepted: seed-driven copy updates to already-seeded environments are no longer possible — future copy changes to existing templates ship as one-off migrations or admin edits. The seeder also fail-loudly asserts the catalog has no duplicate `(notification_type, channel)` pair (see #16) | Us | None |
| 16 | Predefined-uniqueness invariant — `(notification_type, channel)` unique among `is_predefined = true` rows — is **constraint-less by design** (2026-06-11) | Resolved (ours, recorded) — a send-time query by trigger + predefined must return one row. No DB constraint backs this: Prisma PSL cannot declare partial unique indexes, and a sibling repo's `db push` would silently drop a raw-SQL one. Enforced by the seeder catalog assertion (#15) + service construction (API create always writes `is_predefined: false`; edit never flips the flag). **Revisit if** Prisma gains partial-index support or the sibling repos move off `db push` | Us (revisit on tooling change) | None (deliberately no constraint) |
| 17 | Validation rules enforced in code but **not specified in the stories** (2026-06-11; **amended 2026-06-12**) | Open — BA to define/confirm so the stories and the implementation agree. **Resolved by the 2026-06-12 story-alignment fixes** (now match the stories): search cap (254), multi-select `tag`/`channel` filters, optional `from_name`/`reply_to`, CC/BCC de-duplication, HTML/XSS sanitization of `body` and plain-text fields. **Still code-only (not in any story):** channel restriction message (`Only EMAIL channel is supported` — positive phrasing, SMS not named); length caps (`template_name`/`subject`/`from_name`/email fields ≤255, trigger slug ≤150, `language` ≤10); recipient array caps (`to_recipients` 1–50, `cc`/`bcc` ≤50); email-format validation on all address fields; placeholder whitelist (unknown `{{token}}` in subject/body → 400; Handlebars block helpers ignored); recipients are **literal emails only until DRR** (77.9/#3); unknown `channel_config` keys rejected; sanitizer is **blocklist-based** (scripts/event handlers/executable URLs stripped; formatting/tables/images kept — the stories say "stripped/sanitized" without specifying scope); `to_recipients` is **not** deduped (stories mandate dedup for CC/BCC only; cross-field dedup deferred with DRR, #3); **listing search also matches `subject`** (found 2026-06-12 re-audit — the search stories 76.2/77.3 name Template Name and Trigger Event only; both are matched — name, plus trigger slug *and* label since 2026-06-12 — `subject` is an extra field, superset behavior) | BA / Documentation | None |
| 18 | `DELETE /notification-templates/:id` has **no backing user story** (found 2026-06-12) | Open — neither epic contains a Delete story (76.x is edit-only by design; the custom epic 77.x ends at `77.10'` Audit Log, with no delete row in either `Email & SMS Management Upadated Epic.xlsx` or `Email & SMS Management V2.xlsx`). The endpoint exists per the agreed design doc (`crud-design.md`: custom epic = "full CRUD") and is custom-only, audited, with send-history FK cascade. **BA to add a Custom Email "Delete Template" story** (or formally confirm the design-doc justification) so the endpoint is traceable to a requirement | BA / Documentation | None |
| 19 | Predefined `channel_config` — **no API path back to the system-default `null`** once an editable key is written (found 2026-06-12, live HTTP smoke) | Open — all 20 seeded predefined rows ship with `channel_config = null` (the mailer's hard-coded behavior is the "system default"). Story 76.5 lets admins edit `from_name`/`reply_to`/`cc`/`bcc`, and the first such `PUT` materializes a `channel_config` object. After that there is **no way to revert to `null`**: explicit `null` for the object or its keys is rejected with 400 by design (the `IsOptionalNonNull` guard that closes the silent-null-write hole), and the top-level merge updates/adds keys but never removes them. Empty-ish values (`""`, `[]`) are the closest available reset but are stored values, not "absent". The stories never mention reverting to defaults, so this is a gap, not a deviation. **BA/design to decide** whether a "reset to system default" action is wanted (e.g. a dedicated endpoint or an explicit reset flag — NOT bare `null`, which stays rejected); until then, environments needing a true revert require a DB update or re-seed of that row | BA / Design (decision), then Us | None |
| 20 | **`dev` schema collision on the shared `notification_templates` table** (found 2026-06-12 while rebasing `feature/SBE-671` onto `dev`) — payment-flow/PPL work merged into admin `dev` (PRs #413 `fix/change-payment-flow`, #414 `feat/pplalgonew`) re-declared `NotificationTemplate` with a **pre-SBE-671 shape** (BigInt id, `channel` VarChar(50), no `tag`/enums/trigger FK) and added **five `coupon_codes` BIGINT FK columns** referencing `notification_templates.id` (`first/final_reminder_notification_template_id` CASCADE; `coupon_expire_date_email_template_id`, `first/final_reminder_on_lead_threshold_email_template_id` SET NULL — via migrations `20260527110000`/`20260527120000`/`20260602110000`) | **Resolved in code 2026-06-12 (user-approved)** — rebase kept the SBE-671 model (Int PK, enums, trigger-event FK), grafted the two coupon reminder relations onto it, retyped the five `coupon_codes` columns `BigInt?`→`Int?`, and extended migration `20260611120000_sbe671_email_sms_management` to drop the five coupon FKs, ALTER the columns to INTEGER, and recreate each FK with its original name and ON DELETE rule. One-line fix in `coupon-codes.service.ts` (`ids.map(BigInt)` → `ids`). Applied across all 5 repos (exhibitor/worker mirrored the retype; external/pulse `dev` never had the coupon columns); pre-push gates green ×5 incl. full migration replay; pushed. **Payment-flow team informed 2026-06-12 — closed.** What they were told: their five columns convert BIGINT→INTEGER at migrate deploy; generated Prisma types for these fields (and `notificationTemplate.id`) change `bigint`→`number`; recorded factually: their three expire-date/lead-threshold FK columns have **no `@relation`** in the Prisma schema (DB-level FKs only) — their call whether to add relations | Closed (team informed 2026-06-12) | Implemented — `notification_templates.id` + 5 `coupon_codes` FK columns now INTEGER; see `EMAIL_SMS_API_CHANGELOG.md` 2026-06-12 schema entry |

---

## 1. Email & SMS Scheduling — predefined Scheduling + `77.8` (custom)

- **Deferred** from the current sprint — **out of scope per verbal agreement with the BA team (2026-06-03)**.
- **V2 status:** the V2 stories ("Email and SMS Scheduling", file rows 7 and 20) now carry a full specification (follow-up frequency, days-after-trigger offsets, validation, execution). This is documentation only; no scheduler is built this sprint.
- **Schema impact: none.** The `schedule_config` and `follow_up_config` columns are kept in the migration as **nullable** JSONB. They have no writer or reader this sprint; when scheduling is picked up later, no new migration is required.

## 2. Integrate an SMS provider — `76.8`

- **Deferred** — flagged in the epic as a client dependency on the provider; **out of scope per verbal BA agreement (2026-06-03)**.
- **V2 status:** the V2 story ("Integrate an SMS provider", file row 9) specifies provider integration, dispatch, and delivery-outcome handling — all marked *Subject to client confirmation / R&D*. Documentation only this sprint.
- **Schema impact: none.** SMS templates are still stored and editable via the `NotificationChannel.SMS` enum value and the SMS variant of `channel_config`. Actual SMS sending is gated until a provider is integrated.

## 3. Dynamic Recipient Resolution Engine — custom (`77.9`) deferred; predefined (V2 row 10) does not apply

V2 introduces **two** Dynamic Recipient Resolution Engine stories — one in the **custom** epic (`77.9`, file row 21) and a **new** one in the **predefined** epic (file row 10). They are handled **differently**:

**Custom (`77.9`) — Deferred (out of current sprint).**
- Send-time resolution of `{salesperson}`, `{main customer contact}`, `{all customer contacts}`, internal Gmail groups, etc. is **out of scope this sprint** (verbal BA agreement 2026-06-03). A valid later-phase story.
- **Schema impact: none.** `to_recipients` stores literal address strings / placeholder tokens today; send-time resolution is deferred to the mailer plan.
- **TL design review reopened this (2026-06-10).** Inline annotations on `EMAIL_SMS_DB_DESIGN_REVIEW.md` ("Resolution Engine is required @amrin" on the custom EMAIL `to_recipients` example; "need to implement" on the §5 out-of-scope DRR line) flagged that a resolution engine is wanted for custom. **Standing decision is unchanged: custom DRR remains deferred to the follow-on mailer plan** — the annotations are reviewer questions, not approved scope. The inline notes have been resolved into a pointer to this entry; BA/TL to confirm whether to pull custom DRR forward into its own story ahead of the mailer plan.

**Predefined (V2 row 10) — Does NOT apply; remove from the predefined epic.**
- **Predefined templates are system emails / SMS** with **system-defined recipients**. The TO / FROM (and `sender_id`) are **system-controlled and read-only** — an admin cannot change who a predefined template is sent to, because doing so would **disrupt the system-defined send flows** that fire these templates.
- A Dynamic Recipient Resolution Engine in the predefined epic therefore **contradicts the agreed design** (`crud-design.md`: predefined `from_address` / `to_recipients` / `sender_id` are system-controlled, resolved by the calling code at send time — not admin-editable).
- **Action:** BA / Documentation to **remove the Dynamic Recipient Resolution Engine story from the predefined epic** (row 10). Dynamic recipient resolution belongs to **custom only**.

## 4. Recipient picker source lists (TO / CC / BCC "select from a predefined list")

The stories require admins to select recipients from predefined lists ("admin users, exhibitors, and other relevant system emails"). Those lists are sourced from listing endpoints **owned by other modules/services** — applicability, auth scoping, and ownership are decisions for the consuming/owning teams, **not** this module.

Recorded factually below are the listing endpoints observed in the codebase that return email-bearing records. No judgment is made here on which are appropriate for the picker.

**admin-backend-api** (global prefix `api/v1`)

| Route | Email field |
|-------|-------------|
| `GET /users` | `email` |
| `GET /exhibitors` | `email` |
| `GET /providers` | `exhibitor.email` (nested) |
| `GET /ppl-seeker` | `email` |
| `GET /ppl-service-provider-overview/list` | `email` |
| `GET /ppl-service-provider-detail-view` | `email` |

**exhibitor-backend-api** (global prefix `api/v1`)

| Route | Email field |
|-------|-------------|
| `GET /company-user/list` | `email` |
| `GET /leads/accepted` | `email` |

**external-api-service**

| Route | Email field |
|-------|-------------|
| — | none observed (webhook/integration handlers only) |

> Auth, guards, and request scoping on each endpoint are the consuming team's responsibility to evaluate.

**Sub-notes**
- **"Other relevant system emails"** referenced in the stories (V2 rows 6, 13, 18) has **no observed source endpoint** — flagged for the owning team to define.
- **Internal Gmail groups** (V2 custom DRR, row 21) likewise have no observed source — deferred with the DRR engine (issue #3).
- **Manual free-text recipient entry** is specified as **custom-email only**; predefined templates select from lists only.

## 5. Template Type enum — `Event` vs `System` contradiction

The stories remain internally inconsistent on the Template Type values; **V2 did not reconcile this**:

- **Filter stories** (V2 rows 4 and 16) list: `Store, Internal, Vendor, Product, PPL, `**`Event`**
- **Create / Edit stories** (V2 rows 6, 13, 18) list: `Store, Internal, Vendor, Product, PPL, `**`System`**

**What we are using:** **`System`**. The implementation enum `NotificationTemplateType` is `Store, Internal, Vendor, Product, PPL, System` — there is no `Event` value.

**Action:** BA / Documentation team to reconcile the story wording so the Filter stories read `System` instead of `Event`.

## 6. `Both` channel in predefined Listing / Detail

V2 predefined Listing (file row 2) states the Channel column "shall clearly indicate whether the template is Email, SMS, **or both**."

- **Misalignment:** our model is **single-channel per template** — `NotificationChannel` is `EMAIL` **or** `SMS`; a row cannot be both.
- **What we are using:** one channel per template row. "Both" is not represented.
- **Action:** BA / Documentation to drop "or both" from the Channel description.

## 7. From-Email domain text replaced by brand titles (auto-link / crawler artifact)

In V2 custom Create / Edit (file rows 13, 18) the two sending-domain options render as **brand titles** — "I'll be attending!" and "Small Business Expo | Business Conference & Networking Event" — instead of the domain strings.

- **Root cause (confirmed by user):** the original story text contained the actual domains; an **auto-link / crawler substitution** replaced each domain string with the linked site's page title (`TheShowProducers.com` → "I'll be attending!", `TheSmallBusinessExpo.com` → "Small Business Expo | Business Conference & Networking Event"). This is a text artifact, not a requirements change.
- **What we are using:** unchanged — the FROM local-part is free-text and the **domain part is restricted to `theshowproducers.com` or `thesmallbusinessexpo.com`** via the `allowed_from_domains` lookup.
- **Action:** BA / Documentation to **restore the two domain strings** in the story text (and disable auto-linking so it does not recur).

## 8. Audit "last modified by" — stored on record vs derived

V2 Audit Log stories (file rows 11, 22) say the system "shall **persist** the last modified timestamp and last modified by user **against the template record**."

- **What we are doing:** "last modified by / at" is **derived from the existing `admin_audit_logs`** (the design drops a dedicated `updated_by` column on the template; `updated_at` covers the timestamp). The admin sees the same information (who / when / field-level before-after).
- **Status:** functionally equivalent — **no change required**; recorded so the wording difference is not mistaken for a gap. Noted for BA.
- **Amended 2026-06-11 (listing implementation decision):** the listing endpoint (`GET /notification-templates`) does **not** return any last-modified-by information. Audit data lives in the **separate `admin_audit_logs` table** and will be exposed through the **separate audit-logs endpoint** (`GET /notification-templates/:id/audit-logs`, later phase). The list row carries only the record's own `updated_at`.
- **Action:** **BA to update story 76.1** — it currently lists "last modified by/date" among the listing columns; either remove it from the listing or re-point it to the audit-log endpoint/screen. (Endpoint change itself is documented in `EMAIL_SMS_API_CHANGELOG.md`.)

## 9. WYSIWYG "images" vs separate image-upload module

V2 Edit / Create stories (file rows 6, 13, 18) state the WYSIWYG editor supports "formatting, images, hyperlinks, and call-to-action buttons."

- **What we are doing this sprint:** the implementation **stores the provided HTML body only**. Image **upload / asset hosting is a separate story module**, developed independently. Referencing already-hosted image URLs inside the HTML is fine.
- **Action:** BA / Documentation to confirm "images" here means **referencing hosted URLs**, not in-editor upload/hosting (which belongs to the separate module).

## 10. Custom listing "event selector" ambiguity

V2 custom "Email Template Listing" (file row 14) adds an **event selector on the listing page**, populated from the predefined event list.

- **Ambiguity:** trigger-event selection in our design happens during **Create / Edit**, not on the listing. An event selector on the listing reads as either a filter or a create entry point.
- **Action:** BA / Documentation to clarify the intent of the listing-page event selector.

---

## Cosmetic / non-functional notes (no action needed by us)

- Custom-epic Search / Filter stories are still titled "**Email & SMS** Template Search/Filter" although the custom epic is **Email-only**. The custom Filter (row 16) correctly omits the Channel filter; only the title carries the leftover wording.
- Predefined Listing (row 2) names its data source "Auto_Email_Notification_Triggers configuration"; we source the list from the seeded `notification_templates` table. Same data, different label.

## Confirmed aligned with V2 (recorded so they are not re-raised)

- Predefined edit allows **From name, Reply-to, CC, BCC** — matches the `channel_config` EMAIL editable key set; `from_address` and `to_recipients` remain system-controlled/read-only.
- **Manual free-text recipient entry = custom-email only**; predefined selects from lists only.
- **Custom epic = Email only** (no custom SMS); trigger event is read-only / chosen from the predefined dropdown; placeholders are code-controlled and not admin-editable.

---

## Decisions captured (for traceability)

- **Scheduling columns kept nullable** — `schedule_config` / `follow_up_config` are created now but unused this sprint, so reintroducing scheduling later needs no migration.
- **Image upload is a separate story module** — developed independently. This implementation stores only the **provided HTML body**; it does not include asset upload/hosting.
- **Three big deferrals — Scheduling, SMS provider, and *custom* Dynamic Recipient Resolution (`77.9`) — are out of current-sprint scope per a verbal agreement with the BA team (2026-06-03)**, even though the V2 stories specify them in full. Each is zero-schema-impact to defer.
- **Predefined Dynamic Recipient Resolution (V2 row 10) is *not* a deferral** — it does not apply (predefined recipients are system-defined / read-only) and is flagged for BA removal (issue #3).

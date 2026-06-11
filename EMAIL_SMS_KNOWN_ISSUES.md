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
> **Last updated:** 2026-06-11 (schema foundation **implemented** across all 5 repos — migration `20260611120000_sbe671_email_sms_management`, seeders, mirrored schemas. Implementation amendments: FK via globally-unique `trigger_events.slug` — see issue #13; `notification_templates.id` converted BigInt→Int; 20 trigger rows seeded, not 18 — the 2 extra pre-existing slugs are FK-required. Prior 2026-06-10 reconciliations: `type`→`tag` rename — #11; custom-DRR reopened-but-still-deferred — #3; custom-SMS scoped out — #12)

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
| 8 | Audit "last modified by" wording — stored on record vs derived | Resolved (ours) — derived from `admin_audit_logs`; functionally equivalent. **Amended 2026-06-11:** the listing response does **not** include last-modified info at all — it is served by the **separate audit-logs endpoint** (`GET /:id/audit-logs` over the separate `admin_audit_logs` table). **BA to update story 76.1** (remove "last modified by/date" from the listing columns or re-point it to the audit endpoint) | Us → BA to update 76.1 | None |
| 9 | WYSIWYG "images" vs separate image-upload module | Open — confirm URL-reference only this sprint | BA / Documentation | None |
| 10 | Custom listing "event selector" ambiguity | Open — clarify intent | BA / Documentation | None |
| 11 | Column rename `type` → `tag` (TL design review, 2026-06-10) | Resolved — applied to design docs; column is `tag`, enum name `NotificationTemplateType` unchanged. Carry into `schema.prisma`/DTO/query param (`?tag=`)/seeder when code is implemented | Us | None (rename only) |
| 12 | Custom SMS templates — schema-supported but **out of current scope** | Resolved (scope) — V2 `77.x` Custom epic is **Email only** (Change Log #2); custom create rejects `channel = SMS`. Predefined SMS (`76.x`) stays in scope, edit-only. `NotificationChannel.SMS` + the SMS `channel_config` variant remain, so re-introducing custom SMS later needs **zero schema change** | BA (if custom SMS wanted later) | None |
| 13 | `trigger_events` FK design amended at implementation (2026-06-11): composite unique `(slug, is_custom)` + partial-index FK → **globally unique `slug`** | Resolved (ours) — **Postgres FKs cannot reference partial unique indexes**, so the reviewed design was not implementable. Global unique `slug` preserves the 1:1 predefined-trigger ↔ slug mapping and keeps the FK Prisma-native in all 5 schemas. Consequence: a future *custom* trigger cannot reuse a predefined slug (distinct slugs required). Routed to TL for sign-off | Us → TL sign-off | Implemented — `slug` UNIQUE; `is_custom` retained as a flag column |
| 14 | `notification_template.*` permission keys are not mapped in `permission-group.seeder.ts` (2026-06-11) | Open (ours) — the role-permissions UI grants per **permission group** (module-wise checkboxes); ungrouped keys can only be granted via the raw `POST /roles/:id/permissions` API. The supporting dropdown keys (`trigger-events.list`, `allowed-from-domains.list`) **are** group-mapped; the five `notification_template.*` keys are not, so a custom role built through the UI gets the dropdowns but not the template screens. Add the groups (View / Create / Edit / Delete pattern, cf. `booth-agreements`) in the edit/CRUD rewrite phase when the final permission set is known | Us (CRUD phase) | None |
| 15 | `notification-template.seeder.ts` re-run **clobbers admin edits** to predefined templates (2026-06-11) | Open (ours, deferred to edit-endpoint rewrite) — the seeder's update branch writes the FULL payload (`{...template, ...meta, is_predefined: true}` incl. `subject`, `body`, `is_active`) over every existing row on each `seed:run`, and `run-seeds.ts` runs it unconditionally. Harmless today (no edit endpoint), but 76.x is **edit-only**: the moment the edit endpoint ships, any admin edit to predefined copy is silently reverted by the next seed re-run (which our own changelog instructs environments to perform). Fix is NOT a simple `update: {}` (cf. the allowed-from-domain seeder fix) — pre-edit environments may legitimately need seed-driven copy updates; needs an edited-flag / update-only-if-untouched / metadata-only-update strategy, decided when the edit endpoint is built | Us (edit-endpoint phase) | None |

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

# Email & SMS — Story 77.9 Dynamic Recipient Resolution Engine: Implementation Gap Analysis

| | |
|---|---|
| **Date** | 2026-07-06 |
| **Sprint** | 6 |
| **Module** | SBE-671 Email & SMS Management |
| **Story** | 77.9 — Dynamic Recipient Resolution Engine (DRR) |
| **Status** | Pre-implementation gap review |

## Purpose

This document lists the open blockers and ambiguities that must be confirmed with the BA and/or client **before** engineering starts building Story 77.9. Each item pairs the written requirement (V2 row 20 / client feedback) against what the current codebase actually does, states why the mismatch blocks a clean build, and poses a single decision-ready question. It is intended to be worked through in a BA/client session; the "Consolidated question checklist" at the end can be pasted straight into an email.

This is **not** a design or scheduling document. The dynamic-scheduling / follow-up track is designed separately; DRR only intersects it at one point (see DRR-13), and that intersection is called out as a question rather than resolved here.

## Story summary

Story 77.9 introduces an engine that, at email dispatch time, resolves dynamic recipient tokens and internal Gmail groups into concrete addresses and compiles the final recipient set for the send. As written in V2 row 20 it:

- Lets an admin place dynamic tokens — `{salesperson}`, `{main customer contact}`, `{all customer contacts}` — and internal Gmail groups into the **TO field**, alongside predefined-list recipients and manually typed external emails.
- Resolves those tokens **at send time using the most current data** (not at config time), based on the trigger event and its associated context.
- Requires resolved addresses to be valid (RFC 5322), defines fallback handling for unresolvable recipients (skip / default / abort — "Subject to R&D"), forbids dispatch to zero valid recipients, requires cross-field To/CC/BCC de-duplication, and requires that resolution outcomes be logged per dispatch.
- As written, 77.9 is **email-only**; SMS is referenced only via a cross-dependency from 76.8.

## Current codebase state

What already exists that the story builds on:

- **Channel scope is email-only today.** `SUPPORTED_TEMPLATE_CHANNELS = ['EMAIL']` (`notification-template.dto.ts:27`); custom SMS is rejected at create (KNOWN_ISSUES #12). `channel_config` is modelled by `EmailChannelConfigDto` only.
- **Recipient fields.** `EmailChannelConfigDto` exposes `from_address`, `reply_to`, `to_recipients`, `cc_recipients`, `bcc_recipients` (`notification-template.dto.ts:175-228`). Every entry is validated with `IsEmail` (`notification-template.dto.ts:66, 81-97, 93`), so a token cannot be stored in any field today — the DTO comment says validation is loosened only "until the Dynamic Recipient Resolution phase" (`notification-template.dto.ts:172-173`). `from_address` is further constrained to the `AllowedFromDomain` whitelist.
- **Mailers take caller-supplied recipients.** All four mailer services accept recipients from the call site — worker `mailer.service.ts:90-157`, admin `:194-237`, exhibitor `:118-158`, external `:88-131`. **No send path reads `channel_config`** (grep returns zero hits across worker/exhibitor/external/pulse and admin outside the notification-template module).
- **Live triggers compute recipients in code.** e.g. `order-notification.service.ts:99-218` walks `billing_email` → primary Exhibitor. There is **no unified trigger-context object**; context is ad-hoc per call site (worker `mailer.service.ts:36` carries `exhibitorId?`; order path carries `orderId`; auth/contact-us carry a raw email).
- **Membership model.** `CompanyUser` was dropped (migration `20260521120000_drop_company_users_table`). Membership now lives on `Exhibitor` (admin `schema.prisma:1023-1060`), discriminated by `user_type` SmallInt (`=1` primary, `=2` invited). `Exhibitor.company_id` is declared `@unique` in both schemas (`schema.prisma:1030`) but the real DB has a **non-unique** index `idx_exhibitors_company_id` (init migration `20260303120000_init:241`) — multi-member is real (schema drift).
- **Salesperson linkage.** Only `Order.sales_person_id Int?` → `salesPerson User?` (admin `schema.prisma:1615/1634`), and it is nullable. No `Company.sales_person_id`. `Exhibitor` carries different roles `referred_by` / `strategist_id` (`schema.prisma:1033-1034/1055-1056`). `User.email` is required-unique (`schema.prisma:12`); `User.phone` optional (`schema.prisma:16`).
- **Audit log.** `NotificationLog` (`schema.prisma:309-335`) stores a single `email String?` (`:312`) plus `user_id`/`exhibitor_id`/`status` — no cc/bcc and no resolved-recipient-set structure. Worker logs only `options.to[0]` (`mailer.service.ts:129`).
- **Dedup.** `dedupeEmails` (`notification-template.service.ts:109-119`) is applied only to cc/bcc within-field on write (`:273-274, :387-389`); `to_recipients` is not deduped and there is no cross-field dedup.
- **No group / consent concepts.** No group / distribution-list / recipient-list-source model exists; the only multi-recipient precedents are flat `String[]` columns (Product notification arrays, `schema.prisma:1291`) and `CompanyLeadEmail` (PPL-scoped, `schema.prisma:1123-1136`). No consent/opt-in/opt-out or per-recipient permission model exists in any of the five schemas.

## Open questions — must confirm before implementation

### Blockers

---

#### DRR-05 — Source of truth at send time: stored `channel_config` is never read today

| | |
|---|---|
| **Requirement** | V2 row 20 Design Spec (`story_sources.txt:415-439`): the engine operates at the backend during dispatch, identifies placeholders/groups/static recipients configured on the template, resolves them at send time, and compiles the final recipient set. |
| **Codebase reality** | No send path reads `channel_config` (zero grep hits across worker/exhibitor/external/pulse and admin outside the notification-template module). All four mailers take caller-supplied recipients (worker `mailer.service.ts:90-157`, admin `:194-237`, exhibitor `:118-158`, external `:88-131`). Live triggers compute recipients in code (`order-notification.service.ts:99-218`). Seeded predefined templates carry no `channel_config` (`notification-template.seeder.ts`). |
| **The gap** | DRR presumes stored template recipients drive dispatch, but today recipients are computed at the call site and stored `channel_config` is written-but-never-read. Whether the send path switches to template `channel_config`, keeps call-site logic, or merges both is undefined — and predefined templates (no `channel_config`) may or may not be in scope. |
| **Why it blocks** | Determines whether 77.9 is a small resolver or a rewrite of recipient handling in all four mailers plus every existing call site. Building the resolver without deciding the source of truth risks double-sending or dropping existing hard-coded recipients. |
| **Owner** | BA |

> **Question:** At send time, what is the authoritative recipient source — the template's stored `channel_config`, the existing call-site-computed recipients, or a merge? And are predefined templates (which store no `channel_config`) in scope for DRR, or is DRR custom-email only?

---

#### DRR-02 — Primary vs all customer contacts: discriminator + schema drift

| | |
|---|---|
| **Requirement** | V2 row 20 (`story_sources.txt:456-460`): `{main customer contact}` resolves to the primary customer contact; `{all customer contacts}` resolves to all customer contacts associated with the trigger event context. |
| **Codebase reality** | No `is_primary`/role flag exists; `CompanyUser` was dropped (migration `20260521120000_drop_company_users_table`). Membership lives on `Exhibitor` (admin `schema.prisma:1023-1060`), discriminated only by `user_type` SmallInt (`=1` primary, `=2` invited) — `company_user.service.ts` (exhibitor repo) filters additional users by `user_type=2`; only `user_type=1` may invite. **Schema drift confirmed:** `Exhibitor.company_id` is declared `@unique` (`schema.prisma:1030`, both schemas) but the real DB has a non-unique index `idx_exhibitors_company_id` (init migration `20260303120000_init:241`) and no migration ever added a unique constraint. The invite flow creates multiple `user_type=2` rows sharing `company_id`, filtering `deleted_at:null` but deliberately keeping `invitation_status='revoked'` rows. Multi-member is real. |
| **The gap** | Whether "main" vs "all" maps to `user_type=1` vs all rows for a `company_id` is an inference, not a confirmed rule; and `{all customer contacts}` returning >1 row depends on reconciling the stale `@unique`. Inclusion of pending/revoked/soft-deleted invited members is unspecified — code keeps revoked but hides soft-deleted for the UI list; the recipient rule may differ. |
| **Why it blocks** | If `user_type` is not the agreed discriminator, resolution is wrong. The stale `@unique` must be formally removed from both schema files or Prisma queries could regress to expecting one row. Whether revoked/pending/soft-deleted members receive the email is a real delivery decision. |
| **Owner** | BA |

> **Question:** Confirm: `{main customer contact}` = `Exhibitor(company_id, user_type=1)` and `{all customer contacts}` = all `Exhibitor` rows for the `company_id`? We must formally drop `@unique` from `Exhibitor.company_id` in both schemas to match the DB — please approve that. And which invited members are included in `{all customer contacts}`: only accepted (invitation_status accepted / status=true), or also pending/revoked, and never soft-deleted (deleted_at)?

---

#### DRR-01 — Placeholder data source: `{salesperson}`

| | |
|---|---|
| **Requirement** | V2 row 20 (`story_sources.txt:456`): `{salesperson}` resolves to the salesperson associated with the trigger event context. |
| **Codebase reality** | The only salesperson linkage carrying an email is `Order.sales_person_id Int?` → `salesPerson User?` (admin `schema.prisma:1615/1634`), and it is **nullable**. There is no `Company.sales_person_id`. `Exhibitor` carries different roles `referred_by` and `strategist_id` → `User` (`schema.prisma:1033-1034/1055-1056`). `User.email` is required-unique (`schema.prisma:12`); `User.phone` optional. |
| **The gap** | "The salesperson associated with the trigger event context" is only defined for order-scoped triggers (via `Order.sales_person_id`). For company/exhibitor-scoped triggers (welcome, forgot-password, contact-us, low-balance) there is no salesperson link at all, and it is unclear whether `strategist_id`/`referred_by` should stand in. |
| **Why it blocks** | The resolver cannot be coded without knowing, per trigger, which column supplies `{salesperson}`. Assuming `Order.sales_person_id` for triggers with no order silently yields no recipient; using `strategist_id` as a fallback could mis-address emails to the wrong internal person. Ties into the fallback rule (DRR-06) because the column is nullable. |
| **Owner** | BA |

> **Question:** For each trigger that exposes `{salesperson}`, which stored field is the authoritative source? Is it strictly `Order.sales_person_id` (order-scoped triggers only), and for triggers with no order do we omit `{salesperson}` entirely, or fall back to `Exhibitor.strategist_id` / `referred_by`? When `Order.sales_person_id` is null, which fallback (DRR-06) applies?

---

#### DRR-04 — Trigger context: which triggers expose these TO options, and whether required ids are present

| | |
|---|---|
| **Requirement** | V2 row 20 (`story_sources.txt:392-393`): resolve tokens based on the trigger event and its associated context data. |
| **Codebase reality** | There is no unified trigger-context object. Context is ad-hoc per call site — worker carries `exhibitorId?` (`mailer.service.ts:36`); order path carries `orderId` and re-loads company/exhibitor (`order-notification.service.ts:165-218`); webhook paths carry order/purchaser; auth/contact-us paths carry only a raw email. `TriggerEvent.available_placeholders` (`schema.prisma:287`) governs body/subject tokens, not recipient tokens, and no seeded trigger lists recipient placeholders (`trigger-event.seeder.ts`). |
| **The gap** | Which specific trigger events may offer `{salesperson}` / `{main customer contact}` / `{all customer contacts}` (and Gmail groups) in the TO field is unspecified, and several existing triggers structurally lack the ids (`order_id`, `company_id`) needed to resolve them. |
| **Why it blocks** | Without a per-trigger allow-list, an admin could attach `{salesperson}` to a forgot-password template that has no order/company context, producing an unresolvable recipient at send time. Config-time validation (block the token) vs send-time fallback cannot be designed without the trigger-to-token matrix. |
| **Owner** | BA |

> **Question:** Provide the mapping of which trigger events expose each of the three TO tokens (and Gmail groups). For triggers whose context lacks `order_id`/`company_id`, should the token be un-offerable at config time, or offered and handled by the fallback rule at send time?

---

#### DRR-03 — Internal Gmail groups: literal address vs membership expansion

| | |
|---|---|
| **Requirement** | V2 row 20 (`story_sources.txt:373,397`): system shall allow the admin to add internal Gmail groups as recipients and resolve them to their group recipient addresses at send time; boundary case "internal Gmail group with no members." |
| **Codebase reality** | No group / distribution-list / recipient-list-source concept exists anywhere in schema or code (grep returns nothing relevant). The only multi-recipient precedents are flat `String[]` columns (Product notification arrays) and `CompanyLeadEmail` (PPL-scoped, email-only, `schema.prisma:1123-1136`). No Google Directory/Workspace integration and no SendGrid group concept. |
| **The gap** | The "no members" boundary case implies the system knows a group's membership, but a Google Group address is itself just an email string that Google expands on receipt. It is undefined whether we store the group's literal address (no expansion) or must call an external Google Workspace/Directory API to enumerate members. |
| **Why it blocks** | Two completely different builds: (a) treat as a single literal `to_recipients` string = trivial; (b) expand membership = requires a Google Workspace Admin SDK integration, service-account credentials, and a group model — none exist. The "empty group fallback" AC is only implementable under (b). |
| **Owner** | Client |

> **Question:** Is an "internal Gmail group" just a Google Group email address the admin types in (Google handles delivery/expansion, we store one literal string), or must our system enumerate the group's member addresses at send time (requiring a Google Workspace Directory integration)? If the latter, who provisions those credentials, and how is the "no members" case detected?

---

### Major

---

#### DRR-15 — Field scope: TO-only (V2) vs FROM/CC/BCC (client) for tokens & groups

| | |
|---|---|
| **Requirement** | V2 row 20 scopes dynamic tokens and internal Gmail groups explicitly to the **TO field only** (`story_sources.txt:363, 373, 375`). But the client asked for `{salesperson}` in the **FROM** dropdown (`client_feedback.txt:46`) and in **CC/BCC** (`client_feedback.txt:63`). |
| **Codebase reality** | `EmailChannelConfigDto` exposes `from_address`, `reply_to`, `to_recipients`, `cc_recipients`, `bcc_recipients` (`notification-template.dto.ts:175-228`). `IsEmail` is enforced on `from_address` (`:66`), cc/bcc (`:93`) and `to_recipients` — a token cannot be stored in any of these fields today. The "loosen for DRR" comment (`:172-173`) does not say which fields loosen. `from_address` is additionally constrained to the `AllowedFromDomain` whitelist. |
| **The gap** | V2 restricts dynamic recipients to TO, but the client wanted `{salesperson}` as a FROM and CC/BCC option. Whether the resolver and the write-path `IsEmail` loosening apply to only `to_recipients` or also `from_address`/cc/bcc is undefined — and a `{salesperson}` FROM would additionally have to pass (or bypass) the `AllowedFromDomain` whitelist. |
| **Why it blocks** | Determines which DTO fields get token-aware validation and which the resolver must process. Loosen only TO → the client's FROM/CC/BCC token need is unmet; loosen all four → the FROM-domain whitelist and dedup (DRR-08) interactions must be designed. |
| **Owner** | BA/Client |

> **Question:** Are dynamic tokens and internal Gmail groups allowed only in the TO field (per V2), or also in FROM, CC and BCC (per client feedback)? If a token like `{salesperson}` is allowed in FROM, does its resolved address have to satisfy the `AllowedFromDomain` whitelist?

---

#### DRR-17 — Entry typing in the flat recipient array (group vs token vs literal vs list ref)

| | |
|---|---|
| **Requirement** | V2 row 20 (`story_sources.txt:381-383`): tokens and internal Gmail groups may be added alongside predefined-list recipients and manually entered external emails — four kinds of entry coexist in one field; and empty-group handling requires knowing which entries are groups. |
| **Codebase reality** | `to_recipients` is a flat `string[]` of literal emails (`RecipientList`, `notification-template.dto.ts:81-97`; `EmailChannelConfigDto:175-228`). There is no per-entry type/kind marker. A Google Group address is itself an ordinary email string, so a group entry is indistinguishable from a manually typed external email, and a `{token}` would be distinguishable only by curly-brace convention — nothing formalizes this. |
| **The gap** | The `channel_config` recipient schema cannot distinguish a resolved-token entry, an internal-Gmail-group entry, a predefined-list reference, and a literal external email. Without a typed entry structure (or a strict grammar) the resolver cannot know which entries to resolve, which to expand as a group, or which trigger the "empty group" fallback. |
| **Why it blocks** | Concrete `channel_config` schema-shape decision that must precede coding the resolver's parse step. If entries stay flat strings, group-specific behavior (DRR-03) and per-entry audit outcomes (DRR-10) can't be keyed. Choosing wrong forces a migration of every stored custom template. |
| **Owner** | BA |

> **Question:** How is each recipient entry typed in `channel_config` — do we move to a typed structure (e.g. `{kind: literal|token|gmail_group|list_ref, value}`) or keep a flat `string[]` with a reserved token grammar? How is an internal-Gmail-group entry distinguished from a manually typed external email so empty-group handling and per-entry audit can key off it?

---

#### DRR-06 — Send-time fallback rule for unresolvable recipients

| | |
|---|---|
| **Requirement** | V2 row 20 (`story_sources.txt:409` + Failure Handling/Boundary): fallback "skip, log, or use a default (Subject to R&D)"; dispatch must not fail entirely unless no valid recipient remains; dispatch must not proceed with zero valid recipients. |
| **Codebase reality** | No fallback exists in code — OUTSTANDING_ITEMS §4 (Release #30) records that missing placeholder values currently leave raw tokens in the email with no fallback rule. Recipient resolution does not exist at all today (see DRR-05). |
| **The gap** | The story leaves fallback behavior "Subject to R&D" — skip the recipient, use a default address, or abort. The "default" branch has no defined default address anywhere in code or config. |
| **Why it blocks** | The resolver's error path cannot be coded. Skip silently → order confirmations could go to nobody; use a default → no default address exists; abort → need a defined not-sent audit state. Wrong assumption here directly causes lost or misdirected notifications. |
| **Owner** | BA |

> **Question:** Confirm the fallback for an unresolvable dynamic recipient: skip-and-log, substitute a default address (if so, which one), or abort. And confirm a dispatch resolving to zero valid recipients is aborted (not sent), and how that outcome is surfaced/audited.

---

#### DRR-09 — SMS-channel recipient resolution: is it even in 77.9 scope? (email-only per V2)

| | |
|---|---|
| **Requirement** | V2 row 20 Channel Handling states the system resolves **email** recipients for the email send, with RFC 5322 validation — 77.9 as written is EMAIL-ONLY. Yet 76.8 (`story_sources.txt:32`) says the SMS provider will deliver SMS templates to the resolved recipients "→ Refer DRR", creating a cross-dependency. |
| **Codebase reality** | `SUPPORTED_TEMPLATE_CHANNELS=['EMAIL']` (`notification-template.dto.ts:27`); custom SMS is out of scope (KNOWN_ISSUES #12; create rejects channel=SMS). `channel_config` is email-only. No template stores phone recipients. Phone fields are scattered/nullable: `User.phone?` (`schema.prisma:16`), `Exhibitor.phone` required (`:1029`), `Order.billing_phone?` (`:1594`); there is no `additional_phone` array analogous to `Order.additional_emails` (`:1599`); Product carries the only phone-array precedent (`schema.prisma:1291`). |
| **The gap** | 77.9 (custom, email-only) does not define SMS recipient resolution, but 76.8 delegates SMS recipient resolution to "DRR". Since custom SMS is out of scope, it is unclear whether SMS recipient resolution belongs to 77.9 or to the predefined-SMS/76.8 track — and if so, how the same three tokens map to a mobile number (and what happens when the resolved contact's phone is null while their email exists). |
| **Why it blocks** | The SMS path (76.8) has no recipient supply without a decision. Building email-only DRR now leaves SMS un-addressable; if 76.8 assumes 77.9 provides it, neither will. Wrong assumption (reuse the email `to_recipients` field for phones) breaks SMS entirely. |
| **Owner** | BA |

> **Question:** Is SMS recipient resolution in 77.9's scope, or does it belong to the predefined-SMS / 76.8 track (77.9 being explicitly email-only in V2)? Whichever owns it: how do the three tokens resolve to mobile numbers (which phone field per entity), and what happens when the resolved contact's phone is null while their email is present?

---

#### DRR-07 — Predefined recipient-list sources (admin users / exhibitors / "other relevant system emails")

| | |
|---|---|
| **Requirement** | V2 row 20 (`story_sources.txt:381-383`) allows tokens alongside predefined-list recipients; client-agreed (`client_feedback.txt:98-99`): TO can select from a predefined list including admin users, exhibitors, and other relevant system emails. |
| **Codebase reality** | Known issue #4 catalogued that these lists come from listing endpoints owned by other modules (admin `GET /users`, `/exhibitors`, `/providers`, etc.), but "other relevant system emails" has no observed source endpoint. No recipient-list-source picker endpoint exists in this module. |
| **The gap** | "Other relevant system emails" has no defined backing source, and it is unclear whether the predefined lists are resolved by live queries against those other-module endpoints, a new config table, or a static seed. |
| **Why it blocks** | The resolver cannot enumerate a predefined list with no source. Cross-module endpoint ownership, auth scoping, and "which emails" are undefined, blocking the predefined-list branch of TO/CC/BCC resolution. |
| **Owner** | BA |

> **Question:** What exactly backs "other relevant system emails", and how are the predefined recipient lists (admin users, exhibitors) sourced at resolve time — live queries against the owning modules' listing endpoints, a new managed config table, or a static seed? Who owns/maintains that source?

---

#### DRR-10 — Audit storage for resolution outcomes

| | |
|---|---|
| **Requirement** | V2 row 20 Audit (`story_sources.txt:413` + Design Audit): log recipient resolution outcomes for each dispatch — template id, resolved recipient references, timestamp; retained permanently, not editable/deletable. |
| **Codebase reality** | `NotificationLog` (`schema.prisma:309-335`) stores a single `email String?` (`:312`) plus `user_id`/`exhibitor_id`/`status` — no cc/bcc columns and no resolved-recipient-list / resolution-outcome structure. The worker logs only `options.to[0]` (`mailer.service.ts:129`). `admin-backend-api` owns migrations; the other four use `db push`. |
| **The gap** | There is nowhere to record the resolved recipient set, per-recipient resolution outcome (resolved/skipped/failed), or the group-expansion result. Whether this is a new field-set on `NotificationLog` or a new audit table is undecided. |
| **Why it blocks** | The audit AC cannot be met with the current schema; it requires an admin-migration decision (per-recipient rows vs JSON blob) that the other four repos must then `db push` in sync. Blocks the traceability requirement. |
| **Owner** | BA |

> **Question:** Where should recipient-resolution outcomes be stored — extend `NotificationLog` (add resolved-recipients + per-recipient outcome), or a new dedicated audit table? Should each resolved recipient be its own row, or a JSON blob per dispatch?

---

#### DRR-08 — Cross-field To/CC/BCC de-duplication rule

| | |
|---|---|
| **Requirement** | V2 row 20 Duplicate Handling (`story_sources.txt:476`): duplicate resolved recipients across To/CC/BCC must be de-duplicated per the defined rule (Subject to client confirmation). |
| **Codebase reality** | `dedupeEmails` (`notification-template.service.ts:109-119`) is applied only to cc/bcc within-field on write (`:273-274, :387-389`); `to_recipients` is NOT deduped, and there is no cross-field (To∩CC∩BCC) dedup anywhere. At send time there is no dedup at all because recipients aren't sourced from the template today (see DRR-05). |
| **The gap** | The rule is marked "Subject to client confirmation" — the precedence when an address appears in more than one field (which field keeps it), and whether case/normalization applies to resolved addresses, are undefined. This compounds once dynamic tokens can resolve the same person into multiple fields. |
| **Why it blocks** | Dedup precedence changes recipient behavior (e.g. dropping someone from TO because they resolved into CC). Coding it wrong means duplicate sends or a customer silently demoted to BCC. |
| **Owner** | Client |

> **Question:** Confirm the cross-field dedup rule: when a resolved address appears in more than one of To/CC/BCC, which field wins (To > CC > BCC?), and is matching case-insensitive/normalized? Should `to_recipients` also be deduped within-field (it currently isn't)?

---

### Minor

---

#### DRR-16 — Additional dynamic sources named by client (vendor emails from show details) not in the 3-token list

| | |
|---|---|
| **Requirement** | Client asked for dynamic recipient sources beyond the three V2 tokens: vendor emails pulled dynamically from the email address in show details, and product-specific alerts (`client_feedback.txt:55-60`), plus "100's of form fields we want to pull from" (`client_feedback.txt:69-71`). V2 row 20 formalized only `{salesperson}`, `{main customer contact}`, `{all customer contacts}` + Gmail groups. |
| **Codebase reality** | Show-level operational contacts exist as free-text on the `Shows` model: `venue_manager_emails @db.VarChar(500)` is a single comma-joined string (`schema.prisma:2535`), plus `gsc_decorator_contact_email` (`:2540`) and `elctrician_contact_email` (`:2550`), all `String?` free-text, not arrays and not validated. There is no `{vendor}`/show-details recipient token in the V2 spec or any seeded placeholder. |
| **The gap** | The client's vendor-from-show-details source is named but was not carried into the V2 three-token list. Whether 77.9 must support it (and parse the comma-joined `venue_manager_emails` string into recipients) is unresolved, so the token set the resolver must support may be incomplete. |
| **Why it blocks** | If in scope, the resolver needs an additional token and a parser for the comma-joined `Shows` contact strings; if out of scope, the client's product-alert use case is unmet and may bounce back. Building only the three tokens risks a missed requirement. |
| **Owner** | BA/Client |

> **Question:** Is the client's "vendor emails pulled from show details" a required dynamic recipient source for 77.9 (a fourth token beyond the three), or explicitly deferred/out of scope? If in scope, confirm the source field (`Shows.venue_manager_emails` etc.) and that the comma-joined string is to be split into individual recipients.

---

#### DRR-11 — Resolved-address validation vs current token rejection (two-tier contract)

| | |
|---|---|
| **Requirement** | V2 row 20 Channel Handling: resolved email recipients must be valid email addresses (RFC 5322 compliant). AC also allows tokens alongside manually entered external emails (`story_sources.txt:383`). |
| **Codebase reality** | Recipient arrays accept literal emails only — `RecipientList` validates each entry with `IsEmail` (`notification-template.dto.ts:81-97`), and the DTO comment explicitly says tokens are rejected "until the Dynamic Recipient Resolution phase loosens this validation" (`:172-173`). So `{salesperson}` cannot even be stored today; DRR must loosen write-time validation while still validating the resolved address at send time. |
| **The gap** | The story doesn't specify the two-tier validation contract: which token/group syntaxes are accepted at config time (write) vs how the resolved output is validated at send time, and what happens when a resolved value fails RFC 5322 (e.g. a malformed stored email). |
| **Why it blocks** | Loosening `IsEmail` incorrectly could allow arbitrary free text into recipient arrays. Without the accepted token grammar and the send-time validation-failure behavior, the write-path DTO change and the resolver's validation branch cannot be built correctly. |
| **Owner** | BA |

> **Question:** Define the accepted config-time entry grammar (the exact token/group literals to allow past `IsEmail`) and confirm the send-time behavior when a resolved address is not RFC 5322 valid — treat as an unresolved recipient under the fallback rule (DRR-06)?

---

#### DRR-13 — Interaction with scheduling (deferred track): resolve at fire time, not enqueue

| | |
|---|---|
| **Requirement** | V2 row 20 Resolution Timing (`story_sources.txt:401`): resolve at send time using the most current data, not at the time of template configuration. |
| **Codebase reality** | The designed scheduler dispatches via `MailerService.sendFromTemplate` (OUTSTANDING_ITEMS §6) and is a separate deferred track from DRR. For a scheduled/follow-up send the gap between config time and actual send can be days (`client_feedback.txt:204-208` cites time-delay triggers). |
| **The gap** | For scheduled/follow-up sends, "most current data at send time" means re-resolving at the deferred execution moment (salesperson may have changed, contact removed). Whether the resolver runs at enqueue time or at the scheduled fire time is unspecified, as is who owns wiring DRR into the scheduler's dispatch hook. |
| **Why it blocks** | If resolution runs at enqueue instead of fire time, a scheduled email sent days later goes to stale recipients — violating the AC. The integration point between the two separately-built tracks must be agreed or one will not call the other. |
| **Owner** | BA |

> **Question:** For scheduled/follow-up dispatches, must recipient resolution run at the actual fire time (not at enqueue), and which track owns invoking the DRR resolver from the scheduler's `sendFromTemplate` hook?

---

#### DRR-12 — Privacy / permission of exposing internal groups & customer contacts

| | |
|---|---|
| **Requirement** | V2 row 20 exposes internal Gmail groups and customer-contact addresses as selectable/resolvable recipients; predefined lists include admin users and exhibitors (`client_feedback.txt:98-99`). |
| **Codebase reality** | No consent/opt-in/opt-out or per-recipient permission model anywhere (grep `consent|opt_in|subscribe` returns nothing across all five schemas). Recipient-list source endpoints are owned by other modules with their own auth scoping (known issue #4). No access-control rule ties which admin roles may attach which dynamic recipients. |
| **The gap** | It is unspecified whether any admin may attach an internal Gmail group or resolve `{all customer contacts}` (potentially exposing every exhibitor contact for a company), or whether this is role-gated, and whether exposing internal group membership to non-privileged admins is acceptable. |
| **Why it blocks** | If role restrictions are required they must be enforced in the resolver/config endpoints; retrofitting access control after build is costly. Wrong assumption risks leaking internal group members or customer contact lists to under-privileged admins. |
| **Owner** | Client |

> **Question:** Should attaching internal Gmail groups and the `{main/all customer contacts}` tokens be restricted to specific admin roles/permissions, or available to any admin who can create a custom template? Any privacy constraint on exposing group membership / bulk customer contacts?

---

## Consolidated question checklist

Ready to paste into an email to the BA/client. Each question is tagged with its owner.

1. **[BA] (DRR-05)** At send time, what is the authoritative recipient source — the template's stored `channel_config`, the existing call-site-computed recipients, or a merge? Are predefined templates (no `channel_config`) in scope for DRR, or is DRR custom-email only?
2. **[BA] (DRR-02)** Confirm `{main customer contact}` = `Exhibitor(company_id, user_type=1)` and `{all customer contacts}` = all `Exhibitor` rows for the `company_id`. Approve formally dropping `@unique` from `Exhibitor.company_id` in both schemas to match the DB. Which invited members are included — only accepted, or also pending/revoked, and never soft-deleted?
3. **[BA] (DRR-01)** For each trigger exposing `{salesperson}`, which stored field is authoritative? Is it strictly `Order.sales_person_id` (order-scoped only)? For triggers with no order, omit `{salesperson}` or fall back to `Exhibitor.strategist_id` / `referred_by`? When `Order.sales_person_id` is null, which fallback applies?
4. **[BA] (DRR-04)** Provide the mapping of which trigger events expose each of the three TO tokens (and Gmail groups). For triggers lacking `order_id`/`company_id`, is the token un-offerable at config time, or offered and handled by the send-time fallback?
5. **[Client] (DRR-03)** Is an "internal Gmail group" a single Google Group email address we store literally (Google expands on delivery), or must we enumerate the group's members at send time via a Google Workspace Directory integration? If the latter, who provisions credentials and how is "no members" detected?
6. **[BA/Client] (DRR-15)** Are dynamic tokens and Gmail groups allowed only in TO (per V2), or also in FROM/CC/BCC (per client feedback)? If `{salesperson}` is allowed in FROM, must its resolved address satisfy the `AllowedFromDomain` whitelist?
7. **[BA] (DRR-17)** How is each recipient entry typed in `channel_config` — a typed structure (`{kind, value}`) or a flat `string[]` with a reserved token grammar? How is an internal-Gmail-group entry distinguished from a manually typed external email?
8. **[BA] (DRR-06)** Confirm the fallback for an unresolvable dynamic recipient: skip-and-log, substitute a default (which address?), or abort. Confirm a dispatch resolving to zero valid recipients is aborted, and how that is surfaced/audited.
9. **[BA] (DRR-09)** Is SMS recipient resolution in 77.9's scope or the predefined-SMS / 76.8 track? Whichever owns it: how do the three tokens resolve to mobile numbers (which phone field per entity), and what happens when the resolved contact's phone is null but email exists?
10. **[BA] (DRR-07)** What backs "other relevant system emails", and how are the predefined lists (admin users, exhibitors) sourced at resolve time — live queries against owning modules, a new config table, or a static seed? Who maintains it?
11. **[BA] (DRR-10)** Where are recipient-resolution outcomes stored — extend `NotificationLog` or a new audit table? Per-recipient rows or a JSON blob per dispatch?
12. **[Client] (DRR-08)** Confirm the cross-field dedup rule: which field wins when an address appears in more than one of To/CC/BCC (To > CC > BCC?), is matching case-insensitive/normalized, and should `to_recipients` also be deduped within-field?
13. **[BA/Client] (DRR-16)** Is "vendor emails pulled from show details" a required dynamic source for 77.9 (a fourth token), or deferred/out of scope? If in scope, confirm the source field (`Shows.venue_manager_emails` etc.) and that the comma-joined string is split into individual recipients.
14. **[BA] (DRR-11)** Define the accepted config-time entry grammar (exact token/group literals to allow past `IsEmail`) and confirm send-time behavior when a resolved address is not RFC 5322 valid — treat as unresolved under the fallback rule?
15. **[BA] (DRR-13)** For scheduled/follow-up dispatches, must resolution run at the actual fire time (not enqueue), and which track owns invoking the DRR resolver from the scheduler's `sendFromTemplate` hook?
16. **[Client] (DRR-12)** Should attaching internal Gmail groups and the `{main/all customer contacts}` tokens be restricted to specific admin roles, or available to any admin who can create a custom template? Any privacy constraint on exposing group membership / bulk customer contacts?

## Already settled — not blocking

These were considered during the gap review and dropped as already-answered; recorded here for completeness.

- **DRR-14 — Predefined DRR variant out of scope.** The predefined-DRR variant being out of scope is an existing recorded decision (KNOWN_ISSUES #3), not an open implementation blocker. It is a documentation-hygiene item (confirm the BA edited the predefined epic), and its one open thread — whether predefined templates are in DRR scope — is folded into DRR-05's "is DRR custom-only?" confirmation.

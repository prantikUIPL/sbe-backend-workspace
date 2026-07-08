# Email & SMS — Refined User Story: 77.9 Dynamic Recipient Resolution Engine (DRR)

**Module:** Email & SMS Management → Custom Email Management (Epic 77, admin)
**Supersedes:** the "Dynamic Recipient Resolution Engine" story in `Email & SMS Management V2.xlsx` — specifically the **custom-email variant** (V2 dump line 2572; carried verbatim into Confluence as 77.9). The **predefined-module DRR variant** that also appears in V2 (line 1089) is **retired** — out of scope per `EMAIL_SMS_KNOWN_ISSUES.md` #3 and gap-analysis item DRR-14 (settled); its one residual thread (are predefined templates in DRR scope at all?) is folded into DRR-05 here. Both V2 variants remain on disk as the historical baseline.
**Date:** 2026-07-08
**Audience:** Product / BA / Sprint planning
**Release framing:** one of the **7 combined-release documents**. Scheduling (76.6/77.8), DRR (77.9) and SMS (76.8) ship **together** on a shared spine: **one recipient-resolution engine** (this story), **one unified `NotificationLog` migration** (channel + generalized recipient), and the **D1 per-rule resolve-timing toggle** (default = snapshot-at-materialize). DRR is the middle of the dependency chain: the shipped scheduler gates token-recipient sends behind a SKIP → this engine un-gates them → SMS (76.8) reuses this same engine extended to a phone field.
**Primary source material:** live Confluence 77.9 (= V2 row 20 custom variant, verbatim); `EMAIL_SMS_77.9_DYNAMIC_RECIPIENT_RESOLUTION_GAP_ANALYSIS.md` (2026-07-06 — the authoritative open-question register, IDs DRR-01…DRR-17); external validation report 2026-07-07 (findings D1/D2/D3 as they touch DRR); `SBE_client_feedback_email_sms.pdf` (May 2026 client thread).
**Companion documents:** `email_sms_scheduling_plan_and_supporting_docs/EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` (approved, READ-ONLY — the scheduler this engine generalizes) and `EMAIL_SMS_SCHEDULING_STORY.md` (the refined-story precedent this document mirrors); the sibling combined-release stories for 76.6/77.8 and 76.8.

> **Requirement labels used throughout:**
> **CONFIRMED** — stated in an authoritative source (cited). **PROPOSED** — our recommended default, awaiting sign-off on the named question ID; the acceptance criteria in §7 cover every PROPOSED default, so signing off this story signs off the defaults. **OPEN** — a pure question with no default we are willing to assume.

---

## 1. User story

> *As an Admin composing a custom email template, I want to place dynamic recipient tokens — `{salesperson}`, `{main customer contact}`, `{all customer contacts}` — and internal Gmail groups into the TO field alongside predefined-list recipients and manually entered external emails, and have the system resolve them to concrete, valid addresses when the email is dispatched, so that trigger-driven emails always reach the right people without me hard-coding addresses per template.*

(Framing carried verbatim in intent from Confluence 77.9 / V2 row 20 custom variant.)

---

## 2. Why this refinement exists

The V2/Confluence story text is a correct *statement of intent* but is unbuildable as written, for five reasons:

1. **Every token is semantically unmapped.** "The salesperson associated with the trigger event context" names no table or column; the only salesperson linkage **usable from a trigger/order context** is nullable `Order.sales_person_id` (admin `prisma/schema.prisma:1615/1634`) and it exists **only for order-scoped triggers** (gap DRR-01). (The schema's one other salesperson→User relation, `AffiliateClick.salesperson_id` — admin `schema.prisma:69/:75` — is per-click affiliate analytics, not an order/company association, and is irrelevant to recipient resolution.) "Main" vs "all" customer contacts is likewise an inference from `Exhibitor.user_type` — and `{all customer contacts}` returning more than one row collides with a **schema/DB drift**: `Exhibitor.company_id` is declared `@unique` in all five schemas (`schema.prisma:1030`) while the real DB has only a non-unique index (init migration `20260303120000_init:241`) and the invite flow deliberately creates multiple rows per company (gap DRR-02 / validation-report D2).
2. **The consumption point does not exist.** No live send path reads `channel_config` today — all four mailers take caller-supplied recipients and live triggers compute recipients in code (`order-notification.service.ts:99-218`; grep evidence in the gap analysis). "Resolve the TO field at send time" therefore first requires **building the very code path that honors template-configured recipients** (gap DRR-05).
3. **Three clauses are marked "Subject to R&D" / "Subject to client confirmation"** — the unresolvable-recipient fallback, the zero-recipient boundary, and the cross-field dedup rule — i.e. the story's own error paths are undecided (gaps DRR-06/DRR-08; adjudicated in part by validation-report D3).
4. **The resolve-timing clause conflicts with the approved scheduling plan.** 77.9 says "most current data at send time, never config-time values"; the approved scheduler resolves at **materialize time** and *replays the snapshot verbatim, never re-resolving* (scheduling plan §2.2, §4 item 8). The external review adjudicated this as **D1 (HIGH)**: a per-rule toggle, default snapshot (gap DRR-13 → D1; see §5.4).
5. **Recorded client feedback contradicts the V2 scope** — the client asked for `{salesperson}` in FROM and CC/BCC and for vendor emails pulled from show details; V2 narrowed to TO-only and three tokens (gaps DRR-15/DRR-16; see §2.1).

This document re-derives 77.9 as the specification of the **one shared recipient-resolution engine** of the combined release, with every unmapped clause either pinned to real tables/columns (PROPOSED defaults) or carried as an explicit open question under its original stable ID.

### 2.1 Version drift — what wins, and why

| Dimension | V1 ("Recipient Configuration") | Updated Epic 77.9 row | **V2 custom variant = live Confluence (WINS)** | V2 predefined variant (RETIRED) | Client feedback (May 2026 thread) |
|---|---|---|---|---|---|
| Field scope for dynamic entries | All four fields (FROM w/ Reply-To, TO, CC, BCC) | TO only | **TO only** | To/CC/BCC compiled | `{salesperson}` asked for in **FROM** and **CC/BCC** |
| Token set | `{client_email_address}`, `{salesperson_email_address}`, `{additional_client_email_address}`, `{all_speaker_email_addresses}` (+ SMS phone tokens) | the three plain-English tokens | **three tokens + internal Gmail groups** | generic roles, no literals | old vocabulary (`{client_email_address}`, `{salesperson_email_address}`) + vendor-from-show-details |
| Channel | Email **and** SMS | unstated | **Email-only** | Email and SMS | (email thread) |
| Resolution timing | "at template execution" | unstated | **send time, most current data** | same | time-delay triggers are the norm (Theo, 20-May) |
| Show-detail vendor source | explicit | absent | **dropped** | absent | explicitly requested |

**Reconciliation rule adopted by this story:** the **V2 custom variant (= live Confluence) is the baseline** — it is the newest authored spec and the one the client-facing page carries. Where the client's *recorded written feedback* contradicts it (FROM/CC/BCC tokens → **DRR-15**; vendor-from-show-details source → **DRR-16**), the conflict is **carried as an open question, never silently resolved in either direction** — narrowing was a spec decision that contradicts recorded client asks, so only the client can settle it. The retired predefined variant contributes nothing except the residual DRR-05 scope question. V1's old token vocabulary is historical; `{all_speaker_email_addresses}` survives only as the scheduling plan's token-SKIP example and is **not** in this story's token set. Note the client never saw the literals `{main customer contact}` / `{all customer contacts}` in the thread — they first appear in the Updated Epic — so token *naming* sign-off is implicitly part of DRR-04/DRR-15 sessions.

### 2.2 Where this story sits in the combined release (the shared spine)

- **One resolver (never two).** The approved scheduling plan already ships a **restricted** resolver: `notification_schedules.recipient_source` (bare anchor column or one documented relation hop, per-anchor allow-list) + `replacements_map` (bare column or fixed `FULL_NAME`/`DATE_FMT` transforms), validated at config **and** materialize time, no expression DSL, no eval (plan §2.1, §4 items 3/7/12). **DRR is the generalization of exactly that resolver** — it extends the allow-list with token specs; the scheduler's materializer/dispatcher becomes a *consumer* of the shared engine, and the existing bare-column/one-hop/transform forms remain valid inputs (the degenerate, no-token tier — not a separate code path). Standing up a parallel resolver violates the release constraint (validation report M4; gap analysis "extend the allow-list, not stand up a parallel mechanism").
- **One unified `NotificationLog` migration.** `NotificationLog` today stores a single `email String?` (`schema.prisma:312`) and the worker logs only `to[0]` (`worker mailer.service.ts:129`). DRR's per-dispatch resolution audit (DRR-10) and SMS's channel/phone destination (M3) land in **one** admin-owned migration adding `channel` + a generalized recipient representation, `db push`-mirrored to the other four repos — neither track writes its own (validation report M3).
- **D1 resolve-timing toggle.** DRR owns the `resolve_at_send` per-rule column, the reference-shaped occurrence storage variant, and the dispatch-time resolution hook the scheduler calls (§5.4).
- **Sequencing.** Email DRR ships first; SMS (76.8) reuses the engine extended to a phone field (M4) — this breaks the DRR↔SMS circular reference (76.8 says "refer DRR"; 77.9 as written is email-only → DRR-09). The SMS track's Twilio/A2P 10DLC registration long pole (provider mechanism itself pending client confirmation, **SMS-01** — client said "SendGrid" but SendGrid's API is email-only) starts day one in parallel; DRR slipping strands SMS, so DRR is schedule-critical even though it needs no provider.

---

## 3. The refined resolution model

### 3.1 What the engine is

A single backend service — the **recipient-resolution engine** — that, given (a) a template's recipient configuration and (b) a trigger/anchor context (order id, company id, anchor row…), produces the final compiled `{to[], cc[], bcc[]}` plus a per-entry resolution outcome record. It runs:

- **inline at send time** for live-trigger sends (CONFIRMED — Confluence 77.9 Design Spec: identify placeholders/groups/static entries → resolve via trigger-event context → compile final list → pass to email service);
- **at materialize time** for scheduled sends by default, snapshotting into `occurrence.recipients_snapshot` (CONFIRMED — scheduling plan §2.2/§4 item 8, adopted via D1);
- **at dispatch time** for scheduled rules that opt into `resolve_at_send` (PROPOSED default mechanics per D1 — see §5.4).

**Engine home (PROPOSED, follows existing layering — no new question):** the resolution core lives in **`background-worker-service/src/notification/`**, where the scheduler's restricted resolver already lands and where the only multi-recipient send path exists; **config-time validation** (token grammar, trigger-token matrix) lives beside the existing validators in **`admin-backend-api/src/admin/notification-template/`** (the `assertPlaceholdersAllowed` pattern, `notification-template.service.ts:572-592`), since admin owns template CRUD. Cross-repo house rule applies: same repo → hoist; cross-repo → implement natively to identical semantics (no shared npm package exists; the four mailers are deliberate mirrors).

### 3.2 Per-token resolution semantics

| Entry | Resolution rule | Status |
|---|---|---|
| `{salesperson}` | `Order.sales_person_id` (nullable Int, admin `schema.prisma:1615`) → `User.email` (required-unique, `schema.prisma:12`). **Defined only for order-scoped triggers.** Token is *un-offerable* at config time on triggers without an order context; when the column is null at resolve time, the DRR-06/D3 fallback applies (skip-and-log for marketing, abort-and-alert for transactional). `Exhibitor.strategist_id`/`referred_by` are **different roles** (sales strategist / PPL referrer, `schema.prisma:1033-1034/1055-1056`) and are **not** used as stand-ins unless the BA explicitly directs. | **PROPOSED — DRR-01** |
| `{main customer contact}` | `Exhibitor` row with `(company_id = ctx.company_id, user_type = 1, deleted_at: null)` → `Exhibitor.email` (required-unique, `schema.prisma:1023-1061`; `user_type` SmallInt: 1 = primary account holder, 2 = invited member — `exhibitor-backend-api/src/company_user/company_user.service.ts:105-111`). This is the codebase's own established "main contact" precedent: `order-notification.service.ts:196-199` uses exactly this lookup as the D3 recipient-chain fallback. | **PROPOSED — DRR-02** |
| `{all customer contacts}` | All `Exhibitor` rows for the `company_id` with `deleted_at: null` **and** membership in good standing: `user_type = 1`, plus `user_type = 2` rows whose `invitation_status` is accepted. **Excluded by default: pending, revoked, soft-deleted** (the UI list keeps revoked rows visible but that is a display rule, not a delivery rule). Boundary (CONFIRMED — Confluence 77.9): 1 contact → send to that one; many → send to all. **Hard prerequisite:** formally drop `@unique` from `Exhibitor.company_id` in **all five** schema files + replace with the plain index the DB actually has (admin migration, others `db push`) — see §5.3. | **PROPOSED — DRR-02 (membership filter) / D2 (the `@unique` drop, Engineering)** |
| Internal Gmail group | **Literal-address model (recommended default):** the admin selects/enters the group's Google Group email address; we store one literal address entry typed `gmail_group`; Google expands membership on receipt. No Google Workspace Directory integration, no group model, no credentials. **Consequence honestly stated:** the story's "group with no members" boundary case is *undetectable* under this model and is re-scoped to "group address bounces are handled by normal send-failure logging". The membership-expansion alternative (Workspace Admin SDK + service account + group mirror) is a materially larger build and is adopted **only** if the client confirms it. | **PROPOSED — DRR-03 (owner: Client)** |
| Predefined-list recipients | "Admin users, exhibitors, and other relevant system emails" (CONFIRMED as a list — client-accepted, Amrin 18-May, `pdf_client_feedback.txt:101-104`). Source mechanism **OPEN**: admin-user/exhibitor lists plausibly come from the owning modules' listing endpoints; **"other relevant system emails" has no observed backing source anywhere**. | **OPEN — DRR-07** |
| Manually entered external emails | Allowed in TO and CC/BCC with strict RFC 5322 validation. Client-committed (Zach 18-May / Amrin 20-May, `pdf_client_feedback.txt:187-194`). Current `IsEmail` validation already covers the literal-entry case. | **CONFIRMED** |

**Field scope:** per the winning V2/Confluence text, tokens and Gmail groups are **TO-field only** (CONFIRMED as the baseline). The client's recorded ask for `{salesperson}` in FROM and CC/BCC is carried as **DRR-15** (OPEN — BA/Client): if CC/BCC tokens are confirmed, the same engine processes them (no new machinery); a token in **FROM** additionally collides with the `AllowedFromDomain` whitelist (`notification-template.service.ts:599-610`) and is **recommended against** unless the client insists and accepts whitelist enforcement on the resolved address.

### 3.3 Entry typing in `channel_config` (the parse step)

Today `to_recipients` is a flat `string[]` of `IsEmail`-validated literals (`notification-template.dto.ts:81-97`); a Google Group address is indistinguishable from a manually typed external email, and tokens cannot be stored at all (the DTO comment defers loosening "until the Dynamic Recipient Resolution phase", `notification-template.dto.ts:172-174`).

**PROPOSED — DRR-17:** move recipient entries to a **typed structure**: `{ kind: 'literal' | 'token' | 'gmail_group' | 'list_ref', value: string }`, with a write-time migration/normalization for existing stored custom templates (all existing entries become `kind:'literal'`). Rationale: group-specific behavior (DRR-03), per-entry audit outcomes (DRR-10), and the trigger-token matrix (DRR-04) all need to key off the entry kind; a curly-brace string convention formalizes nothing and makes external-email vs group ambiguity permanent. Choosing flat-strings now forces a migration of every stored custom template later.

### 3.4 Which triggers expose which tokens (the trigger-token matrix)

There is no unified trigger-context object today — context is ad-hoc per call site (order path carries `orderId`; worker carries `exhibitorId?`; auth/contact-us carry only a raw email), and no seeded trigger lists any recipient placeholder (`trigger-event.seeder.ts` — zero `salesperson` hits).

**PROPOSED — DRR-04:** extend the code-controlled trigger catalog (`TriggerEvent`, which already carries `available_placeholders Json?` for body/subject tokens) with an **`available_recipient_tokens`** allow-list per trigger, seeded by code, no admin CRUD — mirroring exactly how body placeholders are governed. Rules:

- a token is **offerable at config time only** on triggers whose context structurally carries the ids it needs (`{salesperson}` → triggers with `order_id`; `{main/all customer contacts}` → triggers with `company_id`);
- config-time validation **rejects** a token not in the trigger's list (new validator beside `assertPlaceholdersAllowed` — the same extension point the scheduling plan names);
- send-time resolution failure on an *offered* token falls to DRR-06/D3 — config-time gating prevents the structurally-impossible case, the fallback handles the data-is-null case. (This is the "un-offerable at config time" branch of the DRR-04 question, recommended because it prevents an admin attaching `{salesperson}` to forgot-password.)

The concrete per-trigger matrix (which of the ~40 triggers get which tokens) is **OPEN — DRR-04 (BA)** and must be delivered as a table in the BA session; the mechanism above is what the story signs off.

### 3.5 Source of truth at send time

**The scheduled path is settled (CONFIRMED):** the scheduling build introduces the first consumer of template recipient config — by-id `sendFromTemplate(notificationTemplateId)` replaying `recipients_snapshot` (plan §4 item 9). DRR feeds that snapshot at materialize (or resolves at dispatch under `resolve_at_send`).

**The live-trigger path is the open half (OPEN — DRR-05):** today stored `channel_config` is written-but-never-read; every live trigger computes recipients in code. The story's engine presumes stored template recipients drive dispatch. **PROPOSED default pending DRR-05:** for **custom** templates, stored `channel_config` (parsed through the engine) becomes the authoritative recipient source at send time; **predefined** templates (which store no `channel_config` — the seeder seeds none) stay on call-site-computed recipients and are **out of DRR scope** (consistent with the retired predefined variant / KNOWN_ISSUES #3). Whether any merge semantics (call-site + template) exist is explicitly **rejected** in the proposal — merge is the double-send/dropped-recipient risk the gap analysis warns about. BA must confirm.

### 3.6 Resolve timing (D1 — the toggle, not a rewrite)

The 77.9 clause "resolve at send time using the most current data, never config-time values" is satisfied as follows:

- **Live-trigger sends:** resolved inline at send — trivially "most current" (CONFIRMED, no conflict).
- **Scheduled/follow-up sends:** the approved scheduler snapshots at materialize/capture and replays verbatim. Per the external review's **D1 (HIGH)** adjudication of DRR-13, this stands as the **default**, and freshness becomes a **per-rule product option**: an optional `resolve_at_send: boolean` on `notification_schedules`; when true, the occurrence stores a **reference** (anchor id + token spec) instead of a resolved snapshot, and the engine resolves at dispatch. The path is **unavailable until DRR ships** (config-time rejection until then), and is **mutually exclusive** with timezone-accurate/snapshot semantics (the Klaviyo precedent the review cites). The scheduler's dispatcher grows exactly one branch: `if (rule.resolve_at_send) → call engine at dispatch; else → replay snapshot`. **PROPOSED — D1** (externally adjudicated recommendation, adopted as a release constraint; formal BA sign-off = "both, selectable"). DRR-13 is thereby carried as *adjudicated-pending-sign-off*, not silently closed.

### 3.7 Fallback, zero recipients, dedup

- **Unresolvable recipient (PROPOSED — DRR-06, informed by D3):** per-entry **skip-and-log** — the entry is recorded as unresolved with a reason; dispatch continues with the remaining valid recipients (matches Confluence "must not fail the entire dispatch unless no valid recipient remains", and matches the scheduler's null-source → SKIPPED precedent). The "substitute a default address" branch is **rejected** — no default address exists anywhere in code or config, and inventing one risks misdirected mail.
- **Zero valid recipients (PROPOSED — D3, refining DRR-06):** **never send to zero.** Trigger classification decides the failure mode: **marketing/reminder triggers → skip-and-log** (occurrence/dispatch marked skipped with reason, visible in audit); **transactional triggers → abort-and-alert** (dispatch marked failed + surfaced through the alerting channel the scheduling track's S3 finding establishes — a transactional send silently skipping is the harm D3 exists to prevent). The transactional-vs-marketing classification is carried on the code-controlled trigger catalog (same place as §3.4's matrix).
- **Resolved-but-invalid address (PROPOSED — DRR-11):** a resolved value failing RFC 5322 is treated as an **unresolved** entry under the fallback above. The config-time grammar that loosens `IsEmail` admits exactly: the three token literals, `gmail_group`/`list_ref` typed entries, and RFC 5322 literals — nothing else (no free text).
- **Cross-field dedup (PROPOSED — DRR-08, owner: Client):** after resolution, when an address appears in more than one field, **TO > CC > BCC** (the address keeps its highest placement; lower placements drop it); matching is **case-insensitive on the full address** (consistent with the existing `dedupeEmails` normalization, `notification-template.service.ts:109-119`); `to_recipients` also gains within-field dedup (it currently has none). Admin's low-level `sendMail()` already cross-field-dedupes (`mailer.service.ts:85-144`) — the engine's rule must match it, not fork it.

### 3.8 Audit

- **CONFIRMED (Confluence 77.9 Audit):** every dispatch logs recipient-resolution outcomes — template identifier, resolved recipient references, timestamp; retained permanently, not editable/deletable.
- **PROPOSED — DRR-10:** outcomes live on **`NotificationLog`** via the **one unified migration** (shared with SMS's M3 `channel` column): a generalized recipient representation — per-dispatch JSON of `{entry (as configured), kind, resolved[], outcome: resolved|skipped|failed, reason?}` per field — alongside the new `channel` discriminator. No new audit table (NotificationLog is already the named permanent audit surface and the scheduler's S1 archive target). PK stays as-is (`NotificationLog.id` BigInt is the pre-existing approved exception; no new BigInt PKs are introduced anywhere in this story — Int PKs per schema preference).
- **PROPOSED — DRR-S2 (new question raised by this story):** the unified migration must state what happens to the existing single `email String?` column — recommended: **kept unchanged, still populated with the first TO recipient**, because the payment-reminder dedupe query filters on `email` + template slug + sent-at window (`payment-reminder.service.ts:225-233`) and must not silently break. Dropping or nulling the column is a regression until that query is migrated.

---

## 4. Navigation & UX (template editor)

All UX lands inside the existing Template Edit / Detail screens (no new screen — same placement rule as the scheduling story §5).

- **TO field** becomes a chip-style multi-entry control: each chip is one typed entry (§3.3) — token chips (picked from a dropdown listing only the tokens the template's trigger exposes, per §3.4), Gmail-group chips, predefined-list picks, and free-typed external emails (validated RFC 5322 on entry). CC/BCC keep literal + (if DRR-15 confirms) the same token affordance.
- **Config-time validation** is immediate: a token not exposed by the trigger is not offered; free text failing the grammar is rejected inline (the loosened-`IsEmail` contract, §3.7/DRR-11).
- **Preview ("who will this go to?"):** the editor offers a resolution preview that runs the real engine read-only against a sample context and shows the compiled To/CC/BCC with per-entry outcomes (resolved address / would-skip reason). **PROPOSED — DRR-S1 (new question raised by this story):** how the sample context is chosen — recommended: the admin picks a recent real record of the trigger's anchor type (e.g. an order) from a search field; the preview is subject to the same permission gate as template edit and shows resolved addresses only to admins who could see them in the source modules anyway (interacts with DRR-12).
- **Detail View** shows the recipient configuration read-only, tokens rendered as labeled chips (mirrors the scheduling story's AC-5 pattern).
- **Permissions (PROPOSED — DRR-12, owner: Client):** default = any admin holding the existing notification-template edit permission may attach tokens/groups; **no additional role gate** unless the client requires one. The privacy question (exposing `{all customer contacts}` bulk resolution / group membership) is carried OPEN under DRR-12 — if the client requires gating, it is enforced in the config endpoints and the preview.

---

## 5. Functional requirements

| # | Requirement | Label / hangs on |
|---|---|---|
| **FR-1** | The TO field of a custom email template accepts internal Gmail groups as recipient entries. | CONFIRMED (Confluence 77.9 System Spec; V2 line 2581) |
| **FR-2** | The TO field offers the dynamic tokens `{salesperson}`, `{main customer contact}`, `{all customer contacts}`. | CONFIRMED (Confluence 77.9; V2 lines 2584-2588) |
| **FR-3** | Tokens and groups are combinable in one field with predefined-list recipients and manually entered external emails. | CONFIRMED (Confluence 77.9 AC) |
| **FR-4** | Dynamic entries are scoped to the TO field in this story; CC/BCC (and the rejected-by-default FROM) extension is a client decision. | CONFIRMED baseline (V2) / **OPEN — DRR-15** for the extension |
| **FR-5** | Recipient entries are stored as typed structures `{kind: literal\|token\|gmail_group\|list_ref, value}`; existing stored entries normalize to `literal`. | **PROPOSED — DRR-17** |
| **FR-6** | `{salesperson}` resolves via `Order.sales_person_id → User.email`; the token is offerable only on order-context triggers; strategist/referrer fields are not stand-ins. | **PROPOSED — DRR-01** |
| **FR-7** | `{main customer contact}` resolves to `Exhibitor(company_id, user_type=1, deleted_at:null).email`. | **PROPOSED — DRR-02** |
| **FR-8** | `{all customer contacts}` resolves to all non-deleted, accepted-membership `Exhibitor` rows for the `company_id`; one contact → that one, many → all. Prerequisite: the `Exhibitor.company_id` `@unique` drop (§6.3). | **PROPOSED — DRR-02 / D2**; boundary CONFIRMED |
| **FR-9** | An internal Gmail group is stored as one literal group address (`kind: gmail_group`); Google expands on receipt; the empty-group boundary re-scopes to bounce handling. | **PROPOSED — DRR-03** (Client) |
| **FR-10** | Predefined-list recipients (admin users, exhibitors, "other relevant system emails") are selectable in TO; their backing sources must be named. | List CONFIRMED (client-accepted) / source **OPEN — DRR-07** |
| **FR-11** | Live-trigger sends resolve inline at dispatch, always using current data. | CONFIRMED (Confluence 77.9 Resolution Timing) |
| **FR-12** | Scheduled sends default to snapshot-at-materialize; a per-rule `resolve_at_send` toggle stores a reference and resolves at dispatch; toggle unavailable until DRR ships; mutually exclusive with snapshot/tz-accurate semantics. | **PROPOSED — D1** (adjudicates DRR-13) |
| **FR-13** | For custom templates, stored `channel_config` (via the engine) is the authoritative recipient source at send; predefined templates stay call-site-resolved and out of DRR scope; no merge semantics. | **PROPOSED — DRR-05** |
| **FR-14** | Two-tier validation: config-time grammar admits only the three tokens, typed group/list entries, and RFC 5322 literals; send-time output is RFC 5322-validated; a resolved-but-invalid address is treated as unresolved. | RFC 5322 CONFIRMED / grammar + failure mapping **PROPOSED — DRR-11** |
| **FR-15** | Unresolvable entry → per-entry skip-and-log; dispatch continues with remaining valid recipients; no default-address substitution. | **PROPOSED — DRR-06** |
| **FR-16** | Zero valid recipients → never send: marketing/reminder triggers skip-and-log; transactional triggers abort-and-alert. Classification lives on the trigger catalog. | never-send-to-zero CONFIRMED / split **PROPOSED — D3** |
| **FR-17** | Cross-field dedup after resolution: TO > CC > BCC precedence, case-insensitive; `to_recipients` also deduped within-field. | dedup-required CONFIRMED / rule **PROPOSED — DRR-08** (Client) |
| **FR-18** | Per-dispatch resolution outcomes are logged permanently and immutably on `NotificationLog` via the one unified combined-release migration (channel + generalized recipient); the legacy `email` column stays populated (first TO) to protect the payment-reminder dedupe query. | audit CONFIRMED / storage **PROPOSED — DRR-10**, legacy-column **PROPOSED — DRR-S2** |
| **FR-19** | The trigger catalog gains a code-controlled `available_recipient_tokens` allow-list; config-time validation rejects tokens the trigger does not expose; the concrete per-trigger matrix is a BA deliverable. | mechanism **PROPOSED — DRR-04** / matrix **OPEN — DRR-04** |
| **FR-20** | The engine is the single shared resolver: it subsumes the scheduler's restricted `recipient_source`/`replacements_map` forms as its degenerate tier, preserves both validation points (config + materialize/dispatch), and the scheduler consumes it. Shipping it un-gates the scheduler's token-recipient occurrences (SKIP reason `"recipient requires DRR (#3)"`). | CONFIRMED (release constraint; scheduling plan §4 item 7/§9; validation report M4) |
| **FR-21** | The engine's resolution interface is designed phone-extensible (a destination-field parameter, not email-hardcoded) so 76.8 extends it rather than forking; SMS recipient resolution itself is **not** in 77.9 scope. | sequencing CONFIRMED (M4) / SMS ownership **OPEN — DRR-09** (with SMS-01 on the provider) |
| **FR-22** | Template-editor preview resolves the configured recipients read-only against an admin-chosen sample context and displays per-entry outcomes. | **PROPOSED — DRR-S1** |
| **FR-23** | Tokens/groups attachment is gated by the existing template-edit permission; no extra role gate by default. | **PROPOSED — DRR-12** (Client) |
| **FR-24** | The client-requested vendor-from-show-details source (`Shows.venue_manager_emails` comma-joined VarChar(500) `schema.prisma:2535`, `gsc_decorator_contact_email :2540`, `elctrician_contact_email :2550`) is **not** in the three-token set; whether it becomes a fourth source or is formally deferred is a client decision. | **OPEN — DRR-16** |

---

## 6. System specification

### 6.1 Engine placement & layering
Resolution core in `background-worker-service/src/notification/` (beside the scheduler's materializer/dispatcher and the only `string[]`-recipient mailer); config-time validators in `admin-backend-api/src/admin/notification-template/` beside `assertPlaceholdersAllowed` (`notification-template.service.ts:572-592`). Where admin-triggered live sends need inline resolution, admin implements natively to identical semantics (house rule; no shared package exists). exhibitor/external send sites stay out of DRR scope under FR-13's proposal (their sends are single-address, caller-resolved, predefined-slug flows).

### 6.2 Schema & migration surface (admin owns migrations; others `db push`)
1. **Unified `NotificationLog` migration (shared with SMS/M3 — the ONE migration):** add `channel` discriminator + generalized recipient/outcome JSON (FR-18); the legacy `email` column is kept unchanged, still populated with the first TO recipient (DRR-S2). Int PKs for anything new; NOT NULL + backfill preferred over nullable.
2. **`notification_schedules.resolve_at_send Boolean @default(false)` NOT NULL** (D1) + the reference-shaped variant of `recipients_snapshot` (or sibling `recipient_ref` slot) on occurrences.
3. **`Exhibitor.company_id` `@unique` drop** — see §6.3.
4. **`TriggerEvent.available_recipient_tokens`** (code-seeded, no admin CRUD) + transactional/marketing classification flag (FR-16/FR-19).
5. **`channel_config` typed-entry shape** (DRR-17) + write-time normalization of existing rows.

No new group/consent tables under the literal-address Gmail model (DRR-03 default).

### 6.3 The `company_id @unique` drift fix (D2 — decoupled, do soon)
Declared `@unique` in all five schemas (admin/exhibitor/external `schema.prisma:1030`; worker/pulse `:944`) but no migration ever created the unique index — init created plain `idx_exhibitors_company_id` (`20260303120000_init/migration.sql:241`) and the invite flow creates multiple rows per company (`company_user.service.ts:237-248`). Fix: drop `@unique` in **all five** schema files, replace with `@@index`, remove/adjust the Prisma one-to-one back-relation `Company.exhibitor` (which silently returns an arbitrary row today — `payment-reminder.service.ts:63` depends on it). This is a **standalone data-integrity fix decoupled from DRR timing** (validation report D2), but `{all customer contacts}` returning >1 row hard-requires it, so it must land **before or with** DRR.

### 6.4 Failure/outcome vocabulary
The engine joins the scheduler's existing SKIP-reason vocabulary (missed-window, template-inactive, superseded, S6 tz fail-closed) rather than inventing a parallel one; it adds the DRR reasons (`unresolved token`, `invalid resolved address`, `zero recipients — skipped (marketing)`, `zero recipients — aborted (transactional)`) and standardizes the currently-unquoted null-recipient-source string. Alerting for the transactional abort rides the S3 alert channel. Snapshot/reference PII on occurrence rows remains bounded by the S1 retention purge (archive-to-NotificationLog first) — the engine must not assume snapshots persist.

### 6.5 Known-issue #21 interaction
All four mailers still resolve templates by slug `findFirst` without `is_predefined` filtering (the custom-shadows-predefined defect); scheduled dispatch is immune by-id. DRR live sends for custom templates must ride the **by-id** path or land after the #21 slug-path fix (shipping with the scheduling build) — a DRR live send resolving the wrong template would resolve the wrong recipient config.

---

## 7. Acceptance criteria

Grouped; every PROPOSED default above is covered by at least one AC, so story sign-off = defaults sign-off.

### 7.1 Configuration & validation
- **AC-1** Given a custom email template on a trigger exposing all three tokens, when the admin adds `{salesperson}`, `{main customer contact}`, `{all customer contacts}`, a Gmail group address, a predefined-list pick, and a typed external email to TO, then the template saves and each entry persists with its typed kind (FR-1/2/3/5).
- **AC-2** Given a trigger whose context lacks `order_id`, when the admin edits a template on it, then `{salesperson}` is not offered and a raw-typed `{salesperson}` is rejected at save with a validation error naming the trigger (FR-6/FR-19).
- **AC-3** Given any recipient field, when the admin enters free text that is neither a permitted token nor RFC 5322 valid, then save is rejected (FR-14).
- **AC-4** Given a predefined (seeded) template, when its edit screen loads, then no dynamic-token affordance is offered (predefined stays out of DRR scope, FR-13).

### 7.2 Resolution at send (live triggers)
- **AC-5** Given an order-scoped trigger fires for an order with `sales_person_id` set, when the custom template containing `{salesperson}` dispatches, then the send goes to that `User.email` and the audit records the token → address outcome (FR-6/FR-18).
- **AC-6** Given the same template and an order whose `sales_person_id` is null on a **marketing/reminder** trigger, when dispatch runs, then the token is skipped-and-logged and the send proceeds to the remaining valid recipients (FR-15).
- **AC-7** Given a trigger with `company_id` context, when `{main customer contact}` resolves, then exactly the `user_type=1`, non-deleted Exhibitor's email is used; and when `{all customer contacts}` resolves for a company with one primary + two accepted invited members + one revoked + one soft-deleted, then exactly **three** addresses are produced (FR-7/FR-8).
- **AC-8** Given a template whose only TO entry resolves to zero valid addresses, then **no email is sent** in any case; on a marketing trigger the dispatch is recorded skipped with reason; on a **transactional** trigger it is recorded failed **and an alert is raised** (FR-16).
- **AC-9** Given a resolved value that is not RFC 5322 valid (e.g. malformed stored email), then it is treated as an unresolved entry under AC-6/AC-8 semantics, never handed to the provider (FR-14).
- **AC-10** Given the same address resolves into TO and CC (or CC and BCC), when the final list compiles, then the address appears only in the highest field (TO > CC > BCC), matched case-insensitively; and duplicate literals within TO collapse to one (FR-17).
- **AC-11** Given a Gmail-group entry, when dispatch runs, then exactly the stored literal group address appears in TO (no membership expansion call is made) and the audit records the entry as `gmail_group` (FR-9).

### 7.3 Scheduled sends & the D1 toggle
- **AC-12** Given a schedule rule with `resolve_at_send=false` (default), when its occurrence dispatches, then recipients come verbatim from `recipients_snapshot` and no re-resolution occurs — existing scheduler behavior unchanged (FR-12).
- **AC-13** Given a schedule rule with `resolve_at_send=true` on a token-recipient template, when its occurrence dispatches, then the occurrence carries a reference (anchor id + token spec), the engine resolves at that moment, and a salesperson reassigned between materialize and fire receives/loses the mail accordingly (FR-12).
- **AC-14** Given DRR is not yet deployed, when an admin attempts to set `resolve_at_send=true`, then config rejects it; and a rule cannot combine `resolve_at_send=true` with EVENT/tz-accurate snapshot semantics (FR-12, mutual exclusion).
- **AC-15** Given pre-DRR occurrences SKIPPED with reason `"recipient requires DRR (#3)"`, when the engine ships, then newly materialized occurrences for the same schedules resolve and dispatch normally (FR-20).

### 7.4 Audit & preview
- **AC-16** Given any dispatch that ran resolution, then `NotificationLog` carries the template identifier, per-entry configured value + kind + resolved addresses + outcome + reason, and timestamp; these records are not editable or deletable via any API; and the legacy `email` column still carries the first TO address so the payment-reminder dedupe query returns unchanged results (FR-18).
- **AC-17** Given the template editor preview, when the admin selects a sample anchor record, then the preview shows the compiled To/CC/BCC with per-entry outcomes without sending anything, and is only accessible under the template-edit permission (FR-22/FR-23).

### 7.5 Shared-engine conformance (release-constraint ACs)
- **AC-18** The scheduler's existing `recipient_source` (bare column / one-hop) and `replacements_map` (`FULL_NAME`/`DATE_FMT`) inputs resolve through the **same engine entry point** as tokens, with config-time and materialize/dispatch-time validation both intact; no second resolver code path exists (FR-20).
- **AC-19** The engine's resolve interface accepts a destination-field selector (email today) such that 76.8 can request phone resolution without modifying token semantics — verified by interface signature review, not by shipping SMS (FR-21).

---

## 8. Out of scope

- **SMS recipient resolution and dispatch** — 76.8's story; this story only guarantees the phone-extensible interface (FR-21). Provider mechanism confirmation is **SMS-01**.
- **Predefined-template recipient resolution** — retired variant (DRR-14 settled); predefined flows keep call-site recipients (pending DRR-05 confirmation).
- **Google Workspace Directory integration / group-membership enumeration** — excluded under the DRR-03 literal-address default; becomes in-scope only if the client picks expansion.
- **The V1 token vocabulary** (`{client_email_address}`, `{all_speaker_email_addresses}`, SMS phone tokens) — historical; speaker-token sends remain scheduler-SKIPPED until a token spec for them is commissioned.
- **Vendor-from-show-details source** — carried OPEN (DRR-16), not built by default.
- **Consent/opt-out modelling** — no consent model exists in any schema; 2026 SMS-compliance scoping (validation report M2) belongs to the SMS story.
- **Changing the scheduler's default timing or any part of the approved scheduling plan** — the plan is READ-ONLY; DRR only adds the D1 toggle surface the review specified.

---

## 9. Dependencies & sequencing

1. **`Exhibitor.company_id @unique` drop (D2)** — must land before or with DRR (`{all customer contacts}` hard-requires it); standalone fix, all five schemas, admin migration + `db push`.
2. **The unified `NotificationLog` migration (M3/DRR-10/DRR-S2)** — one migration shared with the SMS track; designed jointly, lands once.
3. **Scheduling build** — provides the by-id dispatch path, the occurrence pipeline, the SKIP vocabulary, and the snapshot default DRR plugs into; the #21 slug-path fix ships with it (DRR live sends depend on it or on by-id, §6.5).
4. **BA/client sessions** — blockers DRR-01…DRR-05 gate coding the resolver; D1/D3 land as recommendations to confirm, not build-blockers.
5. **SMS track (76.8)** — consumes this engine; Twilio/A2P 10DLC registration (days-to-weeks) starts day one in parallel; DRR slippage strands SMS (M4 sequencing).

---

## 10. Open questions register (carried IDs — stable, do not renumber)

| ID | Status in this story | One-line question | Owner |
|---|---|---|---|
| DRR-01 | PROPOSED default in §3.2/FR-6 | `{salesperson}` source per trigger; null fallback | BA |
| DRR-02 | PROPOSED default in §3.2/FR-7/FR-8 | main = `user_type=1`; all = accepted non-deleted rows; approve `@unique` drop; membership filter | BA |
| DRR-03 | PROPOSED default (literal address) in §3.2/FR-9 | literal Google-Group address vs Directory-API expansion; credentials; empty-group detection | Client |
| DRR-04 | Mechanism PROPOSED / matrix OPEN (§3.4/FR-19) | per-trigger token exposure matrix; config-gate vs send-fallback | BA |
| DRR-05 | PROPOSED default in §3.5/FR-13 | authoritative send-time source; predefined in/out of scope | BA |
| DRR-06 | PROPOSED default (skip-and-log, no default address) in §3.7/FR-15 | unresolvable-recipient fallback; zero-recipient surfacing | BA |
| DRR-07 | OPEN (§3.2/FR-10) | backing source for predefined lists + "other relevant system emails" | BA |
| DRR-08 | PROPOSED default (TO>CC>BCC, case-insensitive) in §3.7/FR-17 | cross-field dedup rule | Client |
| DRR-09 | OPEN (§FR-21) | SMS resolution ownership (77.9 vs 76.8); token→phone mapping; null-phone behavior | BA |
| DRR-10 | PROPOSED default (NotificationLog, unified migration) in §3.8/FR-18 | audit storage shape | BA/Engineering (joint) |
| DRR-11 | PROPOSED default in §3.7/FR-14 | config-time grammar; invalid-resolved-address handling | BA |
| DRR-12 | PROPOSED default (existing permission, no extra gate) in §4/FR-23 | role-gating + privacy of groups/bulk contacts | Client |
| DRR-13 | Adjudicated by D1, pending BA sign-off (§3.6/FR-12) | snapshot vs re-resolve for scheduled sends | BA |
| DRR-15 | OPEN (§3.2/FR-4) | TO-only vs FROM/CC/BCC tokens; FROM × `AllowedFromDomain` | BA/Client |
| DRR-16 | OPEN (§FR-24) | vendor-from-show-details as a fourth source, or deferred | BA/Client |
| DRR-17 | PROPOSED default (typed entries) in §3.3/FR-5 | entry typing in `channel_config` | BA |
| D1 | PROPOSED (external adjudication adopted; §3.6) | per-rule `resolve_at_send` toggle, default snapshot — confirm "both, selectable" | BA |
| D2 | PROPOSED (engineering action; §6.3) | approve the five-schema `@unique` drop as a standalone fix | Engineering/BA |
| D3 | PROPOSED (§3.7/FR-16) | zero-recipient policy split: skip-and-log marketing / abort-and-alert transactional / never send to zero | BA |
| SMS-01 | OPEN (carried from the SMS track; §2.2/§8) | SMS provider mechanism — client said "SendGrid" (email-only API); actual A2P SMS = Twilio Programmable Messaging; must be confirmed, never assumed | Client |
| **DRR-S1** | NEW — PROPOSED default in §4/FR-22 | preview sample-context selection: admin picks a recent real anchor record; preview under template-edit permission — confirm the mechanism and its privacy posture | BA |
| **DRR-S2** | NEW — PROPOSED default in §3.8/§6.2 | unified NotificationLog migration keeps the legacy `email` column unchanged, still populated with the first TO recipient, so the payment-reminder dedupe query (`payment-reminder.service.ts:225-233`) is not broken — confirm vs migrating that query | Engineering/BA |

Settled, carried for completeness: **DRR-14** — the predefined-DRR V2 variant is out of scope (existing decision, KNOWN_ISSUES #3); residual scope thread folded into DRR-05.

---

## 11. Known-issues impact

- **#3 Dynamic recipient resolution** — moves from *deferred* to **specified** (this document); building it un-gates the scheduler's token-recipient SKIP (FR-20/AC-15).
- **#2 SMS provider** — unchanged by this story; the engine's phone-extensible interface (FR-21) is the seam 76.8 uses.
- **#21 custom-shadows-predefined at send** — DRR live sends must ride by-id dispatch or land after the slug-path fix that ships with the scheduling build (§6.5).
- **#4 "other relevant system emails" source** — unchanged; re-surfaced here as DRR-07.

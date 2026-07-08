---
atom_id: EMS-779-DRR
title: Shared Recipient-Resolution Engine (Dynamic Recipient Resolution, story 77.9)
version: v1
status: draft
type: implementation
sessions: 1
session: 1
epic: "Email & SMS Management — combined release (76.6/77.8 + 77.9 + 76.8)"
estimate: 122.0h
risk_tier: high
priority: Must Have
depends_on: [EMS-SCH-BUILD, EMS-D2-FIX]
blocks: [EMS-768-SMS]
cc_refs: []
tags: [email-sms, drr, recipient-resolution, shared-engine, combined-release, notification-log]
plan_family: null
parent_plan: null
covers_atoms: null
tracker_ref: "email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_REFINED_STORY.md (refined story, DOC set 7-of-7)"
regulated_workload: false
compliance_scope: null
---

# EMS-779-DRR Implementation Plan — Shared Recipient-Resolution Engine (v1 — Draft)

**DOC 7 of 7 — combined-release doc set** (`email_sms_combined_release_docs/`).
**Scope:** 1 session, phased build (Phases D0–D6) sequenced against the scheduling track (76.6/77.8) and the SMS track (76.8). One combined release: **one resolver, one unified `NotificationLog` migration, one D1 `resolve_at_send` toggle (default = snapshot-at-materialize).**
**Source:** `EMAIL_SMS_77.9_DRR_REFINED_STORY.md` (requirement baseline; FR-1…FR-24, AC-1…AC-19, question IDs DRR-01…DRR-17/DRR-S1/DRR-S2/D1/D2/D3/SMS-01).

**Canon reconciliation:** The Confluence 77.9 clause "resolve at send time using the most current data, never config-time values" conflicts with the approved scheduling plan's snapshot-at-materialize + verbatim-replay contract (scheduling plan §2.2, §4 item 8). Resolved per the external review's **D1 (HIGH)** adjudication, adopted by the refined story §3.6/FR-12: snapshot stays the default; freshness is a per-rule `resolve_at_send` toggle owned by this plan. The scheduling plan file itself is **READ-ONLY** — this plan adds surface around it, never edits it.

---

## Gate Contract

Binary, externally verifiable, ordered by criticality:

- **No second resolver:** `grep -rn "recipient_source" background-worker-service/src/scheduler/ | grep -v recipient-resolution` shows no inline parsing left in the materializer/dispatcher — both call `RecipientResolutionService` (FR-20/AC-18).
- **Scheduler regression zero:** all pre-existing scheduling-build tests pass unmodified; a `resolve_at_send=false` occurrence dispatch replays `recipients_snapshot` byte-identical with no engine re-resolution call (AC-12).
- **Un-gate proven:** in staging, a schedule whose recipients previously SKIPPED with reason `"recipient requires DRR (#3)"` materializes and dispatches normally after deploy (AC-15).
- **Unified migration roundtrip clean** on a disposable DB: `prisma migrate deploy` → verify columns → `migrate resolve --rolled-back` path documented; the payment-reminder dedupe query (`background-worker-service/src/jobs/payment-reminder/payment-reminder.service.ts:225-233`) returns identical results on fixture data before/after (FR-18/AC-16).
- **Zero-recipient policy enforced:** integration test proves a zero-recipient dispatch never reaches the provider — marketing trigger → SKIPPED with reason; transactional trigger → FAILED + alert (AC-8).
- **Preview is side-effect-free:** the preview endpoint produces per-entry outcomes and writes **no** `NotificationLog` row with status SENT and sends nothing (AC-17).
- **Phone-extensible interface verified by signature review:** `resolve()` accepts a `destination` selector; changing it to `'phone'` requires no change to token semantics (AC-19).
- All quality gates green (§Quality Gates) across the five repos.

### Acceptance Criteria

Atom-level acceptance = the refined story's AC-1…AC-19 (`EMAIL_SMS_77.9_DRR_REFINED_STORY.md` §7) — reproduced there, not restated here. Every PROPOSED default in the story is covered by an AC, so story sign-off = defaults sign-off; this plan builds exactly those defaults and stops on the BLOCKED-ON steps (§Implementation Order) where a default is still awaiting its named answer.

---

## Context

**Why:** The shipped scheduler deliberately SKIPs every occurrence whose recipients are tokens with no column on the anchor — reason `"recipient requires DRR (#3)"` (scheduling plan §4 item 7, §9). Until this atom ships, those sends never fire, and the SMS track (76.8) is stranded: it must reuse this engine extended to a phone field (review M4) and cannot fork its own resolver (release constraint). Separately, custom-template recipient configuration is dead data today — no live send path reads `channel_config` (grep evidence: `channel_config` referenced only inside `admin-backend-api/src/admin/notification-template/{dto,controller,service}.ts`) — so the client-visible 77.9 behavior ("trigger-driven emails reach the right people from template config") does not exist at all. DRR is the middle of the combined-release dependency chain; slipping it strands both sibling tracks.

**What:** A single **recipient-resolution engine** — `RecipientResolutionService` — that, given a template's typed recipient entries (or the scheduler's restricted `recipient_source`/`replacements_map` forms as its degenerate tier) plus a trigger/anchor context, produces the compiled `{to[], cc[], bcc[]}` with per-entry resolution outcomes and a zero-recipient disposition (D3 policy). Three consumers: **live sends** (inline at dispatch), **the scheduler** (snapshot-at-materialize by default; dispatch-time when the per-rule `resolve_at_send` toggle is on), and **later SMS** (same engine, `destination:'phone'`). Plus: the token registry with per-token Prisma resolvers, typed `channel_config` entries, config-time validation + a read-only preview endpoint in admin, the D3 zero-recipient policy, and the DRR half of the ONE unified `NotificationLog` migration.

### Reference Documents

| Document | Type | Refer To | Purpose |
|----------|------|----------|---------|
| `email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_REFINED_STORY.md` | Spec | Whole doc (FR/AC/§10 register) | Requirement baseline; question IDs |
| `email_sms_scheduling_plan_and_supporting_docs/EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` | Dependency plan (READ-ONLY) | §2.1, §2.2, §4 items 3/7/8/9/12, §7, §9 | The resolver being generalized; occurrence pipeline; by-id dispatch; SKIP vocabulary |
| `email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md` | Dependency plan (delta) | §0.2–0.3 (finding ownership), S1/S2/S3/S6 sections, D2 section | Review deltas the engine inherits (retention bounds, alert channel, fail-closed posture); D2 execution home |
| `EMAIL_SMS_77.9_DYNAMIC_RECIPIENT_RESOLUTION_GAP_ANALYSIS.md` | Spec (context) | DRR-01…DRR-17 sections | Original open-question register with evidence |
| `email_sms_combined_release_docs/EMAIL_SMS_76.8_SMS_REFINED_STORY.md` | Sibling spec | Engine-reuse + SMS-01 sections | The phone-field consumer contract; unified-migration co-owner |
| `admin-backend-api/src/admin/notification-template/notification-template.service.ts` | Pattern reference | `:94-99`, `:109-119`, `:404-422`, `:572-592`, `:599-610` | `assertPlaceholdersAllowed` extension point; `dedupeEmails`; predefined edit matrix; `AllowedFromDomain` |
| `admin-backend-api/src/admin/notification-template/dto/notification-template.dto.ts` | Config reference | `:81-97`, `:171-228` | `RecipientList()` validator to loosen; `EmailChannelConfigDto` shape |
| `admin-backend-api/src/admin/orders/services/order-notification.service.ts` | Pattern reference | `:166-218` (esp. `:196-199`) | The established "main contact" lookup + recipient-chain skip-with-log precedent |
| `background-worker-service/src/notification/mailer.service.ts` | Pattern reference | `:90-184` (esp. `:95-101`, `:126-183`, `:129`) | The only `string[]` mailer; NotificationLog PENDING→SENT write path; `to[0]` logging defect |
| `background-worker-service/src/jobs/payment-reminder/payment-reminder.service.ts` | Config reference | `:63`, `:225-233` | The two queries the migration/D2 must not break |
| `exhibitor-backend-api/src/company_user/company_user.service.ts` | Pattern reference | `:105-111`, `:237-248`, `:251-253` | `user_type` semantics; multi-row-per-company invite flow (D2 proof); invitation_status handling |
| `admin-backend-api/src/database/seeds/trigger-event.seeder.ts` | Pattern reference | Full file | Code-controlled trigger catalog to extend with `available_recipient_tokens` + classification |
| `admin-backend-api/src/admin/common/agreement-document/base-agreement-document.service.ts` | Pattern reference | Full file | Same-repo hoist precedent (adeba9f) for shared-base layering |

### Dependencies

**Dependencies (blocking):**
- **EMS-SCH-BUILD** — the scheduling build (76.6/77.8): provides `notification_schedules`, `notification_schedule_occurrences`, the materializer/dispatcher, `recipients_snapshot`, the by-id `notificationTemplateId` dispatch path, the SKIP-reason vocabulary, and the #21 slug-path fix. Status: **approved to build, in flight** — Phases D2/D3 of this plan require its Phases 1–3 delivered.
- **EMS-D2-FIX** — the five-schema `Exhibitor.company_id @unique` drop. **Executed by the scheduling-track addendum** (`EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md` §0.2/D2 section — "standalone data-integrity fix decoupled from DRR", per review D2), because `{all customer contacts}` returning >1 row hard-requires it. This plan does not re-implement it; Phase 0 check #2 verifies it landed, and Step 1 carries a contingency (BLOCKED-ON → D2).

**Dependencies (design-time, not code):** BA/client sessions for DRR-01…DRR-05 (the story's coding blockers, story §9 item 4); the SMS track's provider confirmation SMS-01 does **not** block any DRR step but its Twilio/A2P 10DLC kickoff is a Phase D0 day-one item because it is the combined release's long pole.

### Scope Boundary

- **This atom owns:** the resolution engine (worker canonical + admin native mirror), the token registry + per-token resolvers, typed `channel_config` entries + normalization, config-time recipient validation + preview endpoint, the D1 `resolve_at_send` column/branch/reference-mode, the D3 zero-recipient policy + trigger classification flag, the DRR fields of the ONE unified `NotificationLog` migration (channel column co-designed with SMS; generalized recipient JSON; DRR-S2 legacy-`email` preservation — `notification_template_id` already exists NOT NULL, DD-8), and the scheduler's switchover to consuming the engine.
- **The scheduling track owns (do not build here):** the occurrence pipeline, claim/reaper/retry machinery, S1 retention cron, S3 alert channel, S6 tz fail-closed, the #21 slug-path fix, and the D2 `@unique` drop execution. This plan only *plugs into* those (engine SKIP reasons join the existing vocabulary; the transactional abort rides the S3 alert channel).
- **The SMS track (76.8) owns (do not build here):** the provider adapter, phone-token *values*, the `channel='SMS'` gate flip, quiet-hours/compliance (review M2), and the `channel` column *semantics* for SMS rows. This plan guarantees only the phone-extensible interface (`destination` selector, FR-21/AC-19) and ships the shared migration with the `channel` column present.
- **Predefined (seeded) templates stay call-site-resolved** and out of DRR scope (FR-13 default pending DRR-05); exhibitor-backend-api and external-api-service send sites stay out of DRR scope (single-address, caller-resolved, predefined-slug flows — story §6.1). Those two repos receive **`db push` schema mirrors only**.

**Explicit implementation dependency:** the live-send consumption point (Step 10) is only *safe* once the #21 custom-shadows-predefined slug-path fix (shipping with the scheduling build) is deployed — a DRR live send resolving the wrong template would resolve the wrong recipient config (story §6.5). Step 10 therefore gates on Phase 0 check #6 and ships behind the `DRR_LIVE_SEND_ENABLED` rollout gate (DD-12).

---

## Design Decisions

Numbering: `DD-n` for this plan's decisions. External review finding IDs (D1/D2/D3, S1–S7, M1–M4, X1–X2) and story question IDs (DRR-xx) are referenced by their own names and are **never** re-used as plan decision numbers.

### DD-1: One engine, scheduler = consumer; the restricted forms are the degenerate tier

The engine **generalizes** the scheduler's restricted resolver (scheduling plan §2.1: `recipient_source` = bare anchor column | one documented relation hop against a code-controlled per-anchor map; `replacements_map` = bare column | `FULL_NAME(a,b)` | `DATE_FMT(f,'pattern')`; validated at config AND materialize time; no expression DSL, no eval). Those forms become **input kinds of the same engine** — internally `{kind:'anchor_column'|'anchor_hop', value}` entries and the two named transforms — not a separate code path. The scheduler's materializer and dispatcher call `RecipientResolutionService`; their inline resolution code is removed. (FR-20/AC-18; release constraint; review M4; gap analysis "extend the allow-list, not stand up a parallel mechanism".)

**Implication:** any PR that adds recipient parsing outside `recipient-resolution/` fails the Gate Contract grep. The no-DSL/no-eval security posture is inherited unchanged — token specs are code-registered functions, never admin-authored expressions.

### DD-2: Engine home — worker canonical, admin native mirror, conformance-vector enforced

Resolution core lives in **`background-worker-service/src/notification/recipient-resolution/`** — beside the scheduler's materializer/dispatcher and the only multi-recipient mailer (worker `mailer.service.ts:90-184`). Config-time validation lives in **`admin-backend-api/src/admin/notification-template/`** beside `assertPlaceholdersAllowed` (`notification-template.service.ts:572-592`), because admin owns template CRUD. Admin-triggered **live** sends and the preview endpoint need inline resolution in admin: per the cross-repo house rule (no shared npm package exists; the four mailers are deliberate mirrors), admin gets a **native implementation to identical semantics** (`admin-backend-api/src/common/services/recipient-resolution/` — 3 files, per the Files table and Step 8; header comment "mirrors background-worker-service/src/notification/recipient-resolution/"). This is a mirror of ONE design, not a second resolver: both implementations must pass the **same committed conformance-vector fixture** (Step 14) so semantic drift is a test failure, not a code review hope. exhibitor/external get no engine code (Scope Boundary).

**Implication:** every behavioral change to the engine lands in both repos in the same release, and the vector file is updated first.

### DD-3: Token registry — code-controlled specs, one shape, exact resolvers

A code-controlled `TOKEN_REGISTRY` maps each token literal to a spec:

```ts
interface RecipientTokenSpec {
  token: 'salesperson' | 'main_customer_contact' | 'all_customer_contacts';
  requiredContext: 'orderId' | 'companyId';        // config-time offerability gate (FR-19)
  multiplicity: 'one' | 'many';
  resolve: (ctx: ResolutionContext, tx: PrismaClientLike) => Promise<ResolvedDestination[]>;
  // ResolvedDestination = { email: string; phone: string | null; ref: string }  ← phone slot = FR-21 seam
}
```

Per-token resolvers (the exact Prisma queries — PROPOSED defaults per story §3.2, pending DRR-01/DRR-02):

- **`{salesperson}`** (DRR-01): defined only for order-context triggers.
  ```ts
  const order = await tx.order.findUnique({
    where: { id: ctx.orderId },
    select: { salesPerson: { select: { email: true, phone: true, id: true } } }, // Order.sales_person_id Int? → User (schema.prisma:1615/1634); User.email required-unique (:12)
  });
  return order?.salesPerson ? [{ email: order.salesPerson.email, phone: order.salesPerson.phone, ref: `user:${order.salesPerson.id}` }] : [];
  ```
  Empty result → unresolved entry (FR-15). `Exhibitor.strategist_id`/`referred_by` are different roles and are **not** stand-ins (do NOT add them).
- **`{main customer contact}`** (DRR-02): the codebase's own precedent (`order-notification.service.ts:196-199`).
  ```ts
  const ex = await tx.exhibitor.findFirst({
    where: { company_id: ctx.companyId, user_type: 1, deleted_at: null },
    select: { email: true, phone: true, id: true },
  });
  return ex ? [{ email: ex.email, phone: ex.phone || null, ref: `exhibitor:${ex.id}` }] : [];
  ```
- **`{all customer contacts}`** (DRR-02; hard-requires the D2 drop):
  ```ts
  const rows = await tx.exhibitor.findMany({
    where: {
      company_id: ctx.companyId, deleted_at: null,
      OR: [{ user_type: 1 }, { user_type: 2, invitation_status: INVITATION_ACCEPTED }],
    },
    select: { email: true, phone: true, id: true },
    orderBy: { id: 'asc' },   // deterministic output for snapshot/test stability
  });
  ```
  Pending/revoked/soft-deleted rows are **excluded** (delivery rule, not the UI display rule). `INVITATION_ACCEPTED` is the accepted value confirmed by Phase 0 check #4 against `company_user.service.ts` — do not guess it.

The registry also carries the scheduler's existing per-anchor allow-list (CART / ORDER / PAYMENT_TRANSACTION maps, scheduling plan §4 item 12) so there is exactly one allow-list source in each repo.

**Implication:** adding a token = adding a registry entry + seeder matrix rows + vectors; no admin CRUD anywhere (mirrors `available_placeholders` governance).

### DD-4: Typed recipient entries in `channel_config` (DRR-17) with write-time + one-off normalization

`to_recipients`/`cc_recipients`/`bcc_recipients` move from flat `string[]` to typed entries `{ kind: 'literal' | 'token' | 'gmail_group' | 'list_ref', value: string }`. The admin API accepts a **union** (plain string → normalized to `kind:'literal'` on write) so existing FE calls keep working during the transition; the unified migration (Step 1) runs a one-off SQL normalization wrapping every existing stored entry as `literal`. Config-time grammar (DRR-11): a `token` entry must name a registry token exposed by the template's trigger; `gmail_group`/`literal` values must be RFC 5322; `list_ref` values must name a registered predefined list — nothing else, no free text. (FR-5/FR-14; rationale: DRR-03 group behavior, DRR-10 per-entry audit, and the DRR-04 matrix all key off `kind` — a curly-brace convention makes external-email vs group ambiguity permanent.)

**Implication:** `RecipientList()` (`notification-template.dto.ts:81-97`) is replaced by a typed-entry validator; the DTO comment at `:171-174` ("until the Dynamic Recipient Resolution phase") is redeemed by this step.

### DD-5: D1 `resolve_at_send` — column + in-JSON reference mode + one dispatcher branch

Exactly as the external review specs it (D1, HIGH; story §3.6/FR-12):

- `notification_schedules.resolve_at_send Boolean NOT NULL DEFAULT false` (NOT NULL + default = backfill-free; Int-PK rule untouched).
- When `true`, the occurrence's `recipients_snapshot` stores a **reference shape**, not resolved addresses: `{ mode:'reference', anchor_instance_ref, entries:[…typed entries…], context:{orderId?,companyId?} }`. Snapshot shape gains a `mode:'snapshot'` discriminator (default) — **no second column**, no occurrence schema change beyond what the scheduling build ships.
- The dispatcher grows **exactly one branch**: `if (rule.resolve_at_send) → engine.resolve(...) at dispatch; else → replay snapshot verbatim`.
- Config-time: `resolve_at_send=true` **rejected until DRR is deployed** (validator checks a build-time capability constant flipped in this release) and **mutually exclusive** with tz-accurate/EVENT snapshot semantics (the Klaviyo precedent) — both enforced in the admin schedule DTO validator.

**Implication:** the scheduler default is untouched (AC-12); DRR-13 is satisfied as "both, selectable", pending BA sign-off (BLOCKED-ON → D1).

### DD-6: D3 zero-recipient policy + trigger classification on the catalog

The engine computes a **disposition**, consumers act on it: `zeroRecipients && !is_transactional → SKIP` (occurrence/dispatch recorded skipped with reason `"zero recipients — skipped (marketing)"`); `zeroRecipients && is_transactional → ABORT` (recorded failed, reason `"zero recipients — aborted (transactional)"`, alert raised on the **S3 alert channel the scheduling addendum establishes** — no new alert mechanism). **Never send to zero** in any case. Classification lives on the code-controlled trigger catalog: `trigger_events.is_transactional Boolean NOT NULL DEFAULT false`, seeder sets an **explicit** value for every seeded slug and a unit test asserts the seeder map covers every slug (a default-only row is a test failure, since DB default can't be distinguished from a decision). (FR-16/AC-8; classification content is a BA deliverable — BLOCKED-ON → D3/DRR-04.)

**Implication:** the engine never throws for zero recipients; it returns `disposition` so live and scheduled consumers map it to their own status machinery. Unresolvable single entries (FR-15) are per-entry skip-and-log — **no default-address substitution** (rejected: none exists anywhere in code/config; inventing one risks misdirected mail).

### DD-7: Gmail group = literal-address model (DRR-03 default)

A group is stored as one entry `{kind:'gmail_group', value:'<group@company.com>'}`; dispatch passes the literal address; Google expands membership on receipt. **No** Workspace Directory API, no service account, no group tables. Honest consequence (story FR-9): "group with no members" is undetectable — re-scoped to normal send-failure/bounce logging. The `kind` marker exists so the audit distinguishes it (AC-11) and so a future expansion model (if the client picks it) changes only the resolver for this kind.

### DD-8: The ONE unified `NotificationLog` migration — DRR's half, co-designed with SMS

One admin-owned migration (shared with the SMS track's M3 need — designed jointly in Phase D0, lands **once**; neither track writes its own):

| Column | Type / constraint | Rationale |
|---|---|---|
| `channel` | `NotificationChannel` enum, **NOT NULL DEFAULT 'EMAIL'** | M3/SMS discriminator; default backfills all existing rows correctly (all historical rows are email) |
| `recipients` | `Json NOT NULL DEFAULT '[]'` | Generalized per-dispatch resolution audit (DRR-10/FR-18): array of `{field:'to'\|'cc'\|'bcc', entry, kind, resolved:[{email\|phone, ref?}], outcome:'resolved'\|'skipped'\|'failed', reason?}` |
| `email` (existing `String?`) | **kept, unchanged, still populated with the first TO recipient** | DRR-S2: the payment-reminder dedupe query filters on `email` + slug + sent-at window (`payment-reminder.service.ts:225-233`) and must return unchanged results; dropping/nulling it is a regression until that query is migrated |

**`notification_template_id` needs NO migration work — the column already exists.** It is `Int` **NOT NULL** with FK `onDelete: Cascade` (admin `prisma/schema.prisma:311/:327`) and is already populated on every log write by both mailers (worker `mailer.service.ts:128`, admin `mailer.service.ts:246` — `notification_template_id: template.id`), so the Confluence 77.9 "template identifier" audit requirement is satisfied by the existing column and every historical row already carries its template id (no backfill question exists). Any change to its nullability or delete behavior would be an **ALTER of an existing column and a behavior change** — out of scope for this migration unless explicitly decided. Note the existing `onDelete: Cascade` deletes log rows when their template is deleted, which sits in tension with the "permanent, non-editable audit" intent — flagged as a sub-decision under the DRR-10 sign-off (open-questions register, section F), not silently changed here.

No new tables; no new BigInt PKs (`NotificationLog.id` BigInt is the pre-existing approved exception and is not propagated). Historical rows keep `recipients=[]` — the legacy single-address fact remains in `email`; no fabricated backfill. Immutability (AC-16): no update/delete API is added anywhere for these columns; the only writers are the mailer send paths.

**Implication:** worker/admin mailers start writing `recipients` + `channel` on every send (Step 11 — `notification_template_id` is already written today, worker `:128` / admin `:246`); worker's `to[0]`-only logging (`worker mailer.service.ts:129`) becomes first-TO into `email` **plus** the full structured array into `recipients`.

### DD-9: D2 `@unique` drop is a prerequisite executed by the scheduling-track addendum

The drift (declared `@unique` at `admin/exhibitor/external schema.prisma:1030`, `worker/pulse :944`; real DB has only plain `idx_exhibitors_company_id`, init migration `:241`; invite flow creates multi-rows — `company_user.service.ts:237-248`) is fixed as a **standalone** migration per review D2, homed in the scheduling addendum (§0.2). This plan **verifies** it (Phase 0 check #2) instead of duplicating it. Contingency: if not landed when Phase D1 starts, Step 1 absorbs it (drop `@unique` → `@@index` in all five schemas + remove/rename the one-to-one back-relation `Company.exhibitor`, patching its one consumer `payment-reminder.service.ts:63` to the `findFirst(user_type=1, deleted_at:null)` precedent) — recorded in BLOCKED-ON → D2. `{all customer contacts}` must not ship before this lands (Prisma would runtime-error or silently mis-model multi-rows).

### DD-10: Cross-field dedup — TO > CC > BCC, case-insensitive full address, match `sendMail()`

After resolution, an address appearing in multiple fields keeps only its highest placement (TO > CC > BCC); matching is case-insensitive on the full address (consistent with `dedupeEmails`, `notification-template.service.ts:109-119`); within-field duplicates collapse (TO gains within-field dedup it currently lacks). Admin's low-level `sendMail()` already cross-field-dedupes (`admin mailer.service.ts:85-144`) — the engine's compile step implements the **same** rule so the two layers agree (engine output is already deduped; `sendMail`'s pass becomes a no-op safety net, not a divergence). (FR-17/AC-10; PROPOSED — BLOCKED-ON → DRR-08.)

### DD-11: Phone-extensible resolve interface (FR-21/AC-19)

`resolve()` takes `destination: 'email' | 'phone'`. Every resolver returns `ResolvedDestination { email, phone, ref }`; the compile step projects the requested field and treats a null/empty projection as an unresolved entry (mirrors the S6 fail-closed posture — critical because `Exhibitor.phone` is required-but-`''` for invited members, `company_user.service.ts:246`, and `User.phone` is nullable, `schema.prisma:16`). SMS (76.8) therefore extends by **calling with `'phone'`**, not by modifying token semantics. `destination:'phone'` is **rejected at the entry point in this release** (guard clause + test) so no phone path can be half-enabled before the SMS track flips it.

### DD-12: Live-send consumption point — custom templates only, by stored config, behind a rollout gate

Per FR-13 (PROPOSED, BLOCKED-ON → DRR-05): in admin's `MailerService.sendFromTemplate`, after template lookup, **if** `template.is_predefined === false` **and** its `channel_config` carries recipient entries, the engine resolves the stored config (with caller-supplied `context: {orderId?, companyId?}` added to `SendFromTemplateOptions`) and the compiled `{to,cc,bcc}` is used — **no merge** with the caller's `to` (merge is the double-send/dropped-recipient risk the gap analysis rejects). Otherwise (predefined, or custom with no stored recipients) the legacy caller-`to` behavior is untouched. The whole branch sits behind env gate `DRR_LIVE_SEND_ENABLED` (default `false`; flipped at rollout Phase D6) and requires the #21 slug-path fix deployed (Phase 0 check #6) so the looked-up template is deterministically the right one. Call sites that cannot supply context simply resolve tokens to unresolved → FR-15 skip-and-log. Worker/exhibitor/external `sendFromTemplate` are untouched (Scope Boundary; scheduled dispatch is by-id and consumes the engine via the occurrence pipeline instead).

### DD-13: Concurrency hazard analysis

- New paths that run concurrently with existing ones against the same resource? **Yes** — dispatch-time resolution (`resolve_at_send=true`) adds read queries inside the dispatcher tick against Order/Exhibitor/User. Mitigation: reads only, executed inside the existing claim window (occurrence already `SENDING` via the S2 `FOR UPDATE SKIP LOCKED` claim) — no new locks, no writes outside the existing status machine.
- Tighter loop or higher emission rate than the path this replaces? **No** — same occurrence cadence; per-occurrence work grows by ≤3 indexed reads.
- New automatically-triggered action? **No** — no new cron; the engine is invoked only by existing send paths.
- Changes any concurrency-control constant? **No** — retry taxonomy, backoff `[5m,30m,2h]`, `MAX_OCCURRENCE_ATTEMPTS=3`, reaper window all inherited unchanged.
- Residual: at-least-once delivery (S2, stated) means a reaper-reset re-dispatch under `resolve_at_send=true` may re-resolve and reach a *different* recipient set than the first attempt. Accepted: it is the freshness semantics the toggle opts into; the audit rows record each attempt's actual resolution.

### DD-14: Preview endpoint — real engine, read-only, admin-picked sample context (DRR-S1)

`POST /admin/notification-templates/:id/recipient-preview` with body `{ context_type: 'order' | 'company', context_id: number }` runs the **same** admin-native engine in `mode:'preview'` (no send, no NotificationLog write, no occurrence) and returns the compiled To/CC/BCC + per-entry outcomes. Guarded by the existing notification-template edit permission (FR-23/DRR-12 default — no extra role gate); resolved addresses shown are ones the admin could see in the source modules anyway. The admin picks a recent real anchor record via existing admin search/list endpoints on the FE side — this endpoint takes only the chosen id. (AC-17; PROPOSED — BLOCKED-ON → DRR-S1/DRR-12.)

---

## Files

Grouped per repo (file-touch inventory). Every file appears in ≥1 implementation step and vice versa.

### admin-backend-api (owns the migration)

| File | Action | ~Lines |
|------|--------|--------|
| `prisma/migrations/<ts>_ems_unified_notification_spine/migration.sql` | CREATE | ~90 |
| `prisma/schema.prisma` | MODIFY | +~15 |
| `src/database/seeds/trigger-event.seeder.ts` | MODIFY | +~120 |
| `src/admin/notification-template/dto/notification-template.dto.ts` | MODIFY | +~110 |
| `src/admin/notification-template/notification-template.service.ts` | MODIFY | +~140 |
| `src/admin/notification-template/notification-template.controller.ts` | MODIFY | +~30 |
| `src/admin/notification-schedule/dto/*.dto.ts` (schedule DTO from the scheduling build; exact name pinned in Phase 0 check #5) | MODIFY | +~30 |
| `src/common/services/recipient-resolution/token-registry.ts` | CREATE | ~160 |
| `src/common/services/recipient-resolution/recipient-resolution.service.ts` | CREATE | ~300 |
| `src/common/services/recipient-resolution/recipient-resolution.types.ts` | CREATE | ~80 |
| `src/common/services/mailer.service.ts` | MODIFY | +~90 |
| `test/fixtures/recipient-resolution-vectors.json` | CREATE | ~250 |
| `src/admin/notification-template/__tests__/recipient-validation.spec.ts` | CREATE | ~300 |
| `src/common/services/recipient-resolution/__tests__/recipient-resolution.service.spec.ts` | CREATE | ~350 |
| `src/admin/notification-template/__tests__/recipient-preview.e2e.spec.ts` | CREATE | ~180 |

### background-worker-service (canonical engine home)

| File | Action | ~Lines |
|------|--------|--------|
| `prisma/schema.prisma` | MODIFY (then `db push`) | +~15 |
| `src/notification/recipient-resolution/token-registry.ts` | CREATE | ~160 |
| `src/notification/recipient-resolution/recipient-resolution.service.ts` | CREATE | ~300 |
| `src/notification/recipient-resolution/recipient-resolution.types.ts` | CREATE | ~80 |
| `src/scheduler/schedule-dispatch/*` materializer service (exact filename pinned in Phase 0 check #5) | MODIFY | +~60 / −~40 |
| `src/scheduler/schedule-dispatch/*` dispatcher/executor service (pinned in Phase 0 check #5) | MODIFY | +~50 |
| `src/notification/mailer.service.ts` | MODIFY | +~60 |
| `test/fixtures/recipient-resolution-vectors.json` | CREATE | ~250 |
| `src/notification/recipient-resolution/__tests__/recipient-resolution.service.spec.ts` | CREATE | ~350 |
| `src/scheduler/__tests__/drr-integration.spec.ts` | CREATE | ~300 |

### exhibitor-backend-api / external-api-service / pulse-broker-service (mirrors only)

| File | Action | ~Lines |
|------|--------|--------|
| `exhibitor-backend-api/prisma/schema.prisma` | MODIFY (then `db push`) | +~15 |
| `external-api-service/prisma/schema.prisma` | MODIFY (then `db push`) | +~15 |
| `pulse-broker-service/prisma/schema.prisma` | MODIFY (then `db push`) | +~15 |

---

## Public API Contract

### Caller Contract

The engine resolves **typed recipient entries** against a **caller-supplied context**. It never guesses context: a token whose `requiredContext` key is absent resolves to an unresolved entry (skip-and-log), never an error. It never sends, never writes logs — consumers own dispatch and audit writes. It is deterministic for a frozen DB state (stable `orderBy` in every resolver). It never throws for data conditions; it throws only for programmer errors (unknown `kind`, `destination:'phone'` before the SMS release).

### Exported Symbols (identical in both repos — conformance-vector enforced, DD-2)

- `RecipientResolutionService`
  - `resolve(input: ResolveInput): Promise<ResolutionResult>` — the single entry point for all three consumers.
  - `parseChannelConfig(raw: unknown): TypedRecipientFields` — normalizes legacy flat `string[]` and typed entries into `{to[], cc[], bcc[]}` of `RecipientEntry`.
  - `parseScheduleSource(recipient_source: string, replacements_map: Json, anchorKind: AnchorKind): TypedRecipientFields` — the degenerate tier: maps bare-column / one-hop / `FULL_NAME`/`DATE_FMT` forms into engine entries, validated against the per-anchor allow-list (same errors as today).
- `ResolveInput = { fields: TypedRecipientFields; context: ResolutionContext; destination: 'email' | 'phone'; timing: 'live' | 'materialize' | 'dispatch' | 'preview'; trigger: { slug: string; is_transactional: boolean; available_recipient_tokens: string[] } }`
- `ResolutionContext = { orderId?: number; companyId?: number; anchorKind?: AnchorKind; anchorRow?: Record<string, unknown>; anchorInstanceRef?: string }`
- `ResolutionResult = { to: string[]; cc: string[]; bcc: string[]; outcomes: EntryOutcome[]; replacements?: Record<string,string>; zeroRecipients: boolean; disposition: 'PROCEED' | 'SKIP' | 'ABORT' }`
- `EntryOutcome = { field: 'to'|'cc'|'bcc'; entry: string; kind: RecipientKind; resolved: ResolvedDestination[]; outcome: 'resolved'|'skipped'|'failed'; reason?: string }`
- `TOKEN_REGISTRY: Record<string, RecipientTokenSpec>` — code-controlled (DD-3).

### Consumer Responsibilities

- **Scheduler materializer:** call with `timing:'materialize'`; freeze `ResolutionResult` into `recipients_snapshot` (`mode:'snapshot'`); on `disposition:'SKIP'` mark the occurrence SKIPPED with the engine's reason; on `'ABORT'` mark FAILED + raise the S3 alert. For `resolve_at_send=true` rules, store the reference shape instead and **do not** call the engine.
- **Scheduler dispatcher:** `resolve_at_send=false` → replay snapshot verbatim, never call the engine (AC-12). `resolve_at_send=true` → call with `timing:'dispatch'` inside the claim, then map disposition exactly as the materializer does.
- **Admin live send:** call with `timing:'live'` only when `DRR_LIVE_SEND_ENABLED` and template is custom with stored recipients (DD-12); write the `EntryOutcome[]` array into `NotificationLog.recipients` whatever the disposition.
- **Preview:** call with `timing:'preview'`; MUST NOT write NotificationLog or send.
- **All consumers MUST NOT** re-order, re-dedup, or post-filter the compiled lists (the engine output is final), and MUST NOT catch-and-ignore `disposition`.

---

## Substrate Verification (Phase 0)

Run before any implementation step. Halt with `PLAN_BLOCKED` on mismatch — do not improvise.

| # | Check | Command / inspection | Expected | If mismatch |
|---|-------|----------------------|----------|-------------|
| 1 | Scheduling build landed through its Phase 3 | inspect `background-worker-service/src/scheduler/` for the materializer/dispatcher module; `psql: \d notification_schedule_occurrences` | module + table exist with `recipients_snapshot`, `dedupe_key`, `channel` | Phases D2/D3 blocked — re-sequence behind EMS-SCH-BUILD |
| 2 | D2 fix landed | `grep -n "company_id" admin-backend-api/prisma/schema.prisma` (and the other four) | `@@index`, **no** `@unique` on `Exhibitor.company_id`; `Company.exhibitor` one-to-one relation removed/adjusted | Step 1 absorbs D2 per DD-9 contingency; `{all customer contacts}` resolver blocked until then |
| 3 | `channel_config` consumption still absent | `grep -rn "channel_config" admin-backend-api/src --include="*.ts" -l` | hits only in `notification-template/{dto,controller,service}.ts` | A consumption point appeared since research — reconcile DD-12 against it before coding Step 10 |
| 4 | Accepted-invitation status value | `grep -n "invitation_status" exhibitor-backend-api/src/company_user/company_user.service.ts` | the concrete accepted value/enum for `INVITATION_ACCEPTED` | Pin the real value into DD-3's `{all customer contacts}` query — never guess |
| 5 | Exact scheduling-build file names | `ls background-worker-service/src/scheduler/schedule-dispatch/`; `ls admin-backend-api/src/admin/notification-schedule*/dto/` | materializer/dispatcher/service filenames + schedule DTO filename | Update the Files table rows marked "pinned in Phase 0" — plan version bump |
| 6 | #21 slug-path fix present | `grep -n "is_predefined" admin-backend-api/src/common/services/mailer.service.ts` | slug lookup filters/orders on `is_predefined` (fix shipping with scheduling build, plan §5) | Step 10 stays gated OFF (`DRR_LIVE_SEND_ENABLED=false`) — release note; do not ship live consumption |
| 7 | Extension-point signatures | `grep -n "assertPlaceholdersAllowed\|dedupeEmails" admin-backend-api/src/admin/notification-template/notification-template.service.ts` | present at ~`:572-592` / ~`:109-119` | Re-anchor Steps 7/9; verify no signature drift |
| 8 | NotificationLog baseline | `grep -n "email\|channel\|recipients\|notification_template_id" admin-backend-api/prisma/schema.prisma` (NotificationLog block ~`:309-335`) | `email String?` present; `notification_template_id Int` **NOT NULL** FK (`onDelete: Cascade`, ~`:311/:327`) present — pre-existing, not added by Step 1; **no** `channel`/`recipients` columns yet (no one pre-empted the unified migration) | If SMS track already landed the migration: Step 1 shrinks to the DRR-only columns — reconcile with the SMS plan first |
| 9 | Worker schema mirrors resolver models | `grep -n "model Exhibitor\|model User\|model Order" background-worker-service/prisma/schema.prisma` | all three present (~`:937+`) with `sales_person_id`, `user_type`, `invitation_status` | Extend the worker mirror in Step 2 before the engine reads them |
| 10 | Payment-reminder queries unchanged | open `background-worker-service/src/jobs/payment-reminder/payment-reminder.service.ts:63,225-233` | `company.exhibitor` usage + `email`-column dedupe query as researched | Update DD-8/DD-9 impact rows; re-verify AC-16 regression test targets |

---

## Implementation Order

### Summary

| Step | Phase | Primary file(s) | Action | Est |
|------|-------|-----------------|--------|-----|
| 0 | D0 | Substrate Verification + day-one kickoffs | — | 2.0h |
| 1 | D1 | admin migration + `schema.prisma` (unified spine) | CREATE/MODIFY | 8.0h |
| 2 | D1 | 4 sibling `schema.prisma` mirrors + `db push` | MODIFY | 4.0h |
| 3 | D1 | `trigger-event.seeder.ts` (tokens + classification) | MODIFY | 4.0h |
| 4 | D2 | worker `recipient-resolution/` (engine core, 3 files) | CREATE | 16.0h |
| 5 | D2 | scheduler materializer → engine consumer | MODIFY | 8.0h |
| 6 | D3 | dispatcher `resolve_at_send` branch + admin schedule-DTO rejection | MODIFY | 8.0h |
| 7 | D4 | admin DTO typed entries + config-time validators | MODIFY | 10.0h |
| 8 | D4 | admin native engine mirror (3 files) | CREATE | 8.0h |
| 9 | D4 | preview endpoint | MODIFY/CREATE | 4.0h |
| 10 | D5 | admin live-send consumption point (`mailer.service.ts`) | MODIFY | 8.0h |
| 11 | D5 | audit writes: worker + admin mailers → `NotificationLog.recipients`/`channel` | MODIFY | 6.0h |
| 12 | D6 | worker tests (engine + scheduler integration) | CREATE | 12.0h |
| 13 | D6 | admin tests (validation + engine + preview e2e) | CREATE | 10.0h |
| 14 | D6 | conformance vectors (both repos) | CREATE | 4.0h |
| 15 | D6 | rollout smoke: un-gate verification + gate flip | — | 4.0h |
| — | — | Multi-PR coordination buffer (≥5 PRs across 5 repos) | — | 6.0h |
| — | **Total** | | | **122.0h** |

Header `estimate: 122.0h` equals the table sum.

**Sequencing vs the sibling tracks (combined release):**
- **Phase D0 runs on day one**, in parallel with everything: (a) BA/client sessions for DRR-01…DRR-05 + D1/D3/DRR-04-matrix sign-off; (b) unified-migration co-design freeze with the SMS track (DD-8 columns + SMS's channel semantics — ONE migration, agreed before Step 1 is written); (c) **the SMS track's Twilio account + A2P 10DLC registration kickoff (SMS-01)** — owned by 76.8 but listed here because it is the release long pole (days-to-weeks) and DRR's schedule must not become the excuse for starting it late; the provider mechanism itself is CONFIRMED with the client, never assumed (client said "SendGrid"; SendGrid's API is email-only — the A2P SMS product in that family is Twilio Programmable Messaging).
- Phase D1 (schema) lands **with or immediately after** the scheduling build's schema phase, and strictly **before** any SMS dispatch work (M3 sequencing: NotificationLog gains `channel` before any SMS send exists).
- Phases D2/D3 require the scheduling build's materializer/dispatcher (its Phases 1–3) plus the addendum's S1/S3/S6 deltas (retention bounds the snapshot PII the engine writes; S3 provides the abort alert channel; S6 fixes the fail-closed posture the engine mirrors).
- Phases D4/D5 are admin-side and independent of scheduler timing once D1 is in.
- SMS (76.8) consumes the engine only after Phase D3 (interface frozen by AC-19 signature review at end of D2).

### BLOCKED-ON table (steps gated by unanswered questions)

Every gated step **plans and builds the PROPOSED default** (story §labels) so the build starts now; the answer changes only what is listed. OPEN items with no willing default block their step outright.

| Step | Question ID | Blocked what | What changes with the answer |
|------|-------------|--------------|------------------------------|
| 1, 11 | **DRR-10 / DRR-S2** | Final `NotificationLog.recipients` JSON shape + legacy-`email` disposition | Default: DD-8 as written. If BA instead migrates the payment-reminder dedupe query, `email` may stop being populated — Step 11 and the AC-16 regression test change |
| 1, 4 | **D2** | `{all customer contacts}` shipping | Default: fix already landed via the scheduling addendum. If Engineering/BA rejects the drop (keeps `@unique`), FR-8 is unbuildable as specified — `{all customer contacts}` collapses to single-contact semantics; escalate, do not improvise |
| 3 | **DRR-04** (matrix), **D3** (classification) | Concrete per-trigger `available_recipient_tokens` rows + `is_transactional` values in the seeder | Mechanism ships regardless (code-controlled columns + validators); the ~40-trigger matrix and the transactional/marketing split are BA deliverables — seeder rows are placeholders (`[]` / explicit best-guess map flagged `// BA-PENDING`) until delivered; Step 15 will not flip `DRR_LIVE_SEND_ENABLED` with BA-PENDING rows on token-bearing triggers |
| 4 | **DRR-01** | `{salesperson}` resolver | Default: `Order.sales_person_id → User.email`, order-context-only, no strategist/referrer stand-ins. A different source per trigger = new registry resolver entries only |
| 4 | **DRR-02** | `{main/all customer contacts}` membership filter | Default: `user_type=1` / accepted non-deleted rows. A different membership rule = a `where`-clause change + vector update only |
| 4 | **DRR-03** | Gmail-group handling | Default: literal-address model (DD-7). If client picks Directory-API expansion: new resolver for `kind:'gmail_group'`, Google Workspace service-account credentials, group-mirror storage — a materially larger build; re-plan Step 4 scope and estimate |
| 4, 7 | **DRR-11** | Config-time grammar + resolved-but-invalid handling | Default: three tokens + typed entries + RFC 5322 literals only; invalid resolved value → unresolved entry. A looser/stricter grammar = validator + vector changes |
| 4, 7 | **DRR-07** | `kind:'list_ref'` backing sources | **OPEN — no default.** "Admin users / exhibitors" plausibly come from owning modules' listing endpoints; **"other relevant system emails" has no observed backing source anywhere** (base known-issue #4). Step 4/7 ship `list_ref` as a validated kind with **no registered lists** (config-time rejection: "no predefined lists available"); resolvers land when BA names sources |
| 5, 6 | **D1 / DRR-13** | `resolve_at_send` toggle sign-off | Default: build the toggle exactly per DD-5 (external adjudication; BA answer expected = "both, selectable"). If BA rejects the toggle, Step 6 ships dark (column + rejection stays; branch removed) — snapshot remains the only mode |
| 6, 10, 11 | **DRR-06 / D3** | Fallback + zero-recipient policy | Default: per-entry skip-and-log, no default address; zero → never send, marketing skip / transactional abort+alert. A different split changes only the disposition mapping + reason strings |
| 7 | **DRR-17** | Typed entries | Default: DD-4. If BA insists on flat strings: preview/audit/matrix all degrade to convention-parsing — record as accepted debt; normalization migration dropped |
| 9 | **DRR-S1 / DRR-12** | Preview sample-context mechanism + privacy gate | Default: DD-14 (admin-picked recent anchor id, template-edit permission). A stricter privacy posture adds a guard, nothing structural |
| 10 | **DRR-05** | Live-send authoritative source | Default: DD-12 (custom = stored config authoritative, no merge; predefined out of scope). If BA picks merge or predefined-in-scope: Step 10 re-planned — merge semantics are a re-design, not a tweak (double-send/dropped-recipient risk) |
| 10 | **DRR-08** | Dedup rule | Default: DD-10 (TO>CC>BCC, case-insensitive). Client variation = one compile-step function + vectors |
| 4 (interface), 15 | **DRR-09 / SMS-01** | Phone destination enablement | Default: interface seam only (DD-11), `'phone'` rejected. SMS ownership answer + provider confirmation flip the guard in the SMS plan, not here; SMS-01 kickoff is Phase D0 day-one |
| — (scope adds, no step blocked) | **DRR-15** | FROM/CC/BCC tokens | Baseline TO-only ships. If client confirms CC/BCC tokens: extend field iteration in Step 4/7 (same engine, no new machinery). FROM tokens recommended against (collides with `AllowedFromDomain`, `notification-template.service.ts:599-610`) |
| — (scope adds, no step blocked) | **DRR-16** | Vendor-from-show-details source | Not built. If confirmed: a fourth registry entry reading `Shows.venue_manager_emails` (comma-joined VarChar(500), `schema.prisma:2535`), `gsc_decorator_contact_email :2540`, `elctrician_contact_email :2550` — registry + matrix + vectors only |

### Detailed Steps

#### Step 0: Phase D0 — substrate + day-one kickoffs

**Action:** run the Substrate Verification table; log results into the plan (version bump on drift). Convene the unified-migration co-design freeze with the SMS track (DD-8 is the DRR proposal going into that meeting). Confirm the SMS track has opened SMS-01 with the client and kicked off Twilio/A2P 10DLC provisioning **today**. Send the BLOCKED-ON table's BA/client items (DRR-01…05, D1/D3, DRR-04 matrix) as the session agenda.
**Idempotency:** safe.

#### Step 1: Unified spine migration — `admin-backend-api/prisma/migrations/<ts>_ems_unified_notification_spine/migration.sql` + `prisma/schema.prisma`

**Action:** CREATE migration + MODIFY schema. Admin owns migrations; the other four mirror via `db push` (Step 2).

**Columns (per DD-5/DD-6/DD-8; all Int FKs, no new BigInt):**

- `notification_logs`: `channel NotificationChannel NOT NULL DEFAULT 'EMAIL'`; `recipients JSONB NOT NULL DEFAULT '[]'`. **Nothing else** — `email String?` untouched, and the existing `notification_template_id Int` NOT NULL FK (`onDelete: Cascade`, schema `:311/:327`) is **not** touched (it already exists; adding it would fail with a duplicate-column error — DD-8).
- `notification_schedules`: `resolve_at_send BOOLEAN NOT NULL DEFAULT false`.
- `trigger_events`: `available_recipient_tokens JSONB NOT NULL DEFAULT '[]'`; `is_transactional BOOLEAN NOT NULL DEFAULT false`.
- **Data normalization (DD-4):** one-off SQL over `notification_templates.channel_config` for custom EMAIL rows — wrap each flat string in `to_recipients`/`cc_recipients`/`bcc_recipients` as `{"kind":"literal","value":<string>}` (jsonb transform; skip rows already typed — makes the statement idempotent).
- **Contingency (BLOCKED-ON → D2):** if Phase 0 check #2 failed, prepend the D2 fix here exactly per the scheduling addendum's D2 section (drop the never-materialized `@unique` intent, keep/ensure `idx_exhibitors_company_id`) and patch `payment-reminder.service.ts:63` off the `Company.exhibitor` one-to-one.

**Backfill posture:** every new column is NOT NULL with a correct default (existing rows: all-EMAIL, empty audit array, no tokens, marketing) — zero-downtime, no table rewrite beyond defaults. No fabricated backfill of `recipients` for historical rows (DD-8).

**Downgrade path:** explicit `DROP COLUMN IF EXISTS` in reverse order; the `channel_config` normalization is one-way (documented; rollback = code tolerates both shapes via `parseChannelConfig`, so no data rollback needed).
**Migration coordination:** apply by explicit migration name on the shared dev DB, never blind `deploy` from a feature branch mid-collision (dev-collision precedent).
**Idempotency:** destructive — recover by rolling back the migration record before re-running.

#### Step 2: Sibling schema mirrors — 4 × `prisma/schema.prisma`

**Action:** MODIFY worker/exhibitor/external/pulse schemas with the same model changes (NotificationLog + TriggerEvent + notification_schedules where mirrored), then `prisma db push` per repo (their standing rule). Verify worker's Exhibitor/User/Order models carry every field the resolvers read (Phase 0 check #9); pulse mirrors models only (no mail machinery — `src/` has none).
**Idempotency:** safe (`db push` is convergent).

#### Step 3: Trigger catalog — `admin-backend-api/src/database/seeds/trigger-event.seeder.ts`

**Action:** MODIFY. Add per-slug `available_recipient_tokens` (the DRR-04 mechanism: a token is offerable only where the trigger context structurally carries its `requiredContext` — `{salesperson}` → order-context slugs; `{main/all customer contacts}` → company-context slugs) and explicit `is_transactional` per slug (D3). Until the BA matrix lands, rows are `[]` / best-guess flagged `// BA-PENDING` (BLOCKED-ON → DRR-04/D3). Add a seeder unit test asserting every seeded slug has an explicit entry in the classification map (DD-6). No admin CRUD for either column — code-controlled, mirroring `available_placeholders`.
**Idempotency:** safe (seeder upserts).

#### Step 4: Engine core — `background-worker-service/src/notification/recipient-resolution/` (3 files)

**Action:** CREATE `recipient-resolution.types.ts`, `token-registry.ts`, `recipient-resolution.service.ts` per the Public API Contract.

**Algorithm (the compile pipeline, all consumers):**
1. **Parse** — `parseChannelConfig` / `parseScheduleSource` → `TypedRecipientFields` (degenerate tier included, DD-1).
2. **Validate offerability** — `token` entries checked against `trigger.available_recipient_tokens` (send-time re-check of the config-time gate; a stale template with a now-unoffered token → unresolved entry, reason `"token not offered by trigger"`).
3. **Resolve per entry** — registry resolvers (DD-3 queries); `literal`/`gmail_group` pass through; `list_ref` → registered list resolver (none in this release — BLOCKED-ON → DRR-07); `anchor_column`/`anchor_hop`/transforms → existing allow-list semantics with unchanged null-handling (null replacement column → `''`; null recipient source → SKIP, joining the scheduler's vocabulary and standardizing the previously-unquoted reason as `"recipient source resolved null"`).
4. **Project destination** — `destination:'email'` now; null/empty projection → unresolved (DD-11 fail-closed).
5. **Post-validate** — every resolved value RFC 5322-checked; invalid → unresolved entry, reason `"invalid resolved address"` (FR-14/AC-9); never handed to the provider.
6. **Compile + dedup** — flatten, within-field dedup, cross-field TO>CC>BCC case-insensitive (DD-10).
7. **Disposition** — zero valid recipients across all fields → `SKIP` (marketing) / `ABORT` (transactional) per `trigger.is_transactional` (DD-6); else `PROCEED`. Outcomes array always returned in full.

**Constants:** `MAX_RESOLVED_RECIPIENTS_PER_FIELD = 50` (mirrors `ArrayMaxSize(50)`, `notification-template.dto.ts:81-97`; `{all customer contacts}` overflow → entries beyond cap unresolved with reason `"recipient cap exceeded"` — deterministic by the `orderBy`).
**Do NOT:** call any mailer, write NotificationLog, read `ppl_settings`, or catch disposition internally.
**Idempotency:** safe (pure reads).

#### Step 5: Materializer becomes a consumer — `background-worker-service/src/scheduler/schedule-dispatch/` (materializer service, Phase 0-pinned filename)

**Action:** MODIFY. Replace the inline `recipient_source`/`replacements_map` resolution with `engine.resolve({ timing:'materialize', … })`; freeze results into `recipients_snapshot` (`mode:'snapshot'`); map dispositions to the existing occurrence statuses (SKIPPED with engine reason / FAILED + S3 alert). Remove the token-defer SKIP for tokens the registry now resolves — occurrences that previously SKIPPED `"recipient requires DRR (#3)"` begin resolving (AC-15); the SKIP remains only for genuinely unregistered token specs (e.g. the historical `{all_speaker_email_addresses}` — story §8). For `resolve_at_send=true` rules, store the reference shape (`mode:'reference'`, DD-5) without calling the engine. Config-time and materialize-time validation both survive (AC-18) — the engine *is* the materialize-time validator now.
**Implementation notes (verify before coding):** confirm the inline resolver's exact null-handling reasons before deleting it — the engine must emit byte-identical SKIP reasons for the pre-existing cases (regression contract).
**Idempotency:** caution (MODIFY on in-flight scheduling code — coordinate the PR with the scheduling track).

#### Step 6: Dispatcher branch + config-time rejection — dispatcher service (worker) + schedule DTO (admin)

**Action:** MODIFY both.
- Worker dispatcher: exactly one branch — `if (rule.resolve_at_send) → engine.resolve({ timing:'dispatch', … })` from the occurrence's reference shape, inside the existing claim; `else` replay snapshot verbatim (no engine call — AC-12). Dispositions map as in Step 5. Reference-shape occurrences inherit S1 retention unchanged (the reference contains entry specs + ids, less PII than a snapshot — a bonus, not a licence to extend retention).
- Admin schedule DTO/validator: `resolve_at_send=true` rejected until this release's capability constant is on; mutually exclusive with tz-accurate/EVENT snapshot semantics (AC-14, DD-5).
**Idempotency:** caution.

#### Step 7: Admin config-time surface — `notification-template.dto.ts` + `notification-template.service.ts`

**Action:** MODIFY. Replace `RecipientList()` (`dto:81-97`) with the typed-entry union validator (DD-4 grammar: token-in-registry ∧ token-offered-by-trigger, RFC 5322 for `literal`/`gmail_group`, registered-list for `list_ref`, plain-string → `literal` normalization). Add `assertRecipientEntriesAllowed(trigger, entries)` beside `assertPlaceholdersAllowed` (`service:572-592`) — rejects a token the trigger's `available_recipient_tokens` does not expose, with an error naming the trigger (AC-2). Extend `dedupeEmails` usage so `to_recipients` gains within-field dedup (FR-17). Predefined rows: the `PREDEFINED_EDITABLE_CONFIG_KEYS` matrix (`service:94-99`) is untouched — no dynamic-token affordance on predefined templates (AC-4).
**Do NOT:** loosen FROM validation — `AllowedFromDomain` enforcement (`service:599-610`) stands; FROM tokens are out of scope (BLOCKED-ON → DRR-15).
**Idempotency:** caution.

#### Step 8: Admin native engine mirror — `src/common/services/recipient-resolution/` (3 files)

**Action:** CREATE — same three files, same exported symbols, same semantics as Step 4 (DD-2), header-commented as the mirror. Registered in the common providers module beside `MailerService`. Uses admin's Prisma client; queries identical.
**Idempotency:** safe.

#### Step 9: Preview endpoint — `notification-template.controller.ts` (+ service method)

**Action:** MODIFY controller: `POST /admin/notification-templates/:id/recipient-preview`, body `{ context_type: 'order'|'company', context_id: number }`, guarded by the existing template-edit permission (DD-14). Service method loads the template + trigger, builds `ResolutionContext` from the chosen record, calls the mirror engine with `timing:'preview'`, returns `{ to, cc, bcc, outcomes, disposition }`. 404 on unknown context id; 422 on a context type the trigger doesn't match.
**Error mapping:** `NOT_FOUND` → 404; validation → 422; permission → 403 (existing guard).
**Idempotency:** safe (read-only by contract).

#### Step 10: Live-send consumption point — `admin-backend-api/src/common/services/mailer.service.ts`

**Action:** MODIFY `sendFromTemplate` per DD-12: add optional `context?: { orderId?: number; companyId?: number }` to its options; behind `DRR_LIVE_SEND_ENABLED`, custom templates with stored recipient entries resolve via the mirror engine (trigger row loaded for tokens/classification); compiled `{to,cc,bcc}` passed to `sendMail` (which already supports cc/bcc, `:85-144`); `disposition:'SKIP'|'ABORT'` → no send, NotificationLog row written with outcomes + reason, `ABORT` additionally alerts (S3 channel). Legacy behavior for predefined templates and custom templates without stored recipients is byte-identical. Call sites are **not** all retrofitted with context in this release — only order-scoped sites that already have `orderId` in hand (`order-actions.service.ts:703/993`, `order-notification.service.ts` chain) pass it; others resolve tokens to unresolved (FR-15) until follow-up wiring.
**Do NOT:** merge caller-`to` with stored config (FR-13 rejects merge), or touch exhibitor/external/worker `sendFromTemplate`.
**Idempotency:** caution.

#### Step 11: Audit writes — worker `src/notification/mailer.service.ts` + admin `mailer.service.ts`

**Action:** MODIFY both mailers' NotificationLog writes (worker PENDING-then-update path `:126-183`; admin post-attempt path `:244-256`): populate `channel` (from template) and `recipients` (the `EntryOutcome[]`; for non-engine sends, a single synthetic `{field:'to', kind:'literal', outcome:'resolved'}` entry per address so the column is uniformly meaningful), and keep `email` = first TO recipient (DRR-S2 — worker `:129` behavior preserved by design, now explicitly first-TO). `notification_template_id` is **already populated on every write today** (worker `:128`, admin `:246`) — no change to it. No update/delete surface added (AC-16 immutability).
**Idempotency:** caution.

#### Step 12: Worker tests — engine spec + scheduler integration spec

CREATE per the Tests section. Includes the AC-15 un-gate integration test and the AC-12 no-re-resolution regression.

#### Step 13: Admin tests — validation spec, engine mirror spec, preview e2e

CREATE per the Tests section.

#### Step 14: Conformance vectors — `test/fixtures/recipient-resolution-vectors.json` (both repos)

**Action:** CREATE one canonical vector file (≈30 cases: every kind × resolved/unresolved/invalid, dedup collisions, zero-recipient both classifications, degenerate-tier forms, destination-projection nulls, cap overflow) committed **identically** to both repos; each repo runs a table-driven conformance spec over it. Drift between mirrors = failing test (DD-2 enforcement).

#### Step 15: Rollout smoke + gate flip — Phase D6

**Action (ordered rollout):**
1. Deploy Phases D1–D3 (schema + engine + scheduler consumption) with `DRR_LIVE_SEND_ENABLED=false` — scheduled path un-gates first (lowest risk: those occurrences were SKIPPING before; worst case they SKIP again with a clearer reason).
2. Staging smoke: AC-15 (previously-SKIPPED schedule now dispatches), AC-12 (default rule unchanged), AC-13 (`resolve_at_send` reassignment scenario), AC-16 (payment-reminder dedupe unchanged), AC-8 (zero-recipient both branches).
3. Deploy D4/D5; run AC-1…AC-4 config-time + AC-17 preview smoke.
4. Flip `DRR_LIVE_SEND_ENABLED=true` only after: #21 fix confirmed deployed (Phase 0 check #6 re-run against the deployed build) **and** no `// BA-PENDING` rows remain on token-bearing triggers (BLOCKED-ON → DRR-04).
**Rollback:** flip `DRR_LIVE_SEND_ENABLED=false` (restores legacy live behavior instantly); scheduler consumption rollback = redeploy prior worker build (snapshot replay is unaffected — additive schema stays, harmless: NOT NULL defaults are inert to old code). The D2 drop and the `channel_config` normalization are one-way (documented in Step 1); no rollback re-adds `@unique` (the data is legitimately multi-row).

---

## Tests

**Total: ~66 tests across 6 files** (counts finalized at implementation; ranges below are minimums).

| File | Count | Coverage |
|------|-------|----------|
| worker `recipient-resolution.service.spec.ts` | 22 | parse, registry resolvers, grammar, dedup, disposition, destination projection, degenerate tier |
| worker `drr-integration.spec.ts` | 12 | materializer/dispatcher consumption, D1 toggle, un-gate, audit rows |
| admin `recipient-resolution.service.spec.ts` | 10 | mirror parity subset + admin-specific wiring |
| admin `recipient-validation.spec.ts` | 12 | DTO grammar, offerability, normalization, predefined matrix untouched |
| admin `recipient-preview.e2e.spec.ts` | 6 | endpoint contract, permission, side-effect-freedom |
| conformance vectors spec (per repo, table-driven) | 2×~30 rows counted as 2 | mirror-drift enforcement (DD-2) |

**Side-effect boundaries:** all provider sends mocked (SendGrid client stubbed — no live network); DB via each repo's existing test database harness; time frozen where `sent_at` windows matter (payment-reminder regression); no writes outside test schema. No real Google/Twilio calls anywhere (Twilio is not in this atom at all).

### worker `recipient-resolution.service.spec.ts` (22)

**TestParse (4):**
- `parses legacy flat string[] as literal entries` — `["a@b.co"]` → `{kind:'literal'}`; typed entries pass through unchanged.
- `parseScheduleSource maps bare column, one-hop, FULL_NAME and DATE_FMT into engine entries` — CART/ORDER/PAYMENT_TRANSACTION allow-list rows accepted; anything else rejected with the existing error text (AC-18).
- `rejects unknown kind` — programmer-error throw, not a data outcome.
- `rejects destination phone in this release` — guard throw (DD-11).

**TestTokenResolvers (7):**
- `salesperson resolves Order.sales_person_id → User.email` (AC-5 data shape).
- `salesperson null column → unresolved entry, not error` (AC-6 pre-shape).
- `salesperson without orderId context → unresolved with "token not offered/context missing" reason`.
- `main customer contact = user_type 1, deleted_at null, exactly one` (AC-7a).
- `all customer contacts = primary + accepted invited only` — fixture: 1 primary + 2 accepted + 1 revoked + 1 soft-deleted → exactly 3 (AC-7b).
- `all customer contacts deterministic order` — stable `orderBy` proven by repeated runs.
- `cap overflow marks entries beyond 50 unresolved with reason`.

**TestCompile (6):**
- `cross-field dedup keeps highest field TO>CC>BCC, case-insensitive` (AC-10).
- `within-field TO dedup collapses duplicates` (AC-10b).
- `gmail_group passes literal through, outcome kind recorded` (AC-11).
- `resolved-but-invalid address → unresolved, never in output` (AC-9).
- `null phone/email projection → unresolved (fail-closed)` (DD-11).
- `outcomes array covers every configured entry exactly once`.

**TestDisposition (5):**
- `zero recipients + marketing trigger → SKIP with reason "zero recipients — skipped (marketing)"` (AC-8a).
- `zero recipients + transactional trigger → ABORT with reason "zero recipients — aborted (transactional)"` (AC-8b).
- `partial resolution proceeds with remaining valid recipients` (AC-6).
- `null recipient source (degenerate tier) → SKIP "recipient source resolved null"` — matches pre-existing scheduler semantics.
- `PROCEED when ≥1 valid recipient in any field`.

### worker `drr-integration.spec.ts` (12)

- `materializer snapshots engine output into recipients_snapshot mode:snapshot` — shape `{to[],cc[],bcc[],replacements,…}` unchanged for column/one-hop rules (backward compat).
- `pre-existing bare-column rule produces byte-identical snapshot vs pre-refactor fixture` (AC-18 regression).
- `token-recipient schedule that formerly SKIPPED "recipient requires DRR (#3)" now materializes resolved` (AC-15).
- `unregistered token spec still SKIPs with the same reason` (speaker-token case, story §8).
- `resolve_at_send=false dispatch replays snapshot verbatim, engine spy not called` (AC-12).
- `resolve_at_send=true occurrence stores mode:reference and resolves at dispatch` (AC-13a).
- `salesperson reassigned between materialize and fire → dispatch reaches the new user` (AC-13b).
- `resolve_at_send=true rejected by config until capability flag on; mutually exclusive with tz-accurate semantics` (AC-14).
- `zero-recipient at dispatch: marketing → occurrence SKIPPED; transactional → FAILED + alert spy called` (AC-8 scheduled path).
- `NotificationLog row carries channel, notification_template_id, recipients outcomes, email=first TO` (AC-16a).
- `payment-reminder dedupe query returns identical rows before/after migration fixture` (AC-16b).
- `no NotificationLog mutation API exists for recipients/channel` — enforcement grep-style test (AC-16c).

### admin `recipient-validation.spec.ts` (12)

- `all six entry kinds save and persist typed on an all-token trigger` (AC-1).
- `plain string normalizes to kind:literal on write` (DD-4).
- `token not exposed by trigger rejected at save, error names the trigger` (AC-2).
- `raw-typed {salesperson} on an orderless trigger rejected` (AC-2b).
- `free text failing grammar rejected` (AC-3).
- `list_ref rejected while no lists registered` (DRR-07 stance).
- `predefined template edit offers no token affordance; PREDEFINED_EDITABLE_CONFIG_KEYS matrix unchanged` (AC-4).
- `RFC 5322 enforced on literal and gmail_group values`.
- `FROM field rejects tokens; AllowedFromDomain enforcement intact` (DRR-15 baseline).
- `cc/bcc keep literal-only baseline` (FR-4).
- `to_recipients within-field dedup on write` (FR-17).
- `existing stored template normalization migration output shape verified against fixture`.

### admin `recipient-resolution.service.spec.ts` (10)

Mirror-parity subset: the 5 highest-risk vector families re-run natively (token resolvers ×3, dedup, disposition) + admin wiring (Prisma client injection, trigger loading) ×5.

### admin `recipient-preview.e2e.spec.ts` (6)

- `preview returns compiled to/cc/bcc + per-entry outcomes for a real order context` (AC-17a).
- `preview sends nothing and writes no SENT NotificationLog row` (AC-17b).
- `403 without template-edit permission` (FR-23).
- `404 unknown context id; 422 mismatched context type`.
- `would-skip reasons surfaced for null salesperson`.
- `preview of a resolve_at_send rule shows dispatch-time semantics note` (informational field).

### Conformance vector spec (both repos)

- `every vector row: input → expected ResolutionResult deep-equal` — same file, both repos; a mirror drift fails exactly one repo's suite, pinpointing the divergence (DD-2).

### Tests Deferred to the SMS track (76.8)

| Test | Reason |
|------|--------|
| `destination:'phone' projection semantics` | Guard-clause rejection is tested here; real phone resolution ships with 76.8 (FR-21 boundary) |
| Provider idempotency / duplicate-SMS after reaper reset | SMS-plan scope (scheduling contract §(c) note) |

---

## Backward Compatibility

**Existing contract preserved:**
- Scheduler default path: `resolve_at_send=false` (every existing and new-by-default rule) replays snapshots verbatim — pre-existing scheduling tests pass unmodified; snapshot JSON shape for column/one-hop rules is byte-identical (AC-12/AC-18).
- `NotificationLog.email` still populated (first TO) — the payment-reminder dedupe query (`payment-reminder.service.ts:225-233`) returns unchanged results (DRR-S2; regression-tested).
- All new columns NOT NULL with inert defaults — old code reading these tables is unaffected; sibling repos that haven't `db push`-ed yet keep working (columns invisible to their Prisma clients until mirrored).
- Admin template API accepts the legacy flat `string[]` recipient shape (normalized on write) — no FE breakage window (DD-4).
- Predefined templates: zero behavior change anywhere (AC-4; DD-12 branch is custom-only).
- Worker/exhibitor/external `sendFromTemplate` signatures untouched.

**Deprecations:**
- Flat-string recipient entries in `channel_config` — accepted at the API, no longer stored (normalized); remove union acceptance after the FE ships chips UI (follow-up wiring, tracked in Deferred).

**One-way changes (documented, not reversible):** the D2 `@unique` drop (data is legitimately multi-row) and the `channel_config` typed normalization (old readers must go through `parseChannelConfig`, which tolerates both shapes indefinitely).

---

## Security Considerations

- **No expression DSL, no eval** — inherited and preserved: token specs are code-registered functions; admin input is data validated against closed grammars (DD-1/DD-3). Any PR introducing string-evaluated resolution fails review by decision.
- **PII in occurrence rows** — resolved addresses in `recipients_snapshot` are time-boxed by the scheduling addendum's S1 retention purge (archive-to-NotificationLog first); the engine must not assume snapshots persist (story §6.4). Reference-mode rows carry specs + ids, less PII than snapshots.
- **Preview exposure (DRR-12)** — preview resolves live customer/salesperson addresses; gated by the existing template-edit permission; if the client requires a stricter gate it lands in the preview guard + config endpoints only (BLOCKED-ON → DRR-12). Preview responses are not persisted.
- **Audit immutability** — `NotificationLog` resolution outcomes have no update/delete API (AC-16); enforcement test in Step 12.
- **RFC 5322 post-validation** — no resolved value reaches the provider unvalidated (AC-9); malformed stored data cannot be injected into SMTP headers via recipient fields.
- **FROM stays whitelisted** — `AllowedFromDomain` enforcement untouched; FROM tokens rejected (DRR-15 baseline), so resolved addresses can never spoof the sending domain.
- No new secrets, no new external integrations in this atom (Gmail groups are literal addresses; Google credentials explicitly avoided under DD-7).

---

## Deferred

- **SMS recipient resolution + dispatch** — owned by 76.8; this atom ships the `destination` seam only (DD-11). Revisit trigger: SMS plan Phase for gate-flip, after SMS-01 confirmation.
- **Google Workspace Directory expansion for Gmail groups** — excluded under DD-7; in-scope only if the client picks expansion at DRR-03 (re-plan Step 4).
- **`list_ref` backing resolvers** — shipped as a validated-but-empty kind; lands when BA names sources (DRR-07; base known-issue #4 for "other relevant system emails").
- **FROM/CC/BCC token extension** — DRR-15 client decision; CC/BCC = field-iteration extension of the same engine; FROM recommended against.
- **Vendor-from-show-details source** — DRR-16 client decision; would be a fourth registry entry (BLOCKED-ON table row).
- **Retrofitting context into every admin live call site** — Step 10 wires order-scoped sites only; remaining sites resolve tokens to unresolved until wired. Owner: follow-up wiring task in the same epic, threshold-eligible (≥5h) once the DRR-04 matrix names which triggers actually carry tokens.
- **Removing the flat-string API union** — after the FE chips UI ships (Backward Compatibility note).
- **Consent/opt-out modelling** — no consent model exists in any schema; 2026 SMS-compliance scoping (review M2) belongs to the SMS plan.
- **Predefined-template recipient resolution** — retired variant (DRR-14 settled); revisit only if DRR-05 answer flips it.

---

## Cross-Cutting Impact Ledger

| Affected atom / module | What it consumes | Change | Disposition | Verification |
|------------------------|------------------|--------|-------------|--------------|
| Scheduling build (76.6/77.8) materializer/dispatcher | inline `recipient_source`/`replacements_map` resolver | replaced by engine calls (Steps 5/6) | **Update-in-this-plan** | byte-identical snapshot regression + full scheduler suite |
| Scheduling occurrence pipeline | `recipients_snapshot` shape | additive `mode` discriminator; reference variant | No-op for `mode:'snapshot'` readers (default absent = snapshot) | AC-12 test |
| SMS track (76.8) | the engine + unified migration | `channel` column + `destination` seam delivered | No-op here — SMS consumes later (M4 sequencing) | AC-19 signature review |
| Worker `mailer.service.ts` NotificationLog writes | `email` single-address logging (`:129`) | + `recipients`/`channel` (`notification_template_id` already written, `:128`); `email` = first TO | Update-in-this-plan (Step 11) | AC-16 tests |
| Admin `mailer.service.ts` + its ~15 call sites | `sendFromTemplate(to: string, …)` | optional `context`; gated custom-template branch | No-op for callers (optional param; gate default off) | legacy-path byte-identical test |
| `payment-reminder.service.ts` | `email`-column dedupe query (`:225-233`); `Company.exhibitor` (`:63`) | none by default; `:63` patched only under the DD-9 contingency | No-op (protected by DRR-S2) / update-in-this-plan (contingency) | AC-16b regression |
| Admin notification-template CRUD + FE | flat `string[]` recipients | typed entries; union accepted | Accepted transitional change — Backward Compat | AC-1 + normalization tests |
| exhibitor/external/pulse repos | shared DB models | schema mirror only (`db push`) | No-op (columns inert to their code) | `db push` diff clean; their suites green |
| `EMAIL_SMS_KNOWN_ISSUES.md` register | #3 (DRR deferred), #2, #21, #4 | #3 flips to delivered on ship | Follow-up: register is user-frozen — proposed edit delivered to the user, applied by the user (M1 precedent) | n/a (process) |

---

## Post-Atom Checklist

1. Registry/tracker — EMS-779-DRR marked complete + date; Jira story (branch-carried SBE key) DEV DONE with routes-only endpoint table (preview endpoint) per the close-out convention.
2. Aggregate counts — five repos' live lint/test counts match Quality Gates records.
3. Changelog — `EMAIL_SMS_API_CHANGELOG.md` entry proposed to the user (preview endpoint; DTO union; NotificationLog columns) — user applies (docs are user-committed).
4. Plan archived — this file's metadata `status` advanced; BLOCKED-ON rows annotated with answered/unanswered state.
5. Commit + push — **performed by the user per repo** (standing convention: the user reviews and commits everything; this plan introduces no commits).
6. Known-issues follow-through — proposed register updates (#3 delivered; #4 unchanged; #21 interaction note) handed to the user.
7. Combined-release sync — confirm the SMS plan's Substrate Verification now expects the landed unified migration (its check mirrors Phase 0 check #8 inverted).

---

## Quality Gates

- All five repos: lint, typecheck, unit + integration suites green (`~66` new tests passing; zero pre-existing failures introduced).
- Bitbucket Pipelines green ×5 (gitleaks → lint/typecheck/test → SonarQube) — `./scripts/check-pipelines.sh`.
- SonarQube quality gate green on new code ×2 code-bearing repos (admin, worker); zero new-code issues authored by this change — `./scripts/check-sonar.sh <repo> --issues` (READ-ONLY).
- Migration applies cleanly on a disposable DB; `db push` diff-clean on the four mirrors.
- No new BigInt PKs; every new column NOT NULL-with-default — no nullable exceptions (`notification_template_id` already exists NOT NULL and is not touched, DD-8).
- Gate Contract grep: zero inline recipient parsing outside `recipient-resolution/`.
- Conformance vectors: both repos pass the identical file.

---

## Verification

```bash
cd /Users/uipl/Desktop/uipl/sbe/APIs

# 1. Migration + mirrors (disposable DB first, then shared dev by explicit name)
(cd admin-backend-api && npx prisma migrate deploy)                  # Expected: <ts>_ems_unified_notification_spine applied
for r in background-worker-service exhibitor-backend-api external-api-service pulse-broker-service; do
  (cd "$r" && npx prisma db push)                                    # Expected: "already in sync" after mirror edit
done

# 2. Column + drift checks
psql "$DATABASE_URL" -c "\d notification_logs"                        # Expected: channel (not null, default EMAIL), recipients (jsonb, default []); notification_template_id integer NOT NULL (pre-existing, unchanged)
psql "$DATABASE_URL" -c "\d notification_schedules" | grep resolve_at_send   # Expected: boolean not null default false
psql "$DATABASE_URL" -c "\d trigger_events" | grep -E "available_recipient_tokens|is_transactional"  # Expected: both present
psql "$DATABASE_URL" -c "\d exhibitors" | grep company_id             # Expected: plain index idx_exhibitors_company_id, NO unique

# 3. No-second-resolver gate
grep -rn "recipient_source" background-worker-service/src/scheduler/ | grep -v recipient-resolution   # Expected: no parsing hits (imports only)

# 4. Suites
(cd background-worker-service && npm test -- recipient-resolution)    # Expected: engine spec + conformance vectors pass
(cd background-worker-service && npm test -- drr-integration)         # Expected: 12 passed (incl. AC-12/AC-13/AC-15)
(cd admin-backend-api && npm test -- recipient)                       # Expected: validation + mirror + preview suites pass
(cd background-worker-service && npm test && cd ../admin-backend-api && npm test)   # Expected: full suites, 0 failed

# 5. Preview smoke (staging)
curl -s -X POST "$ADMIN_API/admin/notification-templates/<id>/recipient-preview" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"context_type":"order","context_id":<orderId>}'                # Expected: {to,cc,bcc,outcomes,disposition}; no new SENT NotificationLog row

# 6. Un-gate smoke (staging): pick a schedule whose occurrences show reason "recipient requires DRR (#3)"
psql "$DATABASE_URL" -c "SELECT status, recipients_snapshot->>'mode' FROM notification_schedule_occurrences WHERE schedule_id=<S> ORDER BY id DESC LIMIT 3"
                                                                      # Expected: new occurrences PENDING/SENT with mode snapshot (not SKIPPED)

# 7. Payment-reminder regression (fixture DB)
psql "$TEST_DATABASE_URL" -f test/fixtures/payment-reminder-dedupe-before-after.sql   # Expected: identical row sets

# 8. CI + Sonar
./scripts/check-pipelines.sh                                          # Expected: latest pipeline green, all 5 repos
./scripts/check-sonar.sh                                              # Expected: quality gate OK ×5
```

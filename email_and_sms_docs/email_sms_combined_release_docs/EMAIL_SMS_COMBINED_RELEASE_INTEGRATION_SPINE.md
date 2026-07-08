# Email & SMS — Combined Release Integration Spine

**Scheduling (76.6/77.8) + Dynamic Recipient Resolution (77.9) + SMS Provider (76.8) — one release, one spine.**

**DOC 5 of 7 — combined-release doc set** (`email_and_sms_docs/email_sms_combined_release_docs/`)
**Date:** 2026-07-08
**Audience:** the tech lead / release runner. This is the ONE document to read to run all three tracks as a single release; the per-track documents carry the depth.
**Status:** documentation only — no code, no schema change, no commits. The user reviews and commits everything.

### The doc set (reading order for a new joiner)

| Doc | File | Role |
|---|---|---|
| Base plan (READ-ONLY, approved) | `email_sms_scheduling_plan_and_supporting_docs/EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` (Revision 3) | The scheduling build — untouched baseline; externally reviewed, "approve to build, no redesign" |
| 77.9 refined story | `EMAIL_SMS_77.9_DRR_REFINED_STORY.md` | DRR requirements (FR-1…24, AC-1…19, DRR-xx register) |
| 76.8 refined story | `EMAIL_SMS_76.8_SMS_REFINED_STORY.md` | SMS requirements (FR-1…17, AC-1…26, SMS-xx register, §9 un-gating checklist) |
| 77.9 implementation plan | `EMAIL_SMS_77.9_DRR_IMPLEMENTATION_PLAN.md` (EMS-779-DRR) | Builds the shared engine + authors the unified migration (Phases D0–D6, 122h) |
| 76.8 implementation plan | `EMAIL_SMS_76.8_SMS_IMPLEMENTATION_PLAN.md` (EMS-768-SMS) | Builds SMS transport/compliance/webhook + gate flip (Phases A–H, 73h) |
| **This spine (DOC 5)** | `EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md` | Cross-track contract, build order, dependency matrix, release gates, conflict watch |
| Scheduling fixes addendum (DOC 6) | `EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md` | Review deltas (S1–S7, X1–X2, D2) applied with the base plan during the build |

(The DRR plan self-labels "DOC 7 of 7" and the addendum "DOC 6 of 7" — numeric labels across the set are cosmetic and slightly wobbly; the table above, by filename, is the canonical index. See Conflict Watch C6.)

### The release rule, in one paragraph

The scheduler ships a complete materialize → claim → dispatch → log pipeline with a **restricted, allow-listed recipient resolver** whose output freezes into `recipients_snapshot` and replays verbatim (scheduling plan §2.1/§2.2/§4; research contract `scratchpad/research_scheduling_contract.md`). **DRR generalizes that resolver into the one shared engine** (token specs, the D1 `resolve_at_send` reference mode, the D3 zero-recipient policy), with the scheduler as a consumer. **SMS extends the same engine to a phone field** and flips two pre-built gates (the `channel='SMS'` SKIP pass and the `channel==='EMAIL'` assertion in the by-id dispatch path) after the **one unified `NotificationLog` migration** lands. Anything that duplicates the resolver, adds a second occurrence/log table, or resolves recipients outside the engine violates the release constraint. The release **long pole** is external: Twilio account + A2P 10DLC brand/campaign registration (days-to-weeks; carriers block 100% of unregistered 10DLC traffic since Feb 2025) — it starts **day one**, on client confirmation of the mechanism (**SMS-01**: client said "SendGrid", SendGrid's API is email-only; the feasible in-family mechanism is Twilio Programmable Messaging — confirmed, never assumed).

---

## 1. The shared spine, precisely

### 1.1 ONE recipient-resolution engine

#### 1.1.1 The contract

One service — `RecipientResolutionService` — canonical in `background-worker-service/src/notification/recipient-resolution/`, with a conformance-vector-enforced native mirror in `admin-backend-api/src/common/services/recipient-resolution/` (DRR plan DD-2; the cross-repo house rule: no shared npm package, native mirrors to identical semantics, one committed vector fixture run by both repos so drift is a test failure).

**Inputs** (DRR plan, Public API Contract):

- `fields: TypedRecipientFields` — typed entries `{kind: 'literal'|'token'|'gmail_group'|'list_ref', value}` (DRR DD-4), **or** the scheduler's restricted forms via `parseScheduleSource(recipient_source, replacements_map, anchorKind)` — bare anchor column, one documented relation hop, `FULL_NAME`/`DATE_FMT` transforms. The restricted forms are the **degenerate tier of the same engine, not a separate code path** (DRR DD-1; scheduling plan §2.1/§4 items 7/12; review M4).
- `context: ResolutionContext` — `{orderId?, companyId?, anchorKind?, anchorRow?, anchorInstanceRef?}`. The engine never guesses context: a token whose `requiredContext` is absent resolves to an *unresolved entry*, never an error.
- `destination: 'email' | 'phone'` — every token resolver returns `ResolvedDestination {email, phone, ref}`; the compile step projects the requested field, null/empty projection = unresolved (fail-closed, mirroring the S6 posture). **`'phone'` is guard-rejected until the SMS track flips it** (DRR DD-11; the flip is SMS work — see §1.1.2 step 3).
- `timing: 'live' | 'materialize' | 'dispatch' | 'preview'`; `trigger: {slug, is_transactional, available_recipient_tokens}`.

**Outputs:** `ResolutionResult = { to[], cc[], bcc[], outcomes: EntryOutcome[], replacements?, zeroRecipients, disposition: 'PROCEED'|'SKIP'|'ABORT' }` — per-entry outcomes (`resolved|skipped|failed` + reason) always returned in full; compiled lists are final (consumers must not re-order, re-dedup, or post-filter).

**Validation:** two mandatory points, both preserved from the scheduler contract — **config-time** (admin, beside `assertPlaceholdersAllowed`, `admin-backend-api/src/admin/notification-template/notification-template.service.ts:572-592`: token-in-registry ∧ token-offered-by-trigger, RFC 5322 literals, registered `list_ref` only) and **materialize/dispatch-time** (worker: the engine is the materialize-time validator; resolved values RFC 5322 post-validated, invalid → unresolved). No expression DSL, no eval, ever — token specs are code-registered functions (DRR DD-1/DD-3; the review lists this posture under "explicitly right, do not second-guess").

**Error policy:** the engine never sends, never writes logs, never throws for data conditions (throws only for programmer errors: unknown `kind`, `destination:'phone'` pre-flip). Data failures become entry outcomes; zero valid recipients becomes a **disposition** the consumer maps to its own status machinery: marketing/reminder → `SKIP` (reason `"zero recipients — skipped (marketing)"`), transactional → `ABORT` (reason `"zero recipients — aborted (transactional)"` + alert on the S3 channel the addendum establishes). **Never send to zero** (D3; DRR DD-6). Per-entry unresolvable → skip-and-log, **no default-address substitution** (DRR FR-15). The engine joins the scheduler's existing SKIP-reason vocabulary (missed-window, template-inactive, S6 `"unresolvable event timezone"`, …) and adds its own reasons — one vocabulary, never a parallel one (DRR story §6.4).

#### 1.1.2 Who builds which part, in what order

| Order | Part | Builder | Where specified |
|---|---|---|---|
| 1 | Restricted resolver (bare column / one-hop / transforms), snapshot-at-materialize, verbatim replay | **Scheduling track** (already approved; in flight) | Scheduling plan §2.1, §4 items 7/8/12 |
| 2 | **Email DRR** — engine core + token registry (`{salesperson}`, `{main customer contact}`, `{all customer contacts}`, `gmail_group`, `list_ref`), typed entries, config validators, preview, D3 disposition | **DRR track** (EMS-779-DRR Steps 4/7/8/9) | DRR plan DD-1…DD-7, DD-14 |
| 3 | **Scheduler consumes** — materializer/dispatcher inline resolution replaced by engine calls; token-SKIP un-gates; D1 dispatcher branch | **DRR track** (Steps 5/6), coordinated PRs with the scheduling track | DRR plan DD-5; Gate Contract "no second resolver" grep |
| 4 | **SMS extends to phone** — allow-list phone columns (default `Exhibitor.phone`, admin `prisma/schema.prisma:1029`), `destination:'phone'` guard flip, conformance-vector update in **both** repos, snapshot phone destination | **SMS track** (EMS-768-SMS Step F1), after DRR's AC-19 interface freeze | SMS plan DD-3/F1; DRR DD-11; review M4 |

M4 sequencing is binding: **email DRR first → scheduler consumes → SMS extends**. This breaks the 76.8↔77.9 circular reference and is why DRR slipping strands SMS even though DRR needs no provider. Any PR adding recipient parsing outside `recipient-resolution/` fails the DRR Gate Contract grep (`grep -rn "recipient_source" background-worker-service/src/scheduler/ | grep -v recipient-resolution` → no parsing hits).

#### 1.1.3 The D1 `resolve_at_send` toggle — the shared timing contract

Adjudicated by the external review (D1, HIGH) and adopted release-wide; the DRR plan owns the build (DD-5), the scheduler and SMS inherit it identically:

- **Default = snapshot-at-materialize** for every rule, existing and new (`notification_schedules.resolve_at_send Boolean NOT NULL DEFAULT false`). Dispatch replays `recipients_snapshot` verbatim, engine not called (DRR AC-12 — pre-existing scheduler behavior byte-identical).
- **Opt-in freshness:** `resolve_at_send=true` stores a **reference shape** in `recipients_snapshot` (`mode:'reference'`: anchor ref + typed entries + context — no second column) and the dispatcher grows **exactly one branch**: `if (rule.resolve_at_send) → engine.resolve(timing:'dispatch') inside the claim; else replay`.
- **Config-time rejection until DRR ships** (capability constant), and **mutual exclusion** with tz-accurate/EVENT snapshot semantics (the Klaviyo precedent the review cites).
- **SMS variance: none.** SMS rules use the same toggle, same default; phone numbers frozen into snapshots are PII bounded by the S1 retention purge (`schedule_occurrence_retention_days`, default 90) — **neither track may assume snapshots persist** (addendum §1/§7; SMS plan security section).
- Under at-least-once (S2), a reaper-reset re-dispatch with `resolve_at_send=true` may re-resolve to a *different* set — accepted as the freshness semantics the toggle opts into; audit rows record each attempt's actual resolution (DRR DD-13).

Confluence 77.9's "resolve at send time, never config-time values" is satisfied by the toggle plus inline live-trigger resolution — **not** by changing the scheduler default. DRR-13 is carried as adjudicated-pending-BA-sign-off ("both, selectable").

### 1.2 ONE unified `NotificationLog` migration — the single spec

**Name:** `<ts>_ems_unified_notification_spine` (admin-backend-api owns it; the other four repos mirror via `db push` — CLAUDE.md rule). **Execution home: DRR plan Step 1** — co-designed with the SMS track at the Phase D0 freeze, landed **once**. The addendum explicitly adds **no** NotificationLog columns (addendum §0.2, M3 row); the SMS plan explicitly authors **no** log DDL (SMS DD-4, Substrate check #5: a second SMS-specific log migration anywhere = release-constraint violation, halt). **This section is the spec of record both plans reference; neither track ships its own variant.**

**`notification_logs` columns (the M3 + SMS-05 + DRR-10 surface):**

| Column | Type / constraint | Backfill | Serves |
|---|---|---|---|
| `channel` | `NotificationChannel` enum, **NOT NULL DEFAULT 'EMAIL'** | default backfills all existing rows correctly (all historical rows are email) | M3 / SMS AC-18 discriminator |
| `recipients` | `Json NOT NULL DEFAULT '[]'` — array of `{field:'to'\|'cc'\|'bcc', entry, kind, resolved:[{email\|phone, ref?}], outcome:'resolved'\|'skipped'\|'failed', reason?}` | historical rows keep `[]` — **no fabricated backfill**; the legacy single-address fact remains in `email` | DRR-10 per-dispatch resolution audit; `resolved[].phone` records the E.164 SMS destination (SMS FR-11 requirement satisfied) |
| `notification_template_id` (existing) | **already exists — NOT added by this migration**: `Int` **NOT NULL**, FK `onDelete: Cascade` (admin `prisma/schema.prisma:311/:327`), populated on every log write today (worker `mailer.service.ts:128`, admin `mailer.service.ts:246`) | n/a — every historical row already carries its template id | Confluence 77.9 audit "template identifier" — satisfied by the existing column. **Caveat flagged as a DRR-10 sub-decision:** `onDelete: Cascade` deletes log rows when their template is deleted, in tension with the "permanent, non-editable" audit intent; changing it to `SetNull` would be an explicit ALTER + behavior change, decided at the DRR-10 sign-off, never done silently |
| `email` (existing `String?`) | **kept, unchanged, still populated with the first TO recipient** | n/a | **DRR-S2**: the payment-reminder dedupe query filters on `email` + slug + sent-at window (`background-worker-service/src/jobs/payment-reminder/payment-reminder.service.ts:225-233`) and must return identical results before/after — regression-tested (DRR AC-16) |

The same migration also carries the other spine columns (one migration, one deploy): `notification_schedules.resolve_at_send` (§1.1.3 — lands **strictly after** the scheduling Phase-1 migration that creates the table), `trigger_events.available_recipient_tokens Json NOT NULL DEFAULT '[]'` + `is_transactional Boolean NOT NULL DEFAULT false` (DRR-04/D3 mechanism), and the one-off `channel_config` typed-entry normalization (DRR DD-4).

**Settled here (the SMS story FR-12 deferred this to "the unified-migration doc"):** `NotificationLog.status` is `String @db.VarChar(50)`, not an enum — SMS delivery callbacks write **`'DELIVERED'` as a string value; no schema change, no enum migration**. SMS rows use `PENDING → SENT → DELIVERED | FAILED`; terminal statuses are never downgraded (SMS DD-12). Email rows are untouched.

**Not part of this migration (and not a violation of the one-migration rule):** the SMS compliance/webhook tables (`sms_suppressions`, `sms_consent_events`, `twilio_webhook_events` — SMS plan Step D1) are **new tables**, not NotificationLog variants; they land as the SMS track's own admin-owned migration. The one-migration constraint is about the shared audit surface: **exactly one migration touches `notification_logs`** for this release. Likewise the D2 `@unique` drop is its own standalone PR (addendum §10), with a DRR Step-1 contingency absorption if it hasn't landed (DRR DD-9).

**Schema preferences enforced throughout:** Int PKs only (`NotificationLog.id` and the occurrence PK BigInt are the two pre-existing approved exceptions, not propagated); NOT NULL + correct default/backfill over nullable everywhere — no nullable exceptions (`notification_template_id` already exists NOT NULL and is untouched). **Immutability:** no update/delete API for the audit columns anywhere; the only writers are the mailer/SMS send paths and the webhook's status update by `provider_message_id` (DRR AC-16; SMS AC-17/AC-19).

**Verifier greps** (any hit = spine violation):
- exactly one migration folder matching `notification_spine` under `admin-backend-api/prisma/migrations/`, and **zero** other migrations adding columns to `notification_logs`;
- `psql \d notification_logs` → `channel` NOT NULL default `EMAIL`, `recipients` jsonb default `[]`, `notification_template_id` integer **NOT NULL** FK (pre-existing, unchanged), `email` intact.

### 1.3 The materialize-then-SKIP gates — and exactly what un-gates each

The scheduler's deferral mechanism is mechanical, not narrative: occurrences always materialize; query-level gates SKIP them. Un-gating is a send-time flip — **no schema change, no re-materialization**, by design (scheduling plan §4 items 7/10, §7 phase 6).

| Gate | SKIP reason / lever | Un-gated by | Exact un-gate criteria |
|---|---|---|---|
| **Token recipients** | occurrence `SKIPPED "recipient requires DRR (#3)"` (scheduling plan §4 item 7) | **DRR track**, at Phases D2/D3 deploy | Engine + registry deployed to the worker; materializer/dispatcher consuming it (DRR Steps 4–6); occurrences for **registered** token specs then resolve normally (DRR AC-15, staging-proven per the Gate Contract). Unregistered specs (e.g. historical `{all_speaker_email_addresses}`) **stay SKIPPED with the same reason** — the SKIP string is the contract marker. |
| **SMS channel** | separate pass flips `channel='SMS'` PENDING → `SKIPPED "SMS provider not integrated"`; dispatch select filters `channel='EMAIL'` (plan §4 item 10) | **SMS track**, Step H1 (one PR) | SMS story §9 checklist steps 1–6 green, **in order** — SMS-02 confirmed → SMS-01 confirmed → unified migration landed (§1.2) → phone-capable shared resolver shipped (M4) → SMS templates seeded for the confirmed SMS-06 list → compliance substrate live (suppression + quiet hours + SMS-03 recorded) — then the H1 code flip deploys **dark** (remove SKIP pass, widen select, extend the by-id `channel==='EMAIL'` assertion with the `'SMS'` → `SmsService` branch — same by-id path, same log write, #21-immune by construction). The **launch toggle** (row 4 below) needs all eight steps green, including step 7: 10DLC brand+campaign registered + Messaging Service provisioned. |
| **DRR live sends** (custom-template `channel_config` becomes authoritative at dispatch) | env gate `DRR_LIVE_SEND_ENABLED=false` (DRR DD-12) | **DRR track**, Phase D6 step 15.4 | #21 slug-path fix confirmed **deployed** (ships with the scheduling build — a live send resolving the wrong template would resolve the wrong recipient config), **and** no `// BA-PENDING` seeder rows remain on token-bearing triggers (DRR-04 matrix delivered). Rollback = flip the env gate back, instant. |
| **SMS production traffic** | `ppl_settings` `sms_sending_enabled` (**default `'false'`**) — separate from the H1 code flip | **Launch decision** | 10DLC registered + number/Messaging Service provisioned (AC-16 hard gate) + SMS-03 consent decision recorded. A `ppl_settings` edit + SQS invalidate — no deploy. This is also the fastest rollback lever. |

Interlock to respect: the H1 code flip may deploy **dark** (kill switch off ⇒ occurrences log `SKIPPED "sms sending disabled by config"` — observable, harmless; SMS plan Rollout step 3); the *launch* gate is the settings flip, gated on provisioning and consent, never on build completion.

---

## 2. Combined build order

Dependency-ordered milestones across all three tracks. "Blocks" = strictly sequential; "Parallel" = may run concurrently with the named milestones. The addendum's S-fixes ride the scheduling phases exactly as its §0.3 sequences them.

| # | Milestone | Track / owner | Strictly blocked by | Runs in parallel with |
|---|---|---|---|---|
| **MS0** | **Day-one kickoffs:** (a) SMS-01+SMS-02 question pack to client; **on SMS-01 confirmation, Twilio account + A2P 10DLC brand/campaign registration starts immediately — the release long pole**; (b) BA/client session agenda sent (DRR-01…05, D1/D3 sign-off, DRR-04 matrix, SMS-03/06/07/08); (c) unified-migration co-design freeze between DRR and SMS tracks (§1.2 is the agenda); (d) Twilio test credentials + idempotency R&D (SMS A2) | All (SMS A1/A2; DRR Step 0) | — | Everything below — provisioning and BA answers run alongside the entire build |
| **MS1** | **D2 standalone fix** — `Exhibitor.company_id` `@unique` drop, five schemas, `Company.exhibitor` → plural, ~25 call sites; own branch/PR, not bundled into any phase | Scheduling-track addendum §10 | — ("decoupled — do soon") | MS0, MS2 |
| **MS2** | **Scheduling build Phases 1–2** (schema + admin config), with X1 applied at Phase 1 (stop-condition enum ships **without** `CART_CONVERTED`) and the S3 `catchup_policy` column riding the Phase-1 migration if convenient | Scheduling (EMS-SCH-BUILD / EMS-766-SCHED — same atom, two labels; see C3) | — | MS0, MS1 |
| **MS3** | **Unified spine migration** (§1.2) + 4× `db push` mirrors + trigger-catalog seeder scaffold (`available_recipient_tokens`/`is_transactional`, `// BA-PENDING` placeholders) | DRR Steps 1–3 (admin owns; SMS co-signed at MS0c) | MS2 Phase-1 migration (the `notification_schedules` table must exist before `resolve_at_send` ALTERs it); MS1 preferred-landed (else DRR Step 1 absorbs it per DD-9) | MS4-prep, SMS dark build below |
| **MS4** | **Scheduling Phase 3** (executor) + the addendum's before-Phase-3-ships deltas: **S1 retention cron, S6 tz fail-closed**; S2 `FOR UPDATE SKIP LOCKED` claim, S3 per-rule catch-up + alerts, S5/X2 tests during Phase 3/4. Both SKIP gates (token, SMS) now live in production | Scheduling + addendum | MS2 | MS3, MS5 |
| **MS5** | **SMS dark build:** template unlock (C1–C3), compliance substrate migration + service (D1–D2), `SmsService`/render/phone utils (E1–E2), Twilio webhook (G1) — all inert behind not-configured mode + kill switch, tested on Twilio test credentials | SMS | MS3 (unified migration before any SMS send code merges — M3 finding; SMS Step B1 verifies) | MS4, MS6 — this is the release's biggest parallelism win |
| **MS6** | **Email DRR engine + scheduler consumption:** engine core (Step 4), materializer/dispatcher switchover + D1 branch (Steps 5–6 — coordinated PRs with the scheduling track), admin validators/mirror/preview (Steps 7–9), audit writes (Step 11), tests + conformance vectors (Steps 12–14). **Token gate un-gates on deploy; AC-19 signature review freezes the phone seam at end of D2** | DRR | MS3; MS4 (Steps 5/6 need the shipped materializer/dispatcher + S1/S3/S6 deltas) | MS5 |
| **MS7** | **DRR live-send consumption** (Step 10, deployed dark behind `DRR_LIVE_SEND_ENABLED`) + rollout smoke (Step 15.1–15.3) | DRR | MS6; #21 fix deployed (ships with the scheduling build, plan §5) | MS8-prep |
| **MS8** | **SMS phone extension + pipeline:** F1 (allow-list phone columns per SMS-06/07 mapping, `destination:'phone'` guard flip, conformance vectors updated in both repos), E3 dispatcher pre-send pipeline (kill switch → resolve → normalize → suppress → quiet hours → cap → send; see C2), T1 test suites | SMS | MS6 (AC-19 seam frozen; M4 sequencing) | MS7 |
| **MS9** | **Gate flips, in order:** (1) DRR scheduled un-gate proven in staging (AC-15); (2) `DRR_LIVE_SEND_ENABLED=true` (criteria per §1.3 row 3); (3) SMS **H1** code flip (dark — §9 checklist steps 1–6 green); (4) **launch**: `sms_sending_enabled=true` only when 10DLC + provisioning + SMS-03 are green | DRR then SMS | MS7, MS8, and — for (4) only — the MS0 long pole completing | — |

**Critical path:** MS2 → MS4 → MS6 → MS8 → MS9(3). **Schedule-critical but off the code path:** the MS0 Twilio/10DLC long pole gates only MS9(4) — if it starts day one it should finish inside the build window; if it starts late it becomes the release date. **Biggest parallel lanes:** MS5 (SMS dark build) alongside MS4/MS6; MS1 (D2) anytime early; all BA/client sessions (MS0b) alongside everything — every DRR/SMS BLOCKED-ON step builds its PROPOSED default now and re-checks at flip time.

---

## 3. Cross-track dependency matrix

| # | Dependency | Producer | Consumer | Interface (doc §) |
|---|---|---|---|---|
| 1 | Occurrence pipeline (`notification_schedule_occurrences`, dedupe identity, claim/reaper/retry `[5m,30m,2h]`×3, catch-up) | Scheduling | DRR, SMS | Scheduling plan §2.2/§4 item 3; research contract §(c) |
| 2 | By-id `notificationTemplateId` dispatch path (+ #21 immunity) | Scheduling | DRR (live-send safety; scheduled dispatch), SMS (channel branch joins the same path) | Scheduling plan §4 item 9/§5; DRR DD-12; SMS DD-13 |
| 3 | Restricted resolver forms (bare column / one-hop / transforms) as the degenerate tier | Scheduling | DRR engine (`parseScheduleSource`) | Scheduling plan §2.1/§4 items 7/12; DRR DD-1 |
| 4 | SKIP-reason vocabulary (one list; tracks add, never fork) | Scheduling (+ addendum S6) | DRR (adds zero-recipient/unresolved reasons), SMS (adds `"invalid or missing phone number"`, `"sms sending disabled by config"`) | Research contract §(b); DRR story §6.4; SMS DD-7/DD-13 |
| 5 | S1 retention purge — bounds `recipients_snapshot` PII (email **and** phone) | Scheduling addendum §1 | DRR (snapshot/reference lifetime), SMS (phone PII) | Addendum §1/§7; DRR Security; SMS Security |
| 6 | S3 alert channel (warn-level `ApplicationLogService` + aggregate line) | Scheduling addendum §3(c)4 | DRR (D3 transactional abort-and-alert rides it), SMS (D2-step escalation) | Addendum §3; DRR DD-6; SMS Step D2 |
| 7 | S6 fail-closed posture (never guess, SKIP + alert) | Scheduling addendum §6 | DRR (null-projection/fail-closed mirror, DD-11) | Addendum §6; DRR DD-11 |
| 8 | D2 `@unique` drop (five schemas + call sites) | Scheduling-track addendum §10 (standalone PR) | DRR (`{all customer contacts}` hard-requires it) | Addendum §10; DRR DD-9 + Phase 0 check #2 |
| 9 | #21 slug-path fix (`is_predefined` filter + deterministic orderBy, four mailers) | Scheduling (plan §5, ships with the build) | DRR (gate criterion for `DRR_LIVE_SEND_ENABLED`) | DRR DD-12 + Phase 0 check #6 |
| 10 | **Unified spine migration** (§1.2) | DRR Step 1 (admin-owned; SMS co-designed) | SMS (Step B1 hard prerequisite for any send code), Scheduling (log writes gain columns, behavior unchanged), all five repos (`db push`) | This doc §1.2; DRR DD-8; SMS DD-4 |
| 11 | D1 `resolve_at_send` column + reference mode + dispatcher branch + config rejection | DRR DD-5 | Scheduling dispatcher (one branch), SMS (inherits as-is, no variance) | This doc §1.1.3; research contract §(d) |
| 12 | Shared engine + token registry + D3 disposition | DRR Steps 4–6 | Scheduling (materializer/dispatcher become consumers), SMS (compliance escalation consumes `is_transactional` classification) | DRR Public API Contract; SMS Step D2 |
| 13 | Phone-extensible interface: `destination` param + `ResolvedDestination.phone` slot + AC-19 signature freeze | DRR DD-11 | SMS F1 | DRR DD-11/AC-19; SMS DD-3 |
| 14 | Allow-list phone columns + `destination:'phone'` guard flip + conformance-vector update (both repos) | SMS F1 | The shared engine (data + guard only — no resolver code) | SMS Step F1; DRR BLOCKED-ON DRR-09/SMS-01 row; C5 below |
| 15 | Trigger catalog: `available_recipient_tokens` + `is_transactional` (code-seeded) | DRR Step 3 (content = BA deliverable, DRR-04/D3) | DRR validators/engine, SMS D3 escalation | DRR DD-6/Step 3 |
| 16 | `dedupe_key` occurrence identity | Scheduling | SMS duplicate-text protection (platform short-circuit + provider idempotency token) | Research contract §(c); SMS DD-10/AC-23 |
| 17 | `recipients_snapshot` shape generalization (`mode` discriminator; phone destination additive, email fields `to[]/cc[]/bcc[]/replacements/from_name/reply_to` must keep flowing to `sgMail.send`) | DRR (mode), SMS (phone field) | Scheduling dispatcher email branch (must stay byte-identical) | DRR DD-5; SMS DD-13; research contract §(e) |
| 18 | Twilio provisioning + 10DLC registration (external) | Client + SMS track (owner per SMS-08) | Release launch gate MS9(4) only | SMS §4.2/Step A1 |
| 19 | Suppression store + quiet hours + consent events | SMS D1/D2 | SMS launch gate; independent of DRR/Scheduling | SMS DD-8/DD-9 |
| 20 | BA/client answers: DRR-01…05, DRR-04 matrix, D1/D3 sign-off; SMS-01/02/03/06/07/08 | BA/Client | Every BLOCKED-ON row in both plans; three gate flips | Both plans' BLOCKED-ON tables; §6 below |

---

## 4. Release gate checklist

Everything that must be true to call the combined release shipped. Grouped by gate; each item is binary and names its verifier.

**A. Spine integrity (verify continuously, enforce at every PR):**
- [ ] No second resolver: the DRR Gate Contract grep is clean; no recipient parsing outside `recipient-resolution/`; no SMS-specific phone lookup exists (SMS AC-8).
- [ ] Exactly one migration touches `notification_logs` (§1.2 verifier greps); no SMS-side log DDL anywhere (SMS Substrate check #5).
- [ ] Conformance vectors identical in admin + worker; both suites green (DRR DD-2/Step 14).
- [ ] No new BigInt PKs; in the **unified spine migration** every new column is NOT NULL-with-default — no nullable exceptions (`notification_template_id` pre-exists NOT NULL, untouched); sibling migrations: nullable only where semantically required, per SMS plan Step D1 (e.g. `released_at`, `exhibitor_id`/`user_id` on consent rows).

**B. Scheduling track (base plan + addendum):**
- [ ] S1 retention cron live **before Phase 3 ships** (with the FOLLOW_UP latest-row guard); S6 tz fail-closed live (ingest IANA validation + send-side SKIP `"unresolvable event timezone"`).
- [ ] S2 `FOR UPDATE SKIP LOCKED` claim in the first dispatch implementation; at-least-once stated verbatim in the service doc-comment.
- [ ] S3 `catchup_policy` + per-skip and aggregate alert lines; X1: enum shipped without `CART_CONVERTED`.
- [ ] **X2's three verification cases green** (retention / reaper double-send / bad-timezone) + the S5 DST fall-back test — tests, not prose.
- [ ] D2 `@unique` drop landed in all five schemas (or absorbed by DRR Step 1 per the DD-9 contingency) — hard prerequisite for `{all customer contacts}`.

**C. DRR track:**
- [ ] Unified spine migration roundtrip clean; payment-reminder dedupe query returns identical fixture results before/after (DRR-S2 / AC-16).
- [ ] Scheduler regression zero: `resolve_at_send=false` replay byte-identical, pre-existing scheduling tests unmodified (AC-12/AC-18).
- [ ] Token un-gate proven in staging: a schedule that SKIPPED `"recipient requires DRR (#3)"` dispatches normally (AC-15).
- [ ] Zero-recipient policy enforced by integration test — marketing SKIP / transactional ABORT + alert, never send-to-zero (AC-8).
- [ ] Preview side-effect-free (AC-17); `destination` seam verified by AC-19 signature review.
- [ ] `DRR_LIVE_SEND_ENABLED` flipped only after #21 fix confirmed deployed **and** zero `// BA-PENDING` rows on token-bearing triggers (DRR-04 matrix delivered).

**D. SMS track (= the story §9 checklist, restated as gate items):**
- [ ] **SMS-02** written confirmation that 76.8 is pulled forward (reverses the 2026-06-03 verbal deferral) — the meta-gate; without it the SMS plan stands down and the scheduler keeps SKIPping (designed-safe).
- [ ] **SMS-01** confirmed: Twilio Programmable Messaging + account/number ownership — never silently assumed.
- [ ] **10DLC registered**: A2P brand + campaign approved, Messaging Service/number provisioned — **no production SMS before this, period** (carrier hard-block; AC-16). Started day one (MS0).
- [ ] **Suppression store live before the first live SMS** (pre-send check on every dispatch, AC-12) + STOP-webhook and manual opt-out capture writing to it (AC-13) + state-aware quiet-hours deferral (AC-14) + consent events append-only ≥5y (AC-15).
- [ ] **SMS-03** consent policy recorded — no US go-live without it.
- [ ] SMS templates seeded for the confirmed **SMS-06** list (empty scaffold is a gate failure at launch); per-trigger phone mapping (SMS-07) in the allow-list.
- [ ] Phone extension consumed via the shared engine only (F1); guard flip + vectors updated in both repos.
- [ ] H1 flip deployed dark; pre-flip AC-22 behavior verified preserved until then; duplicate-text guard proven (AC-23, reaper re-dispatch does not double-text).
- [ ] Email regression: all pre-existing log rows `channel='EMAIL'`; email dispatch byte-identical pre/post flip (AC-18).
- [ ] Launch = `sms_sending_enabled=true`, only after every item above.

**E. Open questions answered (blocking set — see §6):**
- [ ] All build-blockers answered or their PROPOSED defaults signed off: DRR-01…05 (coding blockers per DRR story §9), D1, D3, DRR-04 matrix; SMS-01/02/03/06/07/08; migration-shape sign-offs DRR-10/DRR-S2/SMS-05.
- [ ] M1 (3 sub-items: `EMAIL_SMS_KNOWN_ISSUES.md` #2/#12 wording → "SMS create is gated; storage shape undefined" + the SCH-3/SCH-4 scheduling-register notes) applied **by the user** before any client-facing review — the registers are frozen to this pipeline.

**F. Process (all five repos):**
- [ ] Pipelines green ×5 (gitleaks → lint/typecheck/test → SonarQube) — `./scripts/check-pipelines.sh`; SonarQube new-code gates green — `./scripts/check-sonar.sh` (READ-ONLY).
- [ ] `db push` mirrors diff-clean against the admin schema.
- [ ] All commits made **by the user** per repo (`type(SBE-xxx): …` scope; no AI trailers); Jira DEV DONE descriptions = routes-only tables.

---

## 5. Conflict watch

Contradictions noticed while reconciling the four new docs + addendum. **C-items are resolved inline here** (this spine's statement wins for the release); **SPINE-Qn items are genuinely open** and carried in §6.

### Resolved inline

- **C1 — Who "owns" the unified migration.** The addendum (§0.2) routes M3 to "the integration-spine doc"; the DRR plan (DD-8/Step 1) authors the DDL; the SMS plan (DD-4) says "authored on the DRR track". **Resolution:** all three are consistent once roles are named — **this spine §1.2 is the spec of record; DRR plan Step 1 is the execution home; SMS Step B1 is the consumer/verifier.** Also note the migration is broader than `notification_logs` (it carries `resolve_at_send` + the trigger-catalog columns) — the ONE-migration constraint specifically means *exactly one migration touches NotificationLog*; the SMS compliance-tables migration and the D2 standalone fix are separate by design, not violations.
- **C2 — SMS pre-send pipeline order.** The SMS plan's Caller Contract (and its Files-table dispatcher row) originally placed suppression and quiet hours **before** normalization, but Step E3 and the dispatcher tests say "kill switch → resolve → **normalize → suppression → quiet hours** → cap". **Resolution: the E3/test order is canonical** — the suppression store is keyed by E.164 (`sms_suppressions.phone_e164`), so normalization must precede the suppression lookup; the Caller Contract sentence was a summary-order slip, not a design (both spots since corrected to the E3 order).
- **C3 — Two ids for the scheduling atom.** The DRR plan's `depends_on` names it `EMS-SCH-BUILD`; the SMS plan's names it `EMS-766-SCHED`. **Resolution: same atom** (the approved scheduling build). Normalize to one id when the atoms are registered in the tracker; until then read them as aliases.
- **C4 — `DELIVERED` status.** The SMS story (FR-12) defers "whether a distinct DELIVERED value is added" to the unified-migration doc; the SMS plan (DD-4) already adopts it. **Resolution (settled in §1.2):** `status` is a VarChar, `'DELIVERED'` is written as a string for SMS rows — no enum, no schema change, terminal statuses never downgraded.
- **C5 — Who flips the `destination:'phone'` guard and updates the vectors.** The DRR plan rejects `'phone'` at the entry point "so no phone path can be half-enabled" and says the flip happens "in the SMS plan, not here"; SMS Step F1 consumes the interface but does not explicitly name the guard removal or the conformance-vector update. **Resolution:** F1 **includes** (a) removing/flipping the guard and (b) updating `test/fixtures/recipient-resolution-vectors.json` in **both** repos in the same release (DRR DD-2's rule: every behavioral engine change lands in both repos, vector file first). Treat this as part of F1's definition, not new scope.
- **C6 — Doc-set numbering.** The DRR plan self-labels "DOC 7 of 7", the addendum "DOC 6 of 7", this spine is directed as DOC 5, and the stories carry no numbers. **Resolution:** numeric labels are cosmetic; the filename index in this doc's front matter is canonical. No file edits (all siblings are read-only to this writer).
- **C7 — Seeded-template count drift.** The SMS story notes the gap doc counted 30 seeded EMAIL templates vs the current seeder grep's 29. Already flagged in that story; no spine action — the AC-4 seeder test asserts the invariant that matters (exactly one SMS row per confirmed trigger, none extra).

### Spine open items

- **SPINE-Q1 — May the unified spine migration land before SMS-02's written confirmation?** M3's wording sequences the migration "immediately after the SMS scope decision"; the DRR schedule needs it at Phase D1 regardless of SMS. **Recommended default: yes — land it with DRR Phase D1.** Every column serves DRR alone except `channel`, whose NOT-NULL-default-`'EMAIL'` is correct and inert even if SMS-02 comes back "no" (in which case the SMS plan stands down and the scheduler keeps SKIPping — designed-safe). M3's intent was ordering relative to *SMS send code*, which this preserves. Needs Engineering/BA nod because it reads M3's letter loosely. *Owner: Engineering/BA.*
- **SPINE-Q2 — What happens to "ship TOGETHER" if SMS-01/10DLC slips past the email tracks' readiness?** The spine's technical design makes the tracks separable (SMS gates keep SKIPping; DRR + Scheduling are complete without SMS), but "one combined release" is a product commitment. **Recommended default: scheduling + DRR deploy on their own readiness; the SMS *code* deploys dark (H1 pre-flip posture) and the combined release is *declared* only at the `sms_sending_enabled` launch flip.** This keeps the shared-spine guarantees (one resolver, one migration) without holding shipped email value hostage to carrier-registration timelines. Needs an explicit product decision so nobody discovers it mid-release. *Owner: BA/Client.*

---

## 6. Consolidated open-question rollup (release-gating and cross-track only)

Stable IDs, never renumbered. Full text lives in the owning doc's register; per-track sign-off items not listed here (SMS-04/09/10/11/12/14/15, DRR-06/08/11/12/15/16/17, DRR-S1) remain in their plans' BLOCKED-ON tables with build-now PROPOSED defaults.

| ID | One-line | Owner | Gates |
|---|---|---|---|
| **SMS-02** | Written confirmation 76.8 is pulled forward (reverses 2026-06-03 deferral) | BA | Entire SMS track (meta-gate) |
| **SMS-01** | Twilio Programmable Messaging confirmed as mechanism + account/number ownership | Client/BA | Day-one long pole; SMS Phases A/E/G |
| **SMS-08** | Sender identity + who registers 10DLC | Client | Launch gate MS9(4) |
| **SMS-03** | Consent/lawful-basis policy | Client | US go-live |
| **SMS-06 / SMS-07** | Trigger→SMS list + per-trigger recipient phone mapping (+ dormant Product flag) | BA | SMS seeding (C3), phone allow-list (F1) |
| **SMS-05 / DRR-10 / DRR-S2** | Migration-shape sign-offs (extend NotificationLog; recipients JSON; legacy `email` kept) | BA/Engineering | §1.2 spec sign-off (defaults build now) |
| **DRR-01…DRR-05** | Token sources, membership filters, Gmail-group model, trigger-token matrix mechanism, live-send authoritative source | BA (+ Client for DRR-03) | DRR coding blockers (story §9 item 4); defaults build now |
| **DRR-04 (matrix)** | The concrete ~40-trigger token/classification table | BA | `DRR_LIVE_SEND_ENABLED` flip |
| **DRR-07** | Backing sources for predefined lists / "other relevant system emails" (base #4) | BA | `list_ref` stays validated-but-empty until answered (not release-blocking) |
| **D1** | `resolve_at_send` toggle — confirm "both, selectable" | BA | Formal sign-off of §1.1.3 (built per adjudication regardless) |
| **D3** | Zero-recipient split: skip marketing / abort+alert transactional / never zero | BA | Disposition mapping sign-off |
| **D2** | Approve the five-schema `@unique` drop as a standalone fix | Engineering/BA | `{all customer contacts}`; MS1 milestone |
| **M1** | Register fixes, 3 sub-items (#2/#12 wording + SCH-3/SCH-4 scheduling-register notes) — user applies (registers frozen) | User | Client-facing review |
| **ADD-Q1 / ADD-Q2 / ADD-Q3** | At-least-once acceptance; catch-up policy model; defer "until answered" RECURRING | BA | Scheduling-track defaults apply if unanswered (addendum §11) |
| **SMS-S1 / SMS-S2** | Quiet hours on immediate SMS; internal-recipient exemption | BA/Client | Not launch-blocking (no immediate SMS trigger in scope); pre-Product-flag |
| **SPINE-Q1** | Unified migration before SMS-02 confirmation? (default: yes) | Engineering/BA | MS3 milestone timing |
| **SPINE-Q2** | Release-declaration semantics if the SMS long pole slips (default: email tracks deploy; SMS dark; release declared at launch flip) | BA/Client | MS9 sequencing / release comms |

---

*Per project convention: no commits are made by this document or its track; the user reviews and commits every repo. The approved scheduling plan, both stories' source registers, and both known-issues registers remain unedited; every register change above is a proposal for the user to apply.*

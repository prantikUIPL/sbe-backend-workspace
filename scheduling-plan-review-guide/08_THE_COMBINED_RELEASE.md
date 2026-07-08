# 8. The combined release — where everything landed

← prev: [The review scorecard](07_THE_REVIEW_SCORECARD.md) · back to the [README](README.md)

Files 1–7 tell the story as it stood when the review landed: the scheduling engine being built alone, SMS and DRR parked behind fences, and a fix-list waiting for a home. **On 2026-07-08 the home arrived.** Seven new documents were written, cross-verified (15 defects caught and fixed before commit), and committed under `email_and_sms_docs/email_sms_combined_release_docs/`. Every one of the review's 16 findings now has a concrete landing place. This file is the map.

---

## The rule that changed everything: ship together

🎓 **For the newcomer.**
The mailroom no longer opens alone. Two more departments open **in the same release**:

- **The address-book department (DRR).** Until now, the mailroom could only send a letter if the address was written plainly on the record ("the email on the cart"). This department handles the harder cases — "the salesperson assigned to this account", "every contact at this company" — by *looking the person up*.
- **The telegram desk (SMS).** A second way to reach people, with its own legal rulebook (you must be registered with the carriers, honour opt-outs, and never wire anyone at night).

The catch — and the whole point — is that they **share the plumbing**: one address-lookup counter serves all three departments, and one logbook records every letter *and* every telegram. Nobody gets to build their own private copy of either.

🛠️ **For the engineer.**
Scheduling (76.6/77.8) + Dynamic Recipient Resolution (77.9) + SMS Provider (76.8) ship as **one release on a shared spine**. The spine's release rule (integration spine, front section): anything that duplicates the resolver, adds a second occurrence/log table, or resolves recipients outside the engine **violates the release constraint** — and the spine backs that with verifier greps, not prose. This is what reshapes the sequencing: the review's M4 ordering (email DRR first, SMS extends it) stops being advice and becomes the build's dependency graph.

### Four facts in files 1–7 that are now different

1. **SMS is no longer "parked."** 76.8 ships in this release (Twilio Programmable Messaging). The materialize-then-SKIP gate files 2 and 6 describe still exists — but only as the **interim boundary** until the SMS un-gate flips at milestone MS9.
2. **DRR is no longer "deferred."** 77.9 ships in this release; the token-recipient SKIP gate lifts when the DRR engine deploys (MS6).
3. **"Save the who-decides questions for the BA" is superseded.** Every open question now lives in a consolidated register with an ID, an owner, tick-box options, and a stated default the build proceeds on.
4. **D2 is a five-schema fix, not two.** The review said "both schema files" because it only examined the two it needed; recon on 2026-07-08 found the `Exhibitor.company_id @unique` in **all five** repos' `schema.prisma`.

---

## The shared spine — three things there is exactly ONE of

### 1. One recipient-resolution engine

🎓 **For the newcomer.**
One address-lookup counter, three customers. The mailroom's existing simple lookup ("read the email straight off the cart") doesn't get thrown away — it becomes the counter's **simplest service tier**. The address-book department adds the harder tiers ("find the salesperson"), and the telegram desk later asks the same counter for a *phone number* instead of an email. Same counter, same rules, one queue.

🛠️ **For the engineer.**
`RecipientResolutionService` — canonical in `background-worker-service/src/notification/recipient-resolution/`, with a native mirror in `admin-backend-api` kept identical by a shared conformance-vector fixture run by both repos (drift = test failure; the no-code-duplication house rule, honoured cross-repo). Key contract points (spine §1.1, DRR plan DD-1…DD-11):

- The scheduler's **restricted resolver** (bare anchor column / one documented hop / fixed transforms) is the **degenerate tier of the same engine** — `parseScheduleSource()` feeds it in; it is *not* a separate code path.
- `destination: 'email' | 'phone'` — every token resolver returns both slots; `'phone'` is **guard-rejected until the SMS track flips it** (so no half-enabled phone path can exist).
- Zero recipients becomes a **disposition**, never a send: marketing/reminder → `SKIP`, transactional → `ABORT` + alert — the review's **D3**, now engine behaviour rather than "subject to R&D."
- No expression DSL, no eval — the security posture the review praised survives generalization intact.

### 2. One `NotificationLog` migration

🎓 **For the newcomer.**
The logbook gets exactly **one renovation**, ever, for this release: a column saying *"was this a letter or a telegram?"* and a column recording the **full list of who it went to and why**. Both departments agreed the renovation plans in writing before anyone picked up a hammer — because two teams renovating the same logbook separately is how you lose records.

🛠️ **For the engineer.**
`<ts>_ems_unified_notification_spine` (admin-owned; the other four repos mirror via `db push`). It adds to `notification_logs` **only** `channel` (`NotificationChannel` enum, NOT NULL DEFAULT `'EMAIL'` — backfills all historical rows correctly) and `recipients` (`Json NOT NULL DEFAULT '[]'` — per-entry resolution outcomes; historical rows keep `[]`, no fabricated backfill). The legacy `email` column is **kept and still populated** — the payment-reminder dedupe query filters on it and must return identical results before/after (regression-tested). **Spec of record: spine §1.2. Execution home: DRR plan Step 1.** The release-gate greps enforce that *exactly one* migration touches `notification_logs`; a second SMS-side log migration anywhere is a halt-the-line violation. (The same migration also carries `resolve_at_send` and the trigger-catalog columns — one migration, one deploy.)

### 3. The D1 timing contract — `resolve_at_send`

🎓 **For the newcomer.**
File 5's hardest question — *photocopy the address list when you write the letter, or check the address book again at mailing time?* — is now a **per-instruction switch**, and the default is the photocopy the mailroom already makes. A manager flips the switch only for instructions where freshness matters more than predictability.

🛠️ **For the engineer.** (spine §1.1.3, DRR plan DD-5)
`notification_schedules.resolve_at_send Boolean NOT NULL DEFAULT false`. Default path: dispatch replays `recipients_snapshot` verbatim, engine not called — pre-existing scheduler behaviour byte-identical. Opt-in path: the snapshot stores a **reference shape** and the dispatcher grows **exactly one branch** (`engine.resolve(timing:'dispatch')` inside the claim). Config-time rejected until DRR ships; SMS inherits it with **no variance**. Honest footnote: under at-least-once (S2), a reaper re-dispatch with the toggle on may re-resolve to a *different* set — accepted as the freshness semantics you opted into, audited per attempt.

---

## The build order: MS0–MS9, and the licence you file on day one

🎓 **For the newcomer.**
The opening-day plan is ten milestones. The one that can sink the date isn't code at all — it's paperwork: the **telegraph licence (10DLC)**. US carriers refuse 100% of telegrams from unregistered businesses, and registration takes days to weeks. So the licence application is filed **on day one**, even though it only matters for the very last switch-flip. File it late and the paperwork *becomes* the release date.

🛠️ **For the engineer.** (spine §2)

| # | Milestone (condensed) | Note |
|---|---|---|
| MS0 | Day-one kickoffs: SMS-01/02 question pack; **Twilio + A2P 10DLC registration starts on SMS-01 confirmation** — the release long pole; BA agenda; migration co-design freeze | Runs in parallel with everything |
| MS1 | **D2** standalone fix (five schemas, own PR) | Decoupled — do soon |
| MS2 | Scheduling Phases 1–2, with **X1** applied at Phase 1 | S3 column may ride the Phase-1 migration |
| MS3 | **Unified spine migration** + 4× `db push` mirrors | Needs MS2's Phase-1 migration first |
| MS4 | Scheduling Phase 3 + the addendum deltas: **S1, S6** before Phase 3 ships; S2/S3/S5/X2 during Phase 3/4 | Both SKIP gates now live |
| MS5 | **SMS dark build** (templates, compliance substrate, `SmsService`, webhook — all inert behind the kill switch) | The release's biggest parallelism win |
| MS6 | **Email DRR engine + scheduler consumption** — token gate un-gates on deploy | The M4 ordering, made binding |
| MS7 | DRR live-send consumption, deployed dark behind `DRR_LIVE_SEND_ENABLED` | Needs the #21 fix deployed |
| MS8 | SMS phone extension — `destination:'phone'` guard flip, vectors updated in both repos | Needs MS6's frozen interface |
| MS9 | **Gate flips, in order**: DRR staging-proven → DRR live env flip → SMS H1 code flip (dark) → **launch**: `sms_sending_enabled=true` | Step 4 alone waits on the 10DLC long pole |

Critical path: MS2 → MS4 → MS6 → MS8 → MS9(3). The 10DLC long pole is schedule-critical but **off the code path** — it gates only MS9(4).

### Two flips, not one — dark flip vs launch toggle

🎓 The telegram desk is wired up and inspected (**the dark flip**) long before the front shutter opens (**the launch toggle**). With the shutter down, would-be telegrams are logged as "skipped — sending disabled" — observable and harmless.

🛠️ The **H1 code flip** deploys the SMS branch dark (remove the SKIP pass, widen the dispatch select, extend the by-id `channel==='EMAIL'` assertion with the `'SMS'` → `SmsService` branch — same by-id path, so #21-immunity carries over by construction). The **launch** is a separate `ppl_settings` flip, `sms_sending_enabled=true` (default `'false'`), gated on 10DLC + provisioning + the consent decision — a settings edit and an SQS invalidate, no deploy. It is also the fastest rollback lever.

---

## The release-gate checklist, in one breath

🎓 A pre-opening inspection sheet: every line is a yes/no with a named inspector. Nothing ships on "should be fine."

🛠️ Spine §4 — six gate groups, each item binary with a named verifier: **A** spine integrity (no second resolver, exactly one `notification_logs` migration, conformance vectors identical — enforced continuously by greps); **B** scheduling track (the addendum deltas: S1 cron live before Phase 3, S6 fail-closed, S2 `SKIP LOCKED` + at-least-once stated verbatim, S3 alerts, X1 enum, **X2's three cases green as tests, not prose**, D2 landed); **C** DRR track (migration roundtrip, byte-identical replay regression, token un-gate staging-proven, never-send-to-zero enforced by test); **D** SMS track (the story's §9 checklist restated — 10DLC, suppression store live before the first live SMS, dark flip verified); **E** every build-blocking open question answered or its default signed off; **F** process (pipelines green ×5, `db push` mirrors diff-clean, all commits by the user).

---

## The open-questions register — the BA agenda, upgraded

🎓 **For the newcomer.**
Files 1–7 kept saying "that's a question for the business analyst." Those questions didn't evaporate — they got **filing cards**. Each card has a number that never changes, the person who owes the answer, tick-box options with our recommended default pre-marked, and a line saying exactly which piece of work waits on it. The build doesn't stall: it proceeds on the recommended default, and an answer either confirms the default or tells us what to change.

🛠️ **For the engineer.**
`EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md`: **44 open entries** (46 stable IDs — D1 carries DRR-13, DRR-07 carries P9-5; 65 IDs in total counting the appendix's 19 closed + 2 carried rows — nothing is dropped, closed items keep their resolving citation), in **8 categories A–H** (business scope, provisioning, recipient semantics, SMS compliance, scheduling hardening, cross-track contracts, data & schema, process), answered in **tier order**:

- **Tier 0 — answer first, shapes the spine:** **SMS-02** (written confirmation SMS is pulled forward — the meta-gate), **SMS-01** (Twilio confirmed as the mechanism — the client said "SendGrid", whose API is email-only, so this is confirmed-never-assumed), **D1** (the `resolve_at_send` adjudication, pending BA sign-off), **SPINE-Q1** (may the migration land before SMS-02's written answer).
- **Tier 1** — day-one long-lead items (10DLC ownership, consent policy). **Tier 2** — shapes story surfaces before they freeze. **Tier 3** — engineering defaults already built (ADD-Q1/Q2, D2 live here). **Tier 4** — sign-offs (M1).

The review's own three Section-6 open questions (file 7) are now register rows: S2's acceptance = **ADD-Q1**, S4's defer-or-ship = **ADD-Q3**, D1's adoption = **decided-in-plan, pending BA sign-off**.

---

## Where each of the 16 findings landed

The one-table version. "Addendum" = the scheduling fixes addendum — a **delta spec**: the approved plan stays byte-for-byte untouched, and where the two conflict, *the addendum wins*.

| ID | Sev. | Landed in | The concrete spec, one line | Slot / open decision |
|---|---|---|---|---|
| **S1** | HIGH | Addendum §1 | Daily retention cron, 3 `ppl_settings` knobs (90-day default), FOLLOW_UP latest-SENT-row purge guard | MS4, before Phase 3 ships |
| S2 | Med | Addendum §2 | `FOR UPDATE SKIP LOCKED` claim in one transaction; **at-least-once stated verbatim** in the doc-comment | MS4 · ADD-Q1 (accept vs idempotency) |
| S3 | Med | Addendum §3 | `catchup_policy` enum column (`SKIP`/`SEND`, NOT NULL default `SKIP`) + per-skip and aggregate alert lines | MS4 · ADD-Q2 (per-kind defaults?) |
| S4 | Med | Addendum §4 | "Until answered" RECURRING template **deferred** with its dependencies; the mechanics still ship, test-exercised | MS4 window · ADD-Q3 (BA) |
| S5 | Low | Addendum §5 | One DST fall-back unit test: 01:30 America/New_York on 2026-11-01 ⇒ the **earlier** instant, deterministically | MS4, with the Phase-3 DST tests |
| **S6** | Med | Addendum §6 | IANA validation at ingest (400 on bad writes, read-only audit for legacy); send side **fails closed** — SKIP + alert, default zone removed from the EVENT chain | MS4, before Phase 3 ships |
| S7 | Low | Addendum §7 | Closed by S1 — snapshot PII lives at most the retention window; staleness half answered by the D1 toggle | Rides MS4 with S1 |
| **D1** | HIGH | DRR plan DD-5 + spine §1.1.3 | **Adopted**: per-rule `resolve_at_send` toggle, default snapshot-at-materialize; one dispatcher branch | Tier-0 register row (BA sign-off) |
| D2 | Med | Addendum §10 | `@unique` dropped + `@@index` added in **all five** schemas (not two); `Company.exhibitor` → plural, ~25 call sites decided one-by-one; idempotent migration, own PR | MS1 · register §G (default: approve) |
| D3 | Med | DRR plan DD-6 | Zero recipients is a disposition, never a send: marketing → SKIP, transactional → ABORT + alert on the S3 channel | Register §C (BA) |
| **M1** | HIGH | Register §H | One entry, **3 tracked sub-items** (the #2/#12 wording fix + the two scheduling-register notes) — applied **by the user**; both register files are frozen to this pipeline | Tier 4 |
| M2 | Med | SMS plan (compliance substrate) | Suppression store + append-only consent events (≥5y) + state-aware quiet hours + the 10DLC hard gate — live before the first live SMS | MS5 dark build |
| M3 | Med | Spine §1.2 | The unified `NotificationLog` migration: `channel` + `recipients` only; spec of record = spine, execution home = DRR Step 1 | MS3 |
| M4 | Low | Spine §1.1.2 / build order | Email DRR first → scheduler consumes → SMS extends to phone — binding sequence, enforced by the gate greps | MS6 → MS8 |
| X1 | Low | Addendum §8 | Stop-condition enum ships as `{CONTRACT_SIGNED, QUESTION_ANSWERED, NONE}` — no `CART_CONVERTED` anywhere; re-adding later is one `ALTER TYPE` | MS2, at Phase 1 |
| X2 | Low | Addendum §9 | Three verification cases appended: retention / reaper double-send / bad timezone — a release-gate line requires them **green as tests** | MS4 |

---

## The seven documents, annotated

All in [`../email_and_sms_docs/email_sms_combined_release_docs/`](../email_and_sms_docs/email_sms_combined_release_docs/). Reading order for a new joiner = top to bottom.

| Doc | What it is | Why you'd open it |
|---|---|---|
| [DRR refined story](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_REFINED_STORY.md) | 77.9 requirements: FR-1…24, AC-1…19, the DRR-xx question register | What the address-book department must do, testably |
| [SMS refined story](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_76.8_SMS_REFINED_STORY.md) | 76.8 requirements: FR-1…17, AC-1…26, the SMS-xx register, the §9 un-gating checklist | What the telegram desk must do — and the 8-step checklist that opens it |
| [DRR implementation plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_77.9_DRR_IMPLEMENTATION_PLAN.md) | Phases D0–D6, 122h — builds the shared engine **and** authors the unified migration | The engine contract (DD-1…14), D1's build, D3's mechanics |
| [SMS implementation plan](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_76.8_SMS_IMPLEMENTATION_PLAN.md) | Phases A–H, 73h — Twilio `SmsService`, suppression/consent tables, webhook, the two flips | The compliance substrate (M2's landing) and the dark-flip/launch split |
| [Integration spine](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_INTEGRATION_SPINE.md) | The cross-track contract: the ONE-engine/ONE-migration rules, MS0–MS9, the dependency matrix, the release-gate checklist, the conflict watch | **The one document a release runner reads.** Spec of record for the migration (§1.2) and D1 (§1.1.3) |
| [Scheduling fixes addendum](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_SCHEDULING_FIXES_ADDENDUM.md) | S1–S7, X1–X2, D2 as ready-to-apply deltas; the approved plan untouched; on conflict, the addendum wins | Every S/X/D2 row in the table above, at full engineering depth |
| [Open-questions register](../email_and_sms_docs/email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md) | 44 open entries, 8 categories, tiers 0–4, tick-box defaults, owner tags; closed IDs kept in its appendix | Any "who decides X?" question from files 1–7 — it's a row here now |

---

## Where this leaves the guide

- Files 1–7 remain the honest record of **plan vs. review** — the 📘/🔎 record is preserved, with any factual corrections disclosed in italics, never silent.
- The **📦 WHERE IT LANDED** boxes layered through them, and this file, are the record of **review vs. outcome**.
- The mailroom still opens exactly as designed. It just no longer opens alone.

← prev: [The review scorecard](07_THE_REVIEW_SCORECARD.md) · back to the [README](README.md)

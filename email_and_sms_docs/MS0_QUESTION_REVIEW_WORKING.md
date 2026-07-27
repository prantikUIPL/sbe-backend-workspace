# MS0 Question Set — Review, Refinements & Design Corrections (WORKING)

**What this is:** durable capture of the one-by-one review of the **MS0 day-one question pack**, done before those questions go to BA / PM / Client / TL. Reconstructed 2026-07-27 from the session working notes (the original scratchpad copy was session-scoped and lost).

**This is NOT the frozen register.** `email_sms_combined_release_docs/EMAIL_SMS_COMBINED_RELEASE_OPEN_QUESTIONS.md` is untouched (code-drift correction set remains on hold until merges-done → re-audit). Nothing here is committed; Prantik reviews and commits.

**Owner note:** authored/confirmed with Prantik (story owner of SBE-675 "Template Edit" / SBE-681 custom twin). Where he stated intent as the story owner, it is treated as authoritative.

---

## Scope — strictly the MS0 day-one pack, 3 groups

- **Group 1 — client/provisioning (5):** SMS-02, SMS-01, SMS-08, SMS-03, DRR-03
- **Group 2 — BA business (8):** DRR-01, DRR-02, DRR-04, DRR-05, D1, D3, SMS-06, SMS-07
- **Group 3 — lower-priority BA (8):** DRR-07, DRR-12, DRR-15, DRR-16, SMS-S1, SMS-S2, ADD-Q3, P9-1

Engineering-owned questions and the MS1–MS9 build walkthrough are OUT of this pass.

## Progress

| Group | Status |
|---|---|
| Group 1 | ✅ Reviewed, no wording changes |
| Group 2 | 🔄 In progress — DRR-01, DRR-02, DRR-04, DRR-05, D1 done; **remaining: D3, SMS-06, SMS-07** |
| Group 3 | ⬜ Not started |

---

## Group 1 — client/provisioning — REVIEWED, no wording changes

- **SMS-02** — Written confirmation 76.8 is pulled forward (reverses 2026-06-03 deferral). Master switch for all SMS.
- **SMS-01** — Confirm Twilio Programmable Messaging as the mechanism (SendGrid is email-only) + account/billing ownership + who hands whom credentials. Starts the multi-week 10DLC clock.
- **SMS-08** — Sender identity (recommend one Messaging Service pooling 10DLC long codes; no per-template sender) + who files 10DLC registration + brand/legal-entity/campaign details. Launch gate.
- **SMS-03** — Consent policy: which entity holds consent (phone/user/exhibitor) + prior express consent required? + named legal contact. Safety net (suppression + quiet hours + ≥5y consent) builds regardless.
- **DRR-03** — Gmail groups: (a) literal address, Google expands [recommended, no creds] vs (b) membership expansion via Google Workspace Directory API (needs service-account creds → name owner).

---

## Group 2 — BA business

### DRR-01 — Who is "the salesperson"? — WIDENED (Deal Owner folded in)
> For the `{salesperson}` tag, confirm the source field(s) so it always resolves to a real person:
> 1. For **order-related** emails — is it the order's assigned salesperson (`Order.sales_person_id`)?
> 2. For emails originating from a **cart/deal** rather than a completed order — should it resolve through the **Deal Owner** (`created_by` / `created_by_type`), which replaced the old cart sales-rep field?
> 3. Confirm **strategist** and **referred-by** are NOT used as stand-ins.
> 4. When a record has no salesperson at all, confirm the tag **skips and logs** rather than substituting anyone.

*Audit basis:* code audit vs origin/dev found the Cart sales-rep FK replaced by polymorphic Deal Owner. Folded in.

### DRR-02 — Who is "main" / "all" customer contacts? — WIDENED (invited_by:null folded in)
> Confirm:
> 1. `{main customer contact}` = the company's **primary account holder** — and confirm which definition is authoritative, since the code currently uses **two**: `user_type = 1` and `invited_by = null` (the un-invited original owner, per the order-notification path). Which is canonical?
> 2. `{all customer contacts}` = primary + **accepted** invited members only — exclude pending, revoked, deleted (include pending? include revoked? — recommend no).
> 3. Confirm: 1 primary + 2 accepted + 1 revoked + 1 deleted → **exactly 3** recipients.

*Audit basis:* code audit found a newer account-owner precedent `invited_by = null` (order-notification.service.ts ~:207-211) alongside proposed `user_type = 1`. Folded in.

### DRR-04 — Trigger→token matrix (BA DELIVERABLE, not yes/no) — REVIEWED
- Mechanism signed off: tokens un-offerable at config time on triggers that structurally lack context; send-time gaps → skip-and-log (DRR-06).
- **Token-naming sign-off flagged:** `{main customer contact}` / `{all customer contacts}` / `{salesperson}` have NEVER been seen by the client (first appeared in the Updated Epic) — confirm or rename before they freeze into the UI.
- **Attach the LIVE trigger list to the matrix template** — audit found ~**33** triggers (docs assumed ~21; seeded templates 18→30). Build against the live list.
- Deliverable format: `Trigger slug → offered tokens → transactional | marketing` (the transactional flag drives D3).
- Fields: two new `trigger_events` columns on the unified migration — `available_recipient_tokens` (Json, default []) + `is_transactional` (Boolean, default false). Seeder rows ship `// BA-PENDING`; `DRR_LIVE_SEND_ENABLED` cannot flip while any token-bearing trigger stays BA-PENDING.

### DRR-05 — Stored config authoritative at send time — **CORRECTED (major finding — predefined partly IN DRR)**
- **RESOLVED by the story owner: case (a) + by design.** Predefined CC/BCC come DIRECTLY from stored config, and that stored config was **purpose-built to be worked with the DRR + scheduling changes.** Predefined templates are NOT wholly out of DRR. Earlier "all predefined recipients read-only / out of DRR" was WRONG.
- **Corrected recipient model** (verified vs origin/dev `notification-template.service.ts` — `assertPredefinedFieldsEditable` + `PREDEFINED_EDITABLE_CONFIG_KEYS`; story SBE-675):
  - **PREDEFINED email:** LOCKED / system-controlled (code) = `to_recipients` (TO), `from_address` (FROM email), `notification_type` (trigger). Admin-editable STORED config, resolved through DRR (incl. tokens) + honored by scheduling = `cc_recipients`, `bcc_recipients`, `from_name`, `reply_to`, subject, body.
  - **PREDEFINED SMS:** channel_config fully read-only.
  - **CUSTOM email:** full stored config (TO + CC + BCC) authoritative through DRR.
- **No merge conflict:** predefined TO=code, CC/BCC=stored config are different fields from different sources.
- Partly ANSWERS **DRR-15**: DRR tokens in CC/BCC are in scope by design (predefined editable CC/BCC + custom).
- Prereq unchanged: #21 template-by-id fix deployed first; MS7 live-send consumption, dark behind `DRR_LIVE_SEND_ENABLED`.

### D1 (/DRR-13) — Recipient freshness for scheduled sends — REVIEWED
- Recommended (adjudicated): "both, selectable" — default snapshot-at-materialize; per-rule `resolve_at_send` opt-in. One boolean column + one dispatcher branch; SMS inherits; zero scheduler redesign.
- Caveat for BA: `resolve_at_send` is mutually exclusive with timezone-accurate (EVENT) sending on the same rule (freeze-everything-ahead vs decide-recipients-at-send are opposite occurrence shapes).
- **Product flag raised, NOT yet in register:** there is **no per-recipient timezone** — a rule fires at ONE timezone (its IANA zone, or EVENT). "Reach everyone at 9am *their* local time" is not supported. Confirm one-zone-per-rule acceptable with client; per-recipient local-time delivery would be new scope.

### Remaining in Group 2: **D3** (item 6), **SMS-06** (7), **SMS-07** (8)

---

## Group 3 — lower-priority BA — NOT STARTED
DRR-07, DRR-12, DRR-15 (note: partly pre-answered by the DRR-05 correction), DRR-16, SMS-S1, SMS-S2, ADD-Q3, P9-1.

---

## DESIGN CORRECTIONS (authoritative, from story owner — can apply INDEPENDENT of the code-drift merge hold; awaiting Prantik's go)

The correction-set hold is about **code-drift** facts that keep moving until branches merge (template/call-site counts, absorption inventory). The item below is a **design-intent** correction from the story owner — it will not change when other branches merge, so it is NOT gated by that hold.

1. **Predefined CC/BCC are IN DRR (from stored config), by design.** The phrase "predefined stays code-computed / out of DRR" is wrong in FOUR places and must be corrected to the split in DRR-05 above:
   - DRR-05 recommendation text (register)
   - DRR implementation plan — Step 10 / DD-12
   - DRR gap analysis — founding premise ("stored recipient config is ignored at send")
   - Integration spine — §1.1

*(Open question to Prantik: keep this "design corrections" list applying on your say-so, separate from the parked code-drift set? Not yet answered.)*

---

## Scheduling facts confirmed this session (from the byte-frozen plan — reference)

- **Dispatch poll interval** = `schedule_dispatch_interval_minutes`, default **5**, clamp [1,30]. This is the only real per-send delay (a send lands within one tick of its target).
- **Timezone is NOT per-recipient.** It's per-rule: an explicit IANA zone, or `EVENT` (derived from the event record — only `Shows.timezone` exists today). EVENT resolution fails CLOSED (skip + alert) on an unresolvable zone (S6); default `America/New_York` is authoring pre-fill only. The two first anchors (CART, PAYMENT_TRANSACTION) have no tz column → must carry explicit IANA. RECURRING can't use EVENT.
- **ANCHOR_RELATIVE id determination:** the materializer **scans the anchor table by its date column** within a look-ahead window each tick (reusing `Cart.@@index([expiration_date])` / `PaymentTransaction.@@index([status, due_date])`); each matching row's **primary key** is the instance id, recorded as `anchor_instance_ref` (`entity:id`); `dedupe_key = schedule_id + ':' + anchor_instance_ref + ':' + offset_key`. In-scope anchors = **CART** (`expiration_date`) + **PAYMENT_TRANSACTION** (`due_date`); ORDER is FOLLOW_UP-only; SHOW deferred. Contrast: FOLLOW_UP has no table to scan, so the capture site WRITES `anchor_instance_ref` at trigger time.

---

## RESUME HERE (next session)

1. **Continue Group 2:** D3 (zero-recipient: marketing skip / transactional abort+alert), then SMS-06 (which emails also text + whose phone), then SMS-07 (which stored phone per trigger).
2. **Then Group 3** (8 questions; DRR-15 partly pre-answered by the DRR-05 correction).
3. **Decide:** apply the DRR-05 predefined-CC/BCC design correction to the 4 docs now (independent of the merge hold), yes/no.
4. **Add to register when un-frozen:** the "no per-recipient timezone" product flag (D1) + the two DRR agenda wideners (Deal Owner, invited_by:null) + the ~33 live-trigger-list attachment for DRR-04.

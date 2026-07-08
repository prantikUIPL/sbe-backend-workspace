# Email & SMS — Combined Release: OPEN QUESTIONS REGISTER

**Scheduling (76.6/77.8) + Dynamic Recipient Resolution (77.9) + SMS Provider (76.8) — one combined release, one consolidated question register.**

**Combined-release doc set** (`email_and_sms_docs/email_sms_combined_release_docs/`) — the consolidated open-questions register, final deliverable of the set. (Doc-set numbering is cosmetic per the spine's C6 note; the spine's filename index is canonical.)
**Date:** 2026-07-08
**Status:** documentation only — no code, no schema change, no commits. The user reviews and commits everything; register edits to the frozen `EMAIL_SMS_KNOWN_ISSUES.md` and `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md` remain user actions (see M1 sub-items (a)–(c)).

---

## 0. How to use this document

1. **This is the ONE list.** Every open question that must be answered for a smooth implementation of the combined release lives here, under its **original stable ID** (SMS-xx from the SMS gap analysis, DRR-xx from the DRR gap analysis, S/D/M/X from the external validation report of 2026-07-07, ADD-Qn from the scheduling fixes addendum, SPINE-Qn from the integration spine, P9-n from the approved scheduling plan §9, and the stories' new -Sn items). **IDs are never renumbered.** Anything from those sources that is *already answered* is in Appendix R with its resolving citation — nothing has been dropped.
2. **Answer in tier order** (§1). Tier 0 shapes the shared spine and must be answered first; Tier 1 items are external long-lead actions that start day one regardless; Tiers 2–4 follow.
3. **Every question with a finite answer space has tick-boxes.** The **first option is our recommended default and is marked "(recommended)"** with a one-line reason. For most items the build **proceeds on the recommended default now** (per the plans' BLOCKED-ON tables) — your answer either confirms the default or tells us what to change. Where only a descriptive answer works (account owners, list sources, a mapping table), there is a free-text line instead.
4. **Owners:** 🧑‍💼 = BA/Client business decision (phrased in plain language) · 🌐 = Client/DevOps provisioning · 🛠️ = Tech Lead/Engineering decision · ✅ = sign-off of an already-built/specified default.
5. **"Blocks"** names exactly which plan step / milestone / gate waits on the answer, with the owning document and section.
6. Mark the ☐ in the summary table as answers land; the release gate checklist (spine §4 item E) closes only when every build-blocking row here is answered or its default is signed off.

**The combined-release constraint (context for every answer):** Scheduling, DRR and SMS ship **together** on a shared spine — **one** recipient-resolution engine (DRR generalizes the scheduler's restricted resolver; SMS extends that same engine to a phone field — never a second resolver), **one** unified `NotificationLog` migration (`channel` + generalized recipient, admin-owned, `db push`-mirrored to the other four repos), and the **D1** per-rule resolve-timing toggle (default = snapshot-at-materialize). The release **long pole is external**: Twilio account + A2P 10DLC brand/campaign registration (days-to-weeks; carriers block 100% of unregistered 10DLC traffic since Feb 2025) starts **day one** on SMS-01 confirmation. (Spine §1, "The release rule"; validation report M2–M4.)

---

## 1. Answer-order index (tiers → question IDs)

| Tier | Meaning | Question IDs |
|---|---|---|
| **Tier 0 — answer first, shapes the spine** | The build's first decisions; day-one question pack | **SMS-02** · **SMS-01** · **D1 (/DRR-13)** · **SPINE-Q1** |
| **Tier 1 — long-lead, kick off day one regardless** | External provisioning / legal; runs in parallel with the whole build | **SMS-08** · **SMS-03** · **DRR-03** |
| **Tier 2 — shapes stories/UX & the spine migration** | Needed before the relevant story surface freezes | **SMS-06** · **SMS-07** · **SMS-12** · **DRR-15** · **DRR-16** · **P9-1** · **DRR-01** · **DRR-02** · **DRR-04** · **DRR-05** · **DRR-07 (/P9-5)** · **DRR-12** · **D3** · **SMS-S1** · **SMS-S2** · **ADD-Q3** · **SMS-05** · **DRR-10** · **DRR-S2** · **SPINE-Q2** · **P9-2** |
| **Tier 3 — engineering decisions we can default** | Defaults are built now; answers change details, not structure | **DRR-06** · **DRR-08** · **DRR-09** · **DRR-11** · **DRR-17** · **DRR-S1** · **SMS-04** · **SMS-09** · **SMS-10** · **SMS-11** · **SMS-14** · **SMS-15** · **ADD-Q1** · **ADD-Q2** · **D2** |
| **Tier 4 — sign-offs / process** | Gate acceptances executed by the named owner | **M1** |

---

## 2. One-page summary table

44 open entries (46 IDs — D1 carries DRR-13; DRR-07 carries P9-5). Appendix R holds 21 rows: 19 closed IDs + 2 carried cross-references (DRR-13 → D1, P9-5 → DRR-07). Owner counts across the open entries: 🧑‍💼 28 · 🌐 3 · 🛠️ 5 · ✅ 8.

| ID | Category | Owner | Tier | Status |
|---|---|---|---|---|
| SMS-02 | A. Business scope | 🧑‍💼 BA | 0 | ☐ |
| SMS-06 | A. Business scope | 🧑‍💼 BA | 2 | ☐ |
| SMS-12 | A. Business scope | 🧑‍💼 Client | 2 | ☐ |
| DRR-15 | A. Business scope | 🧑‍💼 BA/Client | 2 | ☐ |
| DRR-16 | A. Business scope | 🧑‍💼 BA/Client | 2 | ☐ |
| P9-1 | A. Business scope | 🧑‍💼 BA | 2 | ☐ |
| SMS-01 | B. Provisioning/long-lead | 🌐 Client/BA | 0 | ☐ |
| SMS-08 | B. Provisioning/long-lead | 🌐 Client | 1 | ☐ |
| DRR-03 | B. Provisioning/long-lead | 🌐 Client | 1 | ☐ |
| DRR-01 | C. Recipient resolution | 🧑‍💼 BA | 2 | ☐ |
| DRR-02 | C. Recipient resolution | 🧑‍💼 BA | 2 | ☐ |
| DRR-04 | C. Recipient resolution | 🧑‍💼 BA | 2 | ☐ |
| DRR-05 | C. Recipient resolution | 🧑‍💼 BA | 2 | ☐ |
| DRR-06 | C. Recipient resolution | 🧑‍💼 BA | 3 | ☐ |
| DRR-07 (/P9-5) | C. Recipient resolution | 🧑‍💼 BA | 2 | ☐ |
| DRR-08 | C. Recipient resolution | 🧑‍💼 Client | 3 | ☐ |
| DRR-09 | C. Recipient resolution | 🧑‍💼 BA | 3 | ☐ |
| DRR-11 | C. Recipient resolution | 🧑‍💼 BA | 3 | ☐ |
| DRR-12 | C. Recipient resolution | 🧑‍💼 Client | 2 | ☐ |
| DRR-S1 | C. Recipient resolution | 🧑‍💼 BA | 3 | ☐ |
| D3 | C. Recipient resolution | 🧑‍💼 BA | 2 | ☐ |
| SMS-07 | C. Recipient resolution | 🧑‍💼 BA | 2 | ☐ |
| SMS-03 | D. SMS compliance & delivery | 🧑‍💼 Client | 1 | ☐ |
| SMS-04 | D. SMS compliance & delivery | ✅ BA sign-off | 3 | ☐ |
| SMS-09 | D. SMS compliance & delivery | ✅ BA sign-off | 3 | ☐ |
| SMS-10 | D. SMS compliance & delivery | ✅ BA sign-off | 3 | ☐ |
| SMS-11 | D. SMS compliance & delivery | ✅ BA sign-off | 3 | ☐ |
| SMS-14 | D. SMS compliance & delivery | 🧑‍💼 BA | 3 | ☐ |
| SMS-15 | D. SMS compliance & delivery | ✅ BA sign-off | 3 | ☐ |
| SMS-S1 | D. SMS compliance & delivery | 🧑‍💼 BA/Client | 2 | ☐ |
| SMS-S2 | D. SMS compliance & delivery | 🧑‍💼 BA/Client | 2 | ☐ |
| ADD-Q1 (S2) | E. Scheduling hardening | 🛠️ Tech Lead + BA | 3 | ☐ |
| ADD-Q2 (S3) | E. Scheduling hardening | 🛠️ Tech Lead + BA | 3 | ☐ |
| ADD-Q3 (S4) | E. Scheduling hardening | 🧑‍💼 BA | 2 | ☐ |
| D1 (/DRR-13) | F. Cross-track contracts | 🧑‍💼 BA (adjudicated) | 0 | ☐ |
| SPINE-Q1 | F. Cross-track contracts | 🛠️ Eng + BA | 0 | ☐ |
| SMS-05 | F. Cross-track contracts | ✅ BA/Eng sign-off | 2 | ☐ |
| DRR-10 | F. Cross-track contracts | ✅ BA/Eng sign-off | 2 | ☐ |
| DRR-S2 | F. Cross-track contracts | 🛠️ Eng + BA | 2 | ☐ |
| D2 | G. Data & schema | 🛠️ Eng + BA | 3 | ☐ |
| DRR-17 | G. Data & schema | 🧑‍💼 BA | 3 | ☐ |
| M1 | H. Process & release | ✅ User (registers frozen; 3 sub-items) | 4 | ☐ |
| SPINE-Q2 | H. Process & release | 🧑‍💼 BA/Client | 2 | ☐ |
| P9-2 | H. Process & release | 🧑‍💼 BA/PM | 2 | ☐ |

---

## A. Business scope & product decisions (owner: BA/Client)

*What is in the release, which triggers/fields/regions are covered. Plain-language; no code knowledge needed.*

---

#### SMS-02 — Is SMS officially back in the release? (the meta-question)
**Owner:** 🧑‍💼 BA · **Tier:** 0 · **Status:** ☐ OPEN

**Plain language:** The last *written* decision on record (2026-06-03, `EMAIL_SMS_KNOWN_ISSUES.md` #2) postponed SMS — "documentation only this sprint". This combined release **un-postpones** it. Before anyone builds or spends on SMS, we need that reversal **in writing** — otherwise the paper trail says one thing and the work says another.

**Answer options:**
- [ ] **Yes — 76.8 is pulled forward and ships in the combined release. (recommended)** This is the release's stated premise; every SMS plan step assumes it.
- [ ] No — SMS stays deferred. *(Then the whole SMS plan stands down, the scheduler keeps safely SKIPping SMS occurrences — designed-safe — and scheduling + DRR ship without it.)*

**Blocks:** the **entire** SMS plan (`EMAIL_SMS_76.8_SMS_IMPLEMENTATION_PLAN.md`, BLOCKED-ON row "ALL (meta-gate)"); SMS story §9 un-gating checklist step 1; spine §4 gate D first item; spine milestone MS0(a). Per M3, the unified migration is sequenced "immediately after the scope decision" — see SPINE-Q1 for whether it may land sooner.

---

#### SMS-06 — Which messages get a text-message version, and who receives it?
**Owner:** 🧑‍💼 BA · **Tier:** 2 · **Status:** ☐ OPEN

**Plain language:** The platform sends ~40 kinds of automatic emails (order confirmations, reminders, invitations…). We need the list of **which of those should also go out as an SMS**, and **whose phone** each one texts. Today the only client-attributable SMS asks on record are two *scheduled* texts (Workshop Confirmation −24h and a product-question SMS — SMS story FR-8), and both sit on event/workshop anchors the scheduling build defers (see P9-2). Also: the system already stores a dormant per-product setting ("text these numbers when this product is purchased" — `Product.product_purchased_sms_enabled`, admin `prisma/schema.prisma:1288-1291`) that has never sent anything — should it become the first live SMS trigger, or be excluded?

**Answer needed (free text — a small table):**
> Trigger → gets SMS? → recipient (whose phone) → notes
> ______________________________________________________

**Plus two tick-box sub-decisions:**
- [ ] **SMS is additive — a text goes out *in addition to* that trigger's email, never instead of it. (recommended)** The data model already supports one email row + one SMS row per trigger; replacing email risks losing the richer message.
- [ ] SMS replaces the email for some triggers *(name them)*.

- [ ] **Dormant Product purchase-SMS flag: excluded for now. (recommended-if-undecided)** It has no consumer today; including it pulls in the internal-recipient question SMS-S2.
- [ ] Dormant Product flag becomes the first live SMS trigger.

**Blocks:** SMS plan Steps C3 (template seeding — ships as an empty scaffold until the list lands), F1 (per-trigger phone mapping, with SMS-07), E3 (trigger classification); SMS story §9 step 5; spine §4 gate D ("SMS templates seeded for the confirmed SMS-06 list — an empty scaffold is a gate failure at launch").

---

#### SMS-12 — Text messages: US/Canada only, or international?
**Owner:** 🧑‍💼 Client · **Tier:** 2 · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** Sending texts abroad changes cost, sender registration rules and phone-number handling country by country. Our existing phone validation is already locked to US/Canada.

**Answer options:**
- [ ] **US/Canada only at launch. (recommended)** Matches the existing phone-validation region lock (`exhibitor-backend-api/src/common/helpers/validators/is-valid-phone.validator.ts`); non-US/CA numbers are skipped and logged, never guessed (SMS story FR-16).
- [ ] International reach required *(name the countries)*. *(New scope: a libphonenumber-class dependency + per-country sender rules — SMS plan BLOCKED-ON SMS-12.)*

**Blocks:** SMS plan DD-7 region lock (the E.164 normalizer's rules); SMS story FR-7/FR-16, AC-26.

---

#### DRR-15 — Dynamic recipients: TO field only, or also FROM / CC / BCC?
**Owner:** 🧑‍💼 BA/Client · **Tier:** 2 · **Status:** ☐ OPEN

**Plain language:** The current spec (V2/Confluence 77.9) allows smart recipient tokens like `{salesperson}` only in the **TO** line. But your recorded feedback (May 2026 thread) asked for `{salesperson}` as a **FROM** option and in **CC/BCC**. The spec narrowed what you asked for, so only you can settle it. Note: putting a token in FROM collides with the approved-sender-domain whitelist (`AllowedFromDomain`, enforced at `admin-backend-api/src/admin/notification-template/notification-template.service.ts:599-610`) — an email "from" an arbitrary salesperson address can be blocked or hurt deliverability.

**Answer options:**
- [ ] **TO only for this release (the V2 baseline). (recommended)** Ships now; CC/BCC can be added later with the same engine, no new machinery.
- [ ] TO + CC/BCC tokens. *(Same engine, small extension — DRR plan BLOCKED-ON DRR-15 row: field iteration in Steps 4/7.)*
- [ ] Also FROM tokens. *(Recommended against — only with explicit acceptance that the resolved address must satisfy the sender-domain whitelist.)*

**Blocks:** DRR story FR-4; DRR plan Steps 4/7 scope (a scope-add row, no step blocked — the baseline ships regardless). *(The token display names themselves — literals the client has never seen — are signed off under DRR-04's token-naming sub-decision.)*

---

#### DRR-16 — Vendor emails pulled from show details: in or out?
**Owner:** 🧑‍💼 BA/Client · **Tier:** 2 · **Status:** ☐ OPEN

**Plain language:** Your feedback asked for vendor emails (venue manager, decorator, electrician) pulled dynamically from a show's details. The current three-token spec doesn't include this. The data exists (`Shows.venue_manager_emails` — a comma-separated text field, admin `prisma/schema.prisma:2535`, plus `gsc_decorator_contact_email :2540`, `elctrician_contact_email :2550`), so it's buildable as a fourth source — but only if you confirm it's wanted now.

**Answer options:**
- [ ] **Formally defer it — not in this release. (recommended)** Keeps the release scope at the confirmed three tokens; adding later is a registry entry, not a redesign (DRR plan BLOCKED-ON DRR-16).
- [ ] Build it now as a fourth dynamic source *(confirm the comma-separated field is to be split into individual recipients)*.

**Blocks:** DRR story FR-24 (scope-add; no plan step blocked).

---

#### P9-1 — Which existing triggers may ever be scheduled? (the `supports_scheduling` backfill set)
**Owner:** 🧑‍💼 BA · **Tier:** 2 · **Status:** ☐ OPEN

**Plain language:** The scheduler only lets an admin put a schedule on a trigger that has been explicitly opened for scheduling. The scheduling plan *recommends* opening six existing triggers (`cart_updated_notification`, `ppl_product_order_payment`, `lead_daily_summary`, `lead_credits_renewed`, `company_user_invitation`, `ppl_subscription_canceled`) — but opening a trigger is a **product decision about which events may ever be scheduled**, and it needs confirming before it's seeded. (The reminder examples devs actually author live on *new* triggers seeded open by design.)

**Answer options:**
- [ ] **Confirm the six recommended slugs as the backfill set. (recommended)** It's the plan's own vetted recommendation (scheduling plan §9 first bullet / §2.0.4 step 3b).
- [ ] Amend the set *(free text: add/remove slugs)*:
> ______________________________________________________

**Blocks:** the scheduling build's trigger-gate backfill seeding (scheduling plan §2.0.4 step 3b, carried as §9 open item P9-1). Not release-gating — an unconfirmed slug simply stays unschedulable.

---

## B. External provisioning & long-lead items (owner: Client/DevOps)

*Accounts, carrier registration, sender identity, Google groups. These are the release's calendar risks — start them day one.*

---

#### SMS-01 — Confirm HOW we send texts (and who owns the account)
**Owner:** 🌐 Client/BA · **Tier:** 0 (day-one question; kicks off the Tier-1 long pole) · **Status:** ☐ OPEN

**Plain language:** You named **SendGrid** as the SMS provider. SendGrid is our email carrier already — but **SendGrid's API is email-only; it cannot send a text message**. In that vendor family, texts are sent by **Twilio Programmable Messaging** (Twilio owns SendGrid). Think of it as one company with two counters: SendGrid is the email counter, Twilio is the SMS counter. We will not silently assume this — please confirm it. We also need to know **who owns the account**: do you create/own the Twilio account and hand us credentials, or do we (UIPL) provision it?

**Answer options:**
- [ ] **Twilio Programmable Messaging, same vendor family. (recommended)** The only feasible in-family mechanism (SMS story §4.1; gap analysis SMS-01; no Twilio/other SMS SDK exists in any repo today — grep `twilio|nexmo|vonage|plivo` = zero hits).
- [ ] A different mechanism/provider *(name it — the SMS plan's Phases A/E/G re-plan, `PLAN_BLOCKED`)*.

**Account & number ownership (free text):**
> Account owner (client vs UIPL): ______________ · Billing owner: ______________ · Who hands whom credentials: ______________

**Blocks:** SMS plan Steps A1 (account + registration kickoff), E1/E2 (SDK + credentials), G1 (webhook signature scheme) — BLOCKED-ON SMS-01; spine milestone MS0(a) — **on confirmation, Twilio account creation + A2P 10DLC registration starts immediately: this is the release long pole** (days-to-weeks; carriers block 100% of unregistered 10DLC traffic since Feb 2025). Also half-resolves SMS-09 (Twilio ⇒ status-callback webhooks) and narrows SMS-08.

---

#### SMS-08 — Sender identity + who performs the carrier registration (10DLC)
**Owner:** 🌐 Client · **Tier:** 1 (long-lead — start on SMS-01 confirmation) · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** Every business text needs a registered "from" — like a license plate for your messages. US carriers require A2P 10DLC **brand + campaign registration** (your company identity + the kind of messages you send) before a single production text is allowed — unregistered traffic is **blocked outright**, not slowed. Registration takes **days to weeks**, so it must start the moment SMS-01 is confirmed. We need: what kind of number (ordinary long code / toll-free / short code), and **who executes the registration** — you or us.

**Answer options (sender identity):**
- [ ] **One global Messaging Service pooling one or more 10DLC-registered long codes; no per-template sender. (recommended)** Simplest compliant setup; per-template senders can be added later if ever needed (SMS plan DD-15; SMS story FR-10).
- [ ] Toll-free number (toll-free verification path instead of 10DLC).
- [ ] Short code (higher cost/lead time).
- [ ] Per-template sender identities *(adds a `sender_id` key to the SMS config — new scope)*.

**Registration executor + brand details (free text):**
> Who registers (client vs UIPL): ______________ · Legal entity/brand info owner: ______________ · Target campaign use-case description: ______________

**Blocks:** SMS plan Step A1 (registration owner); **production launch gate** spine MS9(4) / SMS story AC-16 ("no production SMS before 10DLC brand + campaign registered and the Messaging Service/number provisioned"); SMS story §9 step 7.

---

#### DRR-03 — Google (Gmail) groups: just an address, or must we know the members?
**Owner:** 🌐 Client · **Tier:** 1 (only becomes long-lead if you pick expansion) · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** When an admin adds an "internal Gmail group" as a recipient, there are two very different builds. (a) We treat the group like a **mailing-list address on an envelope**: we send to `team@yourcompany.com`, and Google delivers to whoever is in the group that day. Simple, no credentials, always current. (b) We **look inside the group** and list its members ourselves — that requires a Google Workspace Directory integration, a service account you'd have to provision, and ongoing credentials. The story's "group with no members" check is only possible under (b); under (a) an empty group just behaves like a normal bounced address.

**Answer options:**
- [ ] **(a) Literal address — store the group's email address, Google expands it on delivery. (recommended)** No external integration, no credentials, membership always current; the empty-group case re-scopes to normal bounce handling (DRR story FR-9; DRR plan DD-7).
- [ ] (b) Membership expansion via Google Workspace Directory API. *(Materially larger build — service-account credentials, group mirror storage; DRR plan Step 4 re-plans. If chosen: who provisions the credentials?)*
> Credentials owner (if (b)): ______________________________________________________

**Blocks:** DRR plan Step 4 (`gmail_group` resolver — BLOCKED-ON DRR-03); DRR story FR-9/AC-11.

---

## C. Recipient resolution semantics — DRR (mixed owners)

*Who exactly the smart tokens resolve to, what happens when they can't resolve, and where SMS phone resolution sits. Defaults are built now (DRR plan BLOCKED-ON table); answers confirm or adjust.*

---

#### DRR-01 — Who is "the salesperson"?
**Owner:** 🧑‍💼 BA · **Tier:** 2 · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** The `{salesperson}` token must point at a real database field. The only salesperson link that exists is **on an order** (`Order.sales_person_id` → that user's email; admin `prisma/schema.prisma:1615/1634`) — and it can be empty. There is **no** salesperson on a company or exhibitor; the "strategist" and "referred-by" fields are different roles. So: for messages not connected to an order (welcome, forgot-password…), there is no salesperson to find.

**Answer options:**
- [ ] **`{salesperson}` = the order's salesperson; the token is only offered on order-related triggers; strategist/referred-by are NOT stand-ins; if the order has no salesperson the normal fallback applies (DRR-06). (recommended)** The only truthful mapping in the data (DRR story §3.2/FR-6; DRR plan DD-3).
- [ ] A different source per trigger *(free text — name the field per trigger)*:
> ______________________________________________________

**Blocks:** DRR plan Step 4 (`{salesperson}` resolver — BLOCKED-ON DRR-01); DRR story FR-6, AC-2/AC-5/AC-6.

---

#### DRR-02 — Who counts as the "main" and "all" customer contacts?
**Owner:** 🧑‍💼 BA · **Tier:** 2 · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** A company on the platform has one **primary account holder** and possibly several **invited members** (some accepted, some still pending, some revoked, some deleted). We propose: `{main customer contact}` = the primary account holder; `{all customer contacts}` = the primary **plus accepted** invited members — never pending, revoked or deleted ones. (This mirrors how the codebase already picks the "main contact" as a fallback — `admin-backend-api/src/admin/orders/services/order-notification.service.ts:196-199`.) The related database fix (D2, section G) makes multiple contacts per company officially correct.

**Answer options:**
- [ ] **Main = primary account holder (`user_type=1`); All = primary + accepted invited members; exclude pending/revoked/deleted. (recommended)** Matches the existing precedent and never emails someone who left or never joined (DRR story §3.2/FR-7/FR-8; DRR plan DD-3).
- [ ] Include pending invitees in "all".
- [ ] Include revoked members in "all". *(Recommended against — they were deliberately removed.)*

**Blocks:** DRR plan Step 4 (contact resolvers — BLOCKED-ON DRR-02); DRR story AC-7 (the 1-primary + 2-accepted + 1-revoked + 1-deleted ⇒ exactly-3 test). `{all customer contacts}` additionally hard-requires the D2 schema fix (section G).

---

#### DRR-04 — The trigger→token matrix (which emails may use which tokens)
**Owner:** 🧑‍💼 BA · **Tier:** 2 · **Status:** ☐ OPEN (mechanism PROPOSED; the matrix itself is the deliverable)

**Plain language:** Not every email can use every token — a forgot-password email has no order, so `{salesperson}` is meaningless there. The *mechanism* is decided (each trigger declares which tokens it offers; the editor only shows those — like a form that only offers fields that make sense). What we need **from you** is the concrete table: for each of the ~40 triggers, which of the three tokens (and Gmail groups) it may offer, **and** whether the trigger is *transactional* (customer-critical, e.g. order confirmation) or *marketing/reminder* — that classification drives the zero-recipient behavior in D3.

**Answer needed (free text — the matrix, deliverable of the BA session):**
> Trigger slug → offered tokens → transactional or marketing
> ______________________________________________________

**Mechanism sign-off:**
- [ ] **Tokens are un-offerable at config time on triggers that structurally lack the needed context (order/company id); send-time data gaps fall to the DRR-06 fallback. (recommended)** Prevents mis-configuration at the source (DRR story §3.4/FR-19; DRR plan Step 3, DD-6).

**Token-naming sign-off (part of this session — do not let the names freeze into the UX unseen):**
- [ ] Token display names `{main customer contact}`, `{all customer contacts}`, `{salesperson}` confirmed **as-is** — the client has never seen these literals (they first appear in the Updated Epic, not in the client's May-2026 thread; DRR story §2 reconciliation note ties this naming sign-off to the DRR-04/DRR-15 sessions).
- [ ] Renamed *(state the new display names)*: ______________

**Blocks:** DRR plan Step 3 (seeder rows ship flagged `// BA-PENDING` until the matrix lands) and **Step 15.4** — `DRR_LIVE_SEND_ENABLED` is not flipped while BA-PENDING rows remain on token-bearing triggers (spine §1.3 row 3; spine §4 gate C last item).

---

#### DRR-05 — At send time, what is the authoritative recipient source for live triggers?
**Owner:** 🧑‍💼 BA · **Tier:** 2 · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** Today, the recipients a template *stores* are never actually used — every live email computes its recipients in code, and the stored configuration is write-only. DRR makes stored config real. We propose: for **custom** templates the stored recipient configuration becomes the single source of truth at send time; **predefined** (system-seeded) templates keep their code-computed recipients and stay out of DRR; and we **never merge** the two (merging is how people get double-emailed or silently dropped).

**Answer options:**
- [ ] **Custom templates: stored config wins, no merge. Predefined templates: unchanged, out of DRR scope. (recommended)** Clean ownership; consistent with the retired predefined-DRR variant (KNOWN_ISSUES #3 / DRR-14) (DRR story §3.5/FR-13; DRR plan DD-12).
- [ ] Merge stored config with code-computed recipients. *(Recommended against — the double-send/dropped-recipient risk the gap analysis warns about; Step 10 would be re-planned, a re-design not a tweak.)*
- [ ] Predefined templates also move to stored config. *(Re-opens the retired variant — new scope.)*

**Blocks:** DRR plan Step 10 (live-send consumption point — BLOCKED-ON DRR-05); DRR story FR-13, AC-4.

---

#### DRR-06 — What happens when a recipient can't be resolved?
**Owner:** 🧑‍💼 BA · **Tier:** 3 · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** Sometimes a token finds nobody (the order has no salesperson). Options: quietly skip that one recipient and continue to the others (logging it), substitute some default address, or cancel the whole send. There is **no default address anywhere** in the system, and inventing one risks sending customer email to the wrong person.

**Answer options:**
- [ ] **Skip that entry, log it with a reason, continue with the remaining valid recipients; never substitute a default address. (recommended)** Matches the scheduler's existing precedent and the Confluence rule "must not fail the entire dispatch unless no valid recipient remains" (DRR story §3.7/FR-15; DRR plan DD-6).
- [ ] Substitute a default address *(which one? none exists today)*: ______________
- [ ] Abort the whole send on any unresolved entry.

**Blocks:** DRR plan Steps 6/10/11 disposition mapping (BLOCKED-ON DRR-06/D3); DRR story AC-6. The zero-recipient boundary case is D3 (below).

---

#### DRR-07 (/P9-5) — What backs the "predefined lists" — especially "other relevant system emails"?
**Owner:** 🧑‍💼 BA · **Tier:** 2 · **Status:** ☐ OPEN — **no default we are willing to assume**

**Plain language:** The agreed recipient picker includes "admin users, exhibitors, and other relevant system emails" (client-accepted, Amrin 18-May). Admin users and exhibitors plausibly come from their existing listing screens — but **"other relevant system emails" has no identifiable source anywhere** (this is base known-issue #4, carried in the scheduling plan as §9 item P9-5). Until you name the sources, the list-picker ships **visible but empty** ("no predefined lists available").

**Answer needed (free text):**
> Admin-user list source: ______________ · Exhibitor list source: ______________ · "Other relevant system emails" = what exactly, maintained by whom: ______________ · Live query vs managed config table vs static seed: ______________

**Blocks:** DRR plan Steps 4/7 (`list_ref` resolvers — BLOCKED-ON DRR-07: ships as a validated-but-empty kind until sources are named); DRR story FR-10. **Not release-gating** (spine §6).

---

#### DRR-08 — If the same person lands in To and Cc, who wins?
**Owner:** 🧑‍💼 Client · **Tier:** 3 · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** Tokens can resolve the same person into more than one field. Our rule: keep the person in the **most prominent** field only — To beats Cc beats Bcc — matching addresses case-insensitively, and also remove duplicates within the To line itself.

**Answer options:**
- [ ] **TO > CC > BCC precedence, case-insensitive matching, within-field dedup too. (recommended)** Matches the mailer's existing low-level dedup so the two layers agree (`admin mailer.service.ts:85-144`; DRR story §3.7/FR-17; DRR plan DD-10).
- [ ] A different precedence *(state it)*: ______________

**Blocks:** DRR plan DD-10 / Step 10 compile rule (BLOCKED-ON DRR-08); DRR story AC-10.

---

#### DRR-09 — SMS recipient resolution: confirm the ownership split (and null-phone behavior)
**Owner:** 🧑‍💼 BA · **Tier:** 3 · **Status:** ☐ OPEN (largely adjudicated by review M4; confirm the residue)

**Plain language:** Story 76.8 says "SMS recipients come from DRR"; story 77.9 as written is email-only — a circular reference. The external review broke it (M4, binding): **email DRR ships first and owns the engine; SMS then reuses the same engine extended to a phone field** — no second resolver, ever. What remains to confirm: that split, plus what happens when a resolved contact has an email but **no usable phone** for an SMS send.

**Answer options:**
- [ ] **77.9 owns the engine + the phone-ready interface; 76.8 owns phone consumption (per M4). A contact with no usable phone = unresolved entry (skip + log, fail-closed) — never texted at a guessed number, never emailed instead. (recommended)** The engine's fail-closed projection already implements this (DRR plan DD-11; SMS story FR-6/FR-7).
- [ ] Fall back to email when the phone is missing. *(Channel substitution — new scope, recommended against.)*

**Blocks:** DRR plan Step 4 interface seam + Step 15 / SMS plan Step F1 (BLOCKED-ON DRR-09/SMS-01); DRR story FR-21/AC-19. The per-trigger *which phone field* mapping is SMS-07 (below).

---

#### DRR-11 — What may be typed into a recipient field (and what if resolution yields a bad address)?
**Owner:** 🧑‍💼 BA · **Tier:** 3 · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** Loosening today's strict "emails only" validation must not open the door to arbitrary text. Proposed grammar: exactly the three tokens, typed group/list entries, and real email addresses — nothing else. And if a token resolves to a *malformed* stored address, we treat it like an unresolved recipient (skip + log) rather than handing garbage to the mail provider.

**Answer options:**
- [ ] **Closed grammar (3 tokens + typed group/list entries + RFC 5322 addresses); resolved-but-invalid ⇒ treated as unresolved. (recommended)** Fail-closed and injection-safe (DRR story §3.7/FR-14; DRR plan Step 4 pipeline step 5, Step 7 validators).
- [ ] A looser/stricter grammar *(state it)*: ______________

**Blocks:** DRR plan Steps 4/7 (BLOCKED-ON DRR-11); DRR story AC-3/AC-9.

---

#### DRR-12 — Who may attach groups and bulk-contact tokens (privacy)?
**Owner:** 🧑‍💼 Client · **Tier:** 2 · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** `{all customer contacts}` can reveal every contact of a company, and the preview screen shows resolved real addresses. Should this power be limited to particular admin roles, or is the existing "can edit templates" permission enough?

**Answer options:**
- [ ] **The existing template-edit permission is sufficient; no extra role gate. (recommended)** The preview only shows addresses an admin could already see in the source modules (DRR story §4/FR-23; DRR plan DD-14).
- [ ] Restrict to specific roles *(name them)*: ______________ *(Enforced in the config endpoints + preview guard only — nothing structural.)*

**Blocks:** DRR plan Step 9 (preview guard — BLOCKED-ON DRR-S1/DRR-12); DRR story AC-17.

---

#### DRR-S1 — Preview: how is the sample record chosen?
**Owner:** 🧑‍💼 BA · **Tier:** 3 · **Status:** ☐ OPEN (default PROPOSED — new question raised by the refined story)

**Plain language:** The editor gets a "who will this go to?" preview. It needs a sample case to resolve against — we propose the admin picks a recent real record (e.g. an actual order) from a search field, and the preview runs read-only under the same permission as template editing.

**Answer options:**
- [ ] **Admin picks a recent real anchor record; preview read-only, template-edit permission. (recommended)** Uses the real engine on real data with no sends and no new permission model (DRR story FR-22; DRR plan DD-14).
- [ ] Synthetic/sample data instead of real records. *(Weaker preview — wouldn't catch real data gaps.)*

**Blocks:** DRR plan Step 9 (BLOCKED-ON DRR-S1/DRR-12); DRR story AC-17.

---

#### D3 — When a send would reach nobody: quiet skip or loud alarm?
**Owner:** 🧑‍💼 BA (external-review adjudication to confirm) · **Tier:** 2 · **Status:** ☐ OPEN (default PROPOSED per validation report D3)

**Plain language:** If, after resolution, a message has **zero** valid recipients, we never "send to nobody". The question is how loudly to fail. The reviewer's recommendation, which we adopted: for routine/marketing reminders, skip quietly and log it; for **transactional** messages (order confirmations, refunds — things a customer must receive), abort **and raise an alert** so a human sees it — a customer-critical email vanishing with only a log line is exactly the harm to prevent. Which triggers count as "transactional" is part of your DRR-04 matrix.

**Answer options:**
- [ ] **Marketing/reminder ⇒ skip-and-log; transactional ⇒ abort-and-alert; never send to zero. (recommended)** External-review adjudication (validation report D3), built as the engine's disposition (DRR plan DD-6; DRR story FR-16/AC-8; SMS inherits it — SMS story FR-6/AC-10).
- [ ] Same behavior for all triggers *(state which)*: ______________

**Blocks:** DRR plan Steps 6/10/11 disposition mapping; SMS plan Step D2 (escalation); the alert rides the scheduling addendum's S3 channel (addendum §3(c)4).

---

#### SMS-07 — Which phone number is "the recipient" for each SMS trigger?
**Owner:** 🧑‍💼 BA · **Tier:** 2 · **Status:** ☐ OPEN (boundary PROPOSED per M4; the mapping is the deliverable)

**Plain language:** Phone numbers live in several places (the exhibitor's profile phone, an order's billing phone, admin-entered lists…). For each trigger on the SMS-06 list we need to know **which stored phone** gets the text. Default starting point: the exhibitor's profile phone (`Exhibitor.phone`, admin `prisma/schema.prisma:1029`) for exhibitor-facing texts.

**Answer needed (free text — column added to the SMS-06 table):**
> Trigger → phone field (e.g. Exhibitor.phone / Order.billing_phone / admin-entered list)
> ______________________________________________________

**Boundary sign-off:**
- [ ] **Phones are resolved by the one shared engine via allow-listed phone columns — never an SMS-specific lookup. (recommended)** The release's shared-spine rule (SMS story FR-6; SMS plan DD-3/Step F1; DRR plan DD-11; spine §1.1.2 step 4).

**Blocks:** SMS plan Step F1 (allow-list phone columns — BLOCKED-ON SMS-06/SMS-07); SMS story §9 step 4-adjacent seeding; spine dependency-matrix row 14.

---

## D. SMS compliance & delivery (mixed owners)

*Consent, quiet hours, rendering, retries, credentials — the texting rulebook. Defaults are built dark behind the kill switch; most rows are sign-offs.*

---

#### SMS-03 — The consent policy: who has agreed to be texted?
**Owner:** 🧑‍💼 Client · **Tier:** 1 (legal decision — start early) · **Status:** ☐ OPEN — **no US go-live without it**

**Plain language:** US law (TCPA) treats text messages far more strictly than email — texting someone without the right kind of permission creates real legal exposure. Today the platform stores **no record of SMS consent anywhere**. We need your policy: **which entity holds consent** (the user? the exhibitor? the phone number itself?) and **whether prior express consent is required** before we text. Regardless of the answer, we are building the safety net now: a suppression list honoring opt-outs from *any reasonable method* (STOP replies, emails, phone calls), state-aware quiet hours, and consent records kept **at least 5 years** — those are required under every possible policy (validation report M2).

**Answer options:**
- [ ] **Prior express consent required; consent recorded per phone number, linked to the exhibitor/user where known. (recommended)** The conservative, defensible posture; matches the append-only `sms_consent_events` design (SMS plan DD-8/Step D1; SMS story FR-9).
- [ ] Existing-business-relationship basis without explicit opt-in *(confirm with your counsel — still requires suppression + quiet hours)*.
- [ ] Other *(describe)*: ______________

**Legal/compliance contact (free text):**
> ______________________________________________________

**Blocks:** SMS plan Step D1 consent-capture flow (BLOCKED-ON SMS-03 — the tables build regardless); **production go-live** — SMS story §9 step 6, spine §4 gate D ("SMS-03 consent policy recorded — no US go-live without it"), spine MS9(4).

---

#### SMS-04 — Where do SMS credentials and settings live? (no admin config screen)
**Owner:** ✅ BA sign-off · **Tier:** 3 · **Status:** ☐ OPEN (default PROPOSED, built)

**Plain language:** We propose keeping provider credentials where all our other provider secrets live (server environment + AWS Secrets — exactly like the email provider today), with behavioral knobs (kill switch, quiet-hour windows) in the existing settings store. **No admin-facing provider-configuration screen** this release.

**Answer options:**
- [ ] **Env + AWS Secrets for credentials; `ppl_settings` for tunables; no config UI. (recommended)** Mirrors the SendGrid precedent exactly (`background-worker-service/src/config/env.validation.ts:28-29`); SMS plan DD-2; SMS story FR-2/§5, AC-2.
- [ ] An admin provider-config screen is required. *(New scope — outside the current estimates; must be Admin-role gated per V2.)*

**Blocks:** SMS plan Step E1 / DD-2 sign-off (BLOCKED-ON SMS-04).

---

#### SMS-09 — Delivery receipts & retries: sign off the webhook + taxonomy
**Owner:** ✅ BA sign-off · **Tier:** 3 · **Status:** ☐ OPEN (half-resolved by SMS-01; default PROPOSED, built)

**Plain language:** Once Twilio is confirmed (SMS-01), delivery outcomes arrive as **status callbacks** (webhooks) — that half answers itself. What needs sign-off: the receiver (a signed public endpoint in our external API service, same recipe as our Stripe webhooks) and the retry policy (temporary provider errors retry on the scheduler's existing 5m/30m/2h backoff, max 3; permanent errors — bad number, suppressed recipient — fail immediately, no retry; immediate sends are single-attempt like email).

**Answer options:**
- [ ] **Twilio status-callback webhook receiver + the scheduler's existing transient/hard retry taxonomy, no new state machine. (recommended)** Third instance of the established webhook recipe (`external-api-service/src/modules/webhook/controllers/webhook.controller.ts:36-56`); SMS plan DD-11/DD-12/Step G1; SMS story FR-12, AC-19/AC-20.
- [ ] Polling instead of webhooks / a different retry policy *(state it)*: ______________

**Blocks:** SMS plan Step G1 / DD-11 sign-off (BLOCKED-ON SMS-09).

---

#### SMS-10 — Text length & rendering policy
**Owner:** ✅ BA sign-off · **Tier:** 3 · **Status:** ☐ OPEN (default PROPOSED, built)

**Plain language:** Texts are plain text (no subject line, no branded layout). One SMS "segment" is 160 characters (70 if emoji/unicode); longer messages are split and each segment is billed. Proposal: warn the template author above one segment; allow up to **3 segments (~459 characters)**; a message that would exceed 3 segments after token substitution **fails cleanly** (logged, not sent) rather than being cut off mid-sentence.

**Answer options:**
- [ ] **Plain text; warn above 1 segment; hard cap at 3 segments — over-cap fails, never truncates. (recommended)** Predictable cost, never a garbled half-message (SMS plan DD-6; SMS story FR-5, AC-6/AC-7).
- [ ] Truncate instead of fail. *(Risks cut-off confirmations.)*
- [ ] A different cap: ______ segments.

**Blocks:** SMS plan Step E2 / DD-6 sign-off (BLOCKED-ON SMS-10).

---

#### SMS-11 — Phone-number cleanup & the bad-number fallback
**Owner:** ✅ BA sign-off · **Tier:** 3 · **Status:** ☐ OPEN (default PROPOSED, built)

**Plain language:** Stored phone numbers are inconsistent (some malformed — the data was validated "fail-open"). Before sending we normalize each number to the international format carriers require (+1XXXXXXXXXX for US/CA). If a number is missing or can't be normalized: **skip that recipient and log it** — never text a guessed/default number, never cancel the other recipients; for transactional triggers the D3 alarm applies.

**Answer options:**
- [ ] **Normalize US/CA to E.164 at dispatch; invalid/missing ⇒ skip + log (`"invalid or missing phone number"`); transactional escalates per D3. (recommended)** Safe under known-dirty data (`PHONE_DIGITS_REGEX`, `is-valid-phone.validator.ts:16`; SMS plan DD-7; SMS story FR-7, AC-9).
- [ ] A default fallback number *(which? recommended against)*: ______________
- [ ] Abort the trigger on any bad number.

**Blocks:** SMS plan Step E2 / DD-7 sign-off (BLOCKED-ON SMS-11).

---

#### SMS-14 — Bulk sends & the no-live-send safety mode
**Owner:** 🧑‍💼 BA · **Tier:** 3 · **Status:** ☐ OPEN (default PROPOSED, built; bulk half stays with SMS-06)

**Plain language:** The provider's Messaging Service already queues and paces texts against carrier throughput caps. We propose **no extra platform-side queue** unless some trigger genuinely fires in bulk (thousands at once) — do any? Separately (already built as a default): a kill switch (`sms_sending_enabled`, default **off**) plus Twilio *test* credentials in dev/QA guarantee no accidental live texts — the same switch is the production launch lever and the fastest rollback.

**Answer options:**
- [ ] **Provider-side pacing only; kill switch + test credentials as the sandbox mode. (recommended)** SMS plan DD-15/FR-15; SMS story FR-14/FR-15, AC-16.
- [ ] A bulk trigger exists *(name it — adds a platform-side queue, new scope)*: ______________

**Blocks:** SMS plan DD-15 / Step E3 throttling posture (BLOCKED-ON SMS-14).

---

#### SMS-15 — SMS templates: seeded predefined only; sign off the config shape
**Owner:** ✅ BA sign-off · **Tier:** 3 · **Status:** ☐ OPEN (default PROPOSED, built)

**Plain language:** SMS templates cannot even be created today (the code hard-blocks them). Proposal: unlock **predefined (system-seeded)** SMS templates — one per trigger on your SMS-06 list — while **custom** SMS templates remain out of scope; SMS templates have no subject line and a defined config shape (recipient phone specs; no per-template sender).

**Answer options:**
- [ ] **Seed predefined SMS rows per the SMS-06 list; custom SMS stays blocked; `SmsChannelConfigDto` shape as specified. (recommended)** One-place channel unlock (`SUPPORTED_TEMPLATE_CHANNELS`, `notification-template.dto.ts:27`); honors the existing dormant guard (`notification-template.service.ts:408-416`); SMS plan DD-14/Steps C1–C3; SMS story FR-3/FR-4, AC-3/AC-4/AC-5.
- [ ] Also unlock custom SMS templates. *(Contradicts the V2 two-epic model and scheduling story AC-14 — new scope.)*

**Blocks:** SMS plan Steps C1/C2 sign-off (BLOCKED-ON SMS-15).

---

#### SMS-S1 — Do quiet hours apply to *instant* texts too?
**Owner:** 🧑‍💼 BA/Client · **Tier:** 2 · **Status:** ☐ OPEN (new question raised by the refined story; not launch-blocking)

**Plain language:** *Scheduled* texts that would land in a recipient's legal quiet window (state-dependent, roughly "not before 8am, not after 8–9pm") are automatically **deferred** to the next allowed time. But if a trigger ever fires an **instant** text at 11pm (say, an order confirmation), should we hold it until morning, or send immediately on the theory that transactional messages are exempt? Today's launch scope has **no instant SMS trigger**, so this is safe to answer later — but it must be answered before one goes live.

**Answer options:**
- [ ] **Hold-and-release: instant texts inside a quiet window wait for the window to open. (recommended)** The conservative reading; the enforcement point is already channel-generic so this is configuration, not rework (SMS plan DD-9; SMS story FR-9/AC-14).
- [ ] Transactional exemption: instant transactional texts send immediately at any hour *(confirm with counsel)*.

**Blocks:** SMS plan Step D2 immediate-path enforcement (BLOCKED-ON SMS-S1). Not on the launch critical path (no immediate SMS trigger in scope).

---

#### SMS-S2 — Do *internal/staff* phone lists follow the same texting rules?
**Owner:** 🧑‍💼 BA/Client · **Tier:** 2 · **Status:** ☐ OPEN (new question raised by the refined story)

**Plain language:** Some SMS recipients may be your own staff (e.g. the admin-entered "text these numbers when this product is purchased" lists). Do staff numbers get the same consent / opt-out / quiet-hours protection as customers, or is there an internal-recipient exemption? This decides whether the dormant Product flag (SMS-06) could go live without customer-grade consent capture.

**Answer options:**
- [ ] **No exemption — internal recipients follow the same suppression/consent/quiet-hours rules. (recommended)** One rulebook, no accidental compliance gap (SMS plan BLOCKED-ON SMS-S2 default).
- [ ] Internal exemption *(define "internal" precisely)*: ______________

**Blocks:** SMS plan Steps C3/D2 for internal-recipient handling (BLOCKED-ON SMS-S2); interacts with the SMS-06 dormant-Product-flag decision.

---

## E. Scheduling hardening decisions (owner: Tech Lead/Eng — from the addendum + review §6)

*The three open decisions the external review left with the scheduling deltas. Each has a stated default that applies if unanswered (addendum §11).*

---

#### ADD-Q1 (maps to S2) — Accept "at-least-once" delivery, or design provider-side idempotency now?
**Owner:** 🛠️ Tech Lead + BA · **Tier:** 3 · **Status:** ☐ OPEN (default applies if unanswered)

**Question:** The dispatch pipeline is explicitly **at-least-once**: in the rare reaper-vs-slow-send race, a recipient can get the same *email* twice (the claim is `FOR UPDATE SKIP LOCKED`; the reaper tail-risk is the accepted residual — addendum §2). Is that acceptable for these transactional-volume emails, or must a provider-side idempotency mechanism (SendGrid idempotency, or a `NotificationLog` pre-insert keyed on `dedupe_key`) be designed in now?

**Answer options:**
- [ ] **Accept at-least-once; state it verbatim in the service doc-comment; no send-side dedupe now. (recommended)** The review calls this "usually acceptable" at this volume (validation report S2/§6; addendum §2(c)3-4).
- [ ] Design provider-side idempotency in now *(extends the X2 reaper test to assert provider-boundary suppression — addendum §9 case 2)*.

**Note:** **SMS already gets stronger protection regardless** — duplicate texts are costlier, so SMS dispatch layers a platform short-circuit + provider idempotency keyed on `dedupe_key` (SMS plan DD-10/AC-23). This question is about the **email** path only.

**Blocks:** addendum §2(c)4 (deferred send-side dedupe) and the conditional extension of X2 verification case 2 (addendum §9).

---

#### ADD-Q2 (maps to S3) — Catch-up policy model: one explicit per-rule switch, or also per-kind defaults?
**Owner:** 🛠️ Tech Lead + BA · **Tier:** 3 · **Status:** ☐ OPEN (default applies if unanswered)

**Question:** After downtime, stale occurrences are skipped ("missed send window") unless their rule says "send late anyway" (`catchup_policy: SKIP|SEND`, per-rule, default SKIP — addendum §3). Model (A): just that one explicit column. Model (B): additionally give rule *kinds* smart defaults (proximity reminders → SKIP; follow-up/payment rules → SEND) so authors get the right behavior without thinking.

**Answer options:**
- [ ] **(A) Single default SKIP + per-rule override only. (recommended)** One explicit column, no hidden kind-based behavior (addendum §3(e)).
- [ ] (B) Additionally per-kind DTO defaults (proximity → SKIP; FOLLOW_UP/payment → SEND).

**Blocks:** the `ScheduleRuleDto` default wiring in scheduling Phase 3 (addendum §3(c)3).

---

#### ADD-Q3 (maps to S4) — Defer the "unanswered product questions" recurring reminder?
**Owner:** 🧑‍💼 BA · **Tier:** 2 · **Status:** ☐ OPEN (default applies if unanswered)

**Plain language:** One client template is a recurring reminder that repeats **until the customer answers their product questions**. The data needed to know "answered or not" isn't modelled yet, and neither is the query that finds which orders need the reminder. The review recommends parking this one template with the other already-parked items (show/workshop reminders) — the machinery ships and is tested, only this template waits for its data.

**Answer options:**
- [ ] **(a) Defer the template alongside the show/workshop anchors; the per-instance recurring machinery still ships, exercised by tests. (recommended)** "Keeps Phase 4 honest" (validation report S4; addendum §4).
- [ ] (b) It must ship this build. *(Then before coding: model/locate the answer table, spec the instance-discovery query in the story, and keep the mandatory `end_window_at` bound — addendum §4(c)4. Do not start (b) without this in writing.)*

**Blocks:** scheduling Phase 4 scope (addendum §4(d)); plan §9/P9-6 residual (`QUESTION_ANSWERED` stays `[dep]`).

---

## F. Cross-track integration contracts (owner: Tech Lead)

*The shared-spine decisions: resolve timing, the one NotificationLog migration's shape, and migration timing.*

---

#### D1 (adjudicates DRR-13) — Recipient freshness for scheduled sends: confirm "both, selectable"
**Owner:** 🧑‍💼 BA (externally adjudicated — formal sign-off) · **Tier:** 0 · **Status:** ☐ OPEN (built per adjudication regardless)

**Plain language:** Story 77.9 says "always use the most current recipients at send time"; the approved scheduler freezes recipients when the send is *prepared* and replays them verbatim — like printing wedding invitations from the guest list on printing day versus re-checking the list at the door. The external review (D1, HIGH) resolved this the way mature senders (e.g. Klaviyo) do: **freeze-at-prepare is the default for every rule; freshness is a per-rule opt-in switch** (`resolve_at_send`) — when on, the occurrence stores a *reference* and the engine re-resolves at the moment of sending. The switch is unavailable until DRR ships and is mutually exclusive with timezone-accurate sending. Live (non-scheduled) triggers always resolve fresh — no conflict there. **DRR-13 is this same question** and is carried as adjudicated-pending-your-sign-off; the expected answer is "both, selectable".

**Answer options:**
- [ ] **Both, selectable — default snapshot-at-materialize; per-rule `resolve_at_send` opt-in. (recommended)** External adjudication adopted release-wide; zero scheduler redesign; SMS inherits it with no variance (spine §1.1.3; DRR story §3.6/FR-12, AC-12/13/14; DRR plan DD-5; validation report D1/§6).
- [ ] Pure snapshot only, staleness documented. *(Then DRR plan Step 6 ships dark — column + rejection stay, branch removed.)*
- [ ] Always re-resolve at send. *(Rejected by the review — incompatible with tz-accurate sending and would reopen the approved scheduler's dispatch design.)*

**Blocks:** DRR plan Steps 5/6 (BLOCKED-ON D1/DRR-13); spine §1.1.3 formal sign-off; scheduling dispatcher's one new branch.

---

#### SPINE-Q1 — May the unified spine migration land before SMS-02's written confirmation?
**Owner:** 🛠️ Engineering + BA · **Tier:** 0 · **Status:** ☐ OPEN (default PROPOSED)

**Question:** Review M3 sequences the unified `NotificationLog` migration "immediately after the SMS scope decision"; the DRR schedule needs it at Phase D1 regardless of SMS. May it land with DRR Phase D1 even if SMS-02's written confirmation is still pending?

**Answer options:**
- [ ] **Yes — land it with DRR Phase D1. (recommended)** Every column serves DRR alone except `channel`, whose NOT-NULL-default-`'EMAIL'` is correct and inert even if SMS-02 comes back "no"; M3's intent was ordering relative to *SMS send code*, which this preserves (spine §5 SPINE-Q1; spine MS3 milestone).
- [ ] No — hold the migration until SMS-02 is confirmed in writing. *(Delays DRR Phase D1 and everything downstream of M3.)*

**Blocks:** spine milestone MS3 timing; DRR plan Step 1 start date.

---

#### SMS-05 — Sign off: extend `NotificationLog`, never a separate SMS log table
**Owner:** ✅ BA/Engineering sign-off · **Tier:** 2 (due at the Phase D0 migration co-design freeze) · **Status:** ☐ OPEN (default PROPOSED per M3 + release constraint)

**Question:** The SMS audit lands as new columns on the existing `NotificationLog` (`channel` NOT NULL default `'EMAIL'`; generalized recipient JSON recording the E.164 destination), via the release's **ONE** unified migration authored on the DRR track — not a separate SMS log table. Confirm.

**Answer options:**
- [ ] **Extend `NotificationLog` via the one unified migration (spine §1.2 is the spec of record). (recommended)** One audit surface, one query path (validation report M3; SMS story FR-11; SMS plan DD-4 — a second SMS log migration anywhere is a release-constraint violation, halt).
- [ ] A separate SMS log table. *(Violates the spine — escalate, don't build; SMS plan BLOCKED-ON SMS-05.)*

**Blocks:** SMS plan Step B1 sign-off; spine §1.2 sign-off; DRR plan Step 1.

---

#### DRR-10 — Sign off: where resolution outcomes are stored (per-dispatch JSON on `NotificationLog`)
**Owner:** ✅ BA/Engineering sign-off (joint — the shape is a JSON-column/FK/immutability decision; matches the spine §6 rollup and SMS-05/DRR-S2) · **Tier:** 2 (due at the Phase D0 migration co-design freeze) · **Status:** ☐ OPEN (default PROPOSED)

**Question:** Per-dispatch recipient-resolution audit = a JSON array on `NotificationLog.recipients` (`{field, entry, kind, resolved[], outcome, reason?}` per entry), riding the **existing** `notification_template_id` FK (already `Int` NOT NULL on every log row — admin `prisma/schema.prisma:311`; no new column) — not a new audit table, not per-recipient rows. Historical rows keep `recipients=[]` (no fabricated backfill). Immutable — no update/delete API. Confirm.

**Answer options:**
- [ ] **JSON-per-dispatch on `NotificationLog` via the unified migration. (recommended)** NotificationLog is already the named permanent audit surface and the S1 archive target (DRR story §3.8/FR-18, AC-16; DRR plan DD-8; spine §1.2 table).
- [ ] Per-recipient rows / a dedicated audit table. *(Second audit surface — contradicts the spine; re-design.)*

**Sub-decision (surfaced by the column audit):** the existing template FK is `onDelete: Cascade` (schema `:327`) — deleting a template deletes its log rows, which sits in tension with "permanent, non-editable audit".
- [ ] **Keep `Cascade` as-is this release (current behavior; template deletion is a rare, admin-controlled act). (recommended)** Zero schema change; revisit if audit permanence is formalized.
- [ ] Change to `SetNull`. *(Requires making the column nullable — an explicit ALTER of an existing column + behavior change, called out in the migration, never done silently; spine §1.2 caveat.)*

**Blocks:** DRR plan Steps 1/11 (BLOCKED-ON DRR-10/DRR-S2); spine §1.2.

---

#### DRR-S2 — Sign off: keep the legacy `email` column populated (protects the payment-reminder dedupe)
**Owner:** 🛠️ Engineering + BA · **Tier:** 2 (due at the Phase D0 migration co-design freeze) · **Status:** ☐ OPEN (default PROPOSED — new question raised by the refined story)

**Question:** The payment-reminder job de-duplicates by querying `NotificationLog.email` + slug + sent-at window (`background-worker-service/src/jobs/payment-reminder/payment-reminder.service.ts:225-233`). The unified migration therefore **keeps** the legacy `email` column and continues populating it with the first TO recipient — dropping or nulling it silently breaks that query. Alternative: migrate the dedupe query itself to the new `recipients` column (extra work, no behavior gain now). Confirm keep-and-populate.

**Answer options:**
- [ ] **Keep `email`, keep populating it (first TO recipient); regression-test the dedupe query byte-identical before/after. (recommended)** Zero-risk continuity (DRR plan DD-8; DRR story FR-18/AC-16; spine §1.2 row `email`; SMS plan Step B1 verifies).
- [ ] Migrate the payment-reminder dedupe query to `recipients` and retire `email`. *(Changes DRR plan Steps 1/11 + the AC-16 regression target — BLOCKED-ON DRR-10/DRR-S2 row.)*

**Blocks:** DRR plan Steps 1/11; spine §4 gate C first item; SMS plan Step B1 verification (c).

---

## G. Data & schema sign-offs (owner: Tech Lead / DBA-ish)

*Schema corrections and storage-shape decisions that ride the release.*

---

#### D2 — Approve the five-schema `Exhibitor.company_id @unique` drop (standalone fix)
**Owner:** 🛠️ Engineering + BA · **Tier:** 3 (executed "decoupled — do soon") · **Status:** ☐ OPEN (approval of a specified fix)

**Question:** All five `schema.prisma` files declare `Exhibitor.company_id @unique` (admin/exhibitor/external `:1030`, worker/pulse `:944`), but the real DB has only a plain index and multi-member companies are real (the invite flow deliberately creates them — `exhibitor-backend-api/src/company_user/company_user.service.ts:237-248`). The fix: drop `@unique` in all five schemas, add `@@index`, flip the `Company.exhibitor` back-relation to plural, and resolve ~25 call sites one-vs-many — as its **own standalone PR**, not bundled into any phase (addendum §10; validation report D2 "fix now… so it can't bite an unrelated query first"). Approve.

**Answer options:**
- [ ] **Approve the drop as specified (five schemas, standalone PR). (recommended)** The schema is simply wrong about the data; `{all customer contacts}` (DRR FR-8) hard-requires the fix; DRR plan Step 1 carries a contingency absorption if it hasn't landed (DD-9).
- [ ] Reject (keep `@unique`). *(Then FR-8 is unbuildable as specified — `{all customer contacts}` collapses to single-contact semantics; DRR plan BLOCKED-ON D2 says: escalate, do not improvise.)*

**Blocks:** spine milestone MS1; DRR plan Steps 1/4 (BLOCKED-ON D2); spine §4 gate B last item.

---

#### DRR-17 — Recipient entries become typed structures in `channel_config`
**Owner:** 🧑‍💼 BA · **Tier:** 3 · **Status:** ☐ OPEN (default PROPOSED, built)

**Plain language:** Today a template's recipient list is a plain list of email strings — a Google-group address is indistinguishable from a typed-in external email, and a token can't be stored at all. Proposal: each entry becomes a small labeled record (`{kind: literal | token | gmail_group | list_ref, value}`); existing stored entries are converted to `literal` automatically; the API keeps accepting plain strings during the transition.

**Answer options:**
- [ ] **Typed entries + one-off normalization of existing rows. (recommended)** Group behavior (DRR-03), per-entry audit (DRR-10) and the trigger matrix (DRR-04) all key off the entry kind; flat strings would force a bigger migration later (DRR story §3.3/FR-5; DRR plan DD-4/Step 1 normalization/Step 7).
- [ ] Keep flat strings with a token grammar convention. *(Accepted debt: preview/audit/matrix degrade to convention-parsing — DRR plan BLOCKED-ON DRR-17.)*

**Blocks:** DRR plan Step 7 (BLOCKED-ON DRR-17) + the Step 1 normalization statement; DRR story AC-1.

---

## H. Process & release sign-offs (owner: PM/BA)

*Combined-release gate acceptances and the one frozen-register action.*

---

#### M1 — Fix the known-issues register wording + apply the two scheduling-register notes (user actions; both register files frozen)
**Owner:** ✅ User (Prantik) — the register files are frozen to this doc pipeline · **Tier:** 4 · **Status:** ☐ OPEN action

**Action (a) (HIGH per the external review):** `EMAIL_SMS_KNOWN_ISSUES.md` items #2/#12 say SMS storage/edit is "already built, zero schema change" — the code hard-blocks SMS create and the SMS config shape was never defined. Correct the wording to **"SMS create is gated; storage shape undefined"** before any client-facing review — otherwise the register overstates readiness and SMS could be scoped as nearly-done when it is not (validation report M1; SMS story §2 item 4/§11; spine §4 gate E).

**Actions (b)/(c) (same class — user-applied edits to a frozen register, here `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md`):** the scheduling fixes addendum specifies two register notes it cannot apply itself (that register is read-only to its track). Tracked here so they can be marked done and verified before client-facing review, exactly like (a):

- [ ] **(a)** Wording fix applied by the user to `EMAIL_SMS_KNOWN_ISSUES.md` #2/#12.
- [ ] **(b)** **SCH-3 note** applied by the user to `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md`: SCH-3's PII half is bounded by the S1 retention window once built; its staleness half is answered by the D1 per-rule resolve-timing toggle (default snapshot-at-materialize; `resolve_at_send` opt-in once DRR ships) — addendum §7(c)2; closes the S7/P9-7 residue (Appendix R).
- [ ] **(c)** **SCH-4 note** applied by the user to `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md`: the planned stop-condition resolver list shrinks after the X1 `CART_CONVERTED` drop (`CONTRACT_SIGNED` / `QUESTION_ANSWERED` remain; `QUESTION_ANSWERED` stays `[dep]` per S4) — addendum §8(c)4; closes the X1 residue (Appendix R).

**Blocks:** client-facing review of the registers (spine §4 gate E second item). No code step waits on any of the three.

---

#### SPINE-Q2 — If the SMS long pole slips, what does "ship together" mean?
**Owner:** 🧑‍💼 BA/Client (product decision) · **Tier:** 2 (decide before MS9 planning) · **Status:** ☐ OPEN (default PROPOSED)

**Plain language:** Carrier registration (10DLC) is outside our control and can take weeks. Technically the tracks are separable — the email work (scheduling + DRR) is complete without SMS, and the SMS code can sit deployed-but-dark. But "one combined release" is a product commitment, so: if registration is still pending when the email tracks are ready, do we hold everything, or ship the email value and declare the combined release when SMS actually switches on?

**Answer options:**
- [ ] **Email tracks deploy on their own readiness; SMS code deploys dark (pre-flip posture); the combined release is *declared* at the `sms_sending_enabled` launch flip. (recommended)** Keeps every shared-spine guarantee (one resolver, one migration) without holding shipped email value hostage to carrier timelines (spine §5 SPINE-Q2).
- [ ] Hold the entire release until SMS can launch. *(Email value waits on an external registration queue.)*

**Blocks:** spine milestone MS9 sequencing and release communications.

---

#### P9-2 — Accept: the deferred anchors mean some client templates aren't dispatchable at launch
**Owner:** 🧑‍💼 BA/PM (acceptance) · **Tier:** 2 · **Status:** ☐ OPEN acceptance

**Plain language:** The scheduling build defers show/workshop/employee-date anchors (`Shows.date` is date-only/nullable with a TBA flag; workshop and employee-date anchors are unmodelled — scheduling plan §9 P9-2). Consequence to accept explicitly: the majority of the client's time-based emails — **including the two client-cited scheduled SMS (Workshop Confirmation −24h and the product-question SMS)** — are **not dispatchable at launch even with the SMS provider live**; they wait on anchor modelling in a later story (SMS story §9 note; SMS plan Deferred). Recording, not owning: anchor modelling is the scheduling track's deferred scope.

- [ ] **Acknowledged — the deferred-anchor consequence is accepted for this release and communicated to the client. (recommended)** The alternative (modelling the anchors now) is new scope outside every current plan.
- [ ] Not acceptable — pull anchor modelling into scope *(new story + re-plan; name which anchors)*: ______________

**Blocks:** release-notes/client-expectation setting for MS9; no code step.

---

## Appendix R — Resolved / closed IDs (nothing vanishes)

Every original gap-doc, review, or plan-§9 ID that is **not** open above, with the citation that resolves it. If any row's premise turns out wrong, the ID reverts to the open sections under its original number.

| ID | Was | Resolution | Citation |
|---|---|---|---|
| **S1** (HIGH) | No retention/purge for `notification_schedule_occurrences` | **Specified, no open decision:** retention cron + `schedule_occurrence_retention_days` (90, clamp [7,365]) + batched deletes + FOLLOW_UP latest-row guard; lands before Phase 3 ships | Addendum §1 ("(e) Open decision: none"); spine §4 gate B |
| **S2** | Reaper race can double-send; exactly-once leaned on topology | **Fixed by spec:** `FOR UPDATE SKIP LOCKED` claim; at-least-once stated explicitly. *Residual open decision = ADD-Q1 (section E)* | Addendum §2; validation report S2/§6 |
| **S3** | One-size 24h catch-up can drop a valid send | **Fixed by spec:** per-rule `catchup_policy` + per-skip and aggregate alert lines. *Residual open decision = ADD-Q2 (section E)* | Addendum §3 |
| **S4** | RECURRING "until answered" lacks instance-discovery + live resolver | **Fixed by spec:** review option (a) adopted — template deferred; mechanics ship exercised by tests. *Residual open decision = ADD-Q3 (section E)* | Addendum §4; validation report S4/§6 |
| **S5** | DST fall-back (ambiguous hour) untested | **Closed:** one unit test specified (2026-11-01 America/New_York, earlier instant), lands with Phase 3 tests; no open decision | Addendum §5 |
| **S6** | Invalid EVENT timezone silently defaults → wrong-hour send | **Closed:** ingest-side IANA validation + send-side fail-closed SKIP `"unresolvable event timezone"` + alert; `schedule_default_timezone` removed from the EVENT chain; before Phase 3 ships; no open decision | Addendum §6 |
| **S7** | PII in `recipients_snapshot`, no retention tie-in | **Closed by S1:** snapshot lifetime = occurrence retention window; documentation bindings only (SCH-3 register note = user action, **tracked as M1 sub-item (b)**) | Addendum §7; validation report S7 |
| **X1** | `CART_CONVERTED` aliases `CONTRACT_SIGNED` | **Closed:** enum ships without `CART_CONVERTED` (Phase 1 migration); re-adding later is additive; no open decision (SCH-4 register note = user action, **tracked as M1 sub-item (c)**) | Addendum §8 |
| **X2** | Verification list pre-dates the fixes | **Closed:** exactly three cases appended (retention / reaper double-send / bad timezone); case 2 has a conditional extension hanging off ADD-Q1 | Addendum §9; spine §4 gate B |
| **M2** | 2026 SMS compliance under-specified | **Adopted as built defaults:** state-aware quiet hours, platform suppression store ("any reasonable method"), ≥5-yr consent retention, 10DLC hard gate — all in SMS plan DD-8/DD-9/Step D1-D2. *Signs off with SMS-03/SMS-08 (open above)* | SMS story FR-9/§4.2; SMS plan DD-8/DD-9; SMS story §12 row M2 |
| **M3** | `NotificationLog` can't record SMS channel/destination | **Adopted:** the ONE unified migration (spine §1.2 = spec of record; DRR Step 1 = execution home; SMS B1 = consumer). *Signs off with SMS-05 (open above); timing question = SPINE-Q1* | Validation report M3; spine §1.2/C1; SMS story §12 row M3 |
| **M4** | DRR↔SMS circular dependency | **Settled, binding:** email DRR first → scheduler consumes → SMS extends the same resolver to phone; encoded in the build order. *Signs off with SMS-07 (open above)* | Validation report M4; spine §1.1.2; SMS plan DD-3; DRR plan DD-11 |
| **DRR-13** | Snapshot vs re-resolve for scheduled sends (the timing conflict) | **Adjudicated by D1** — carried as *adjudicated-pending-BA-sign-off* under the D1 entry (section F); not silently closed | Validation report D1; DRR story §3.6/§10; spine §1.1.3 |
| **DRR-14** | Predefined-DRR V2 variant scope | **Settled before this release:** out of scope per existing decision (KNOWN_ISSUES #3); residual scope thread folded into DRR-05 (open above) | DRR gap analysis "Already settled"; DRR story §10 |
| **SMS-13** | Send-path repo ownership & schema sync | **Retired — answered by architecture:** worker hosts the send, admin owns migrations, others `db push`; its one fragment (log-schema propagation) folded into SMS-05 (open above) | SMS gap analysis "Already settled"; SMS story §12 row SMS-13 |
| **P9-3** (sms-provider) | SMS provider gates scheduled-SMS dispatch (deferred) | **Superseded by this release:** the deferral is being reversed via SMS-02, mechanism via SMS-01 (both open above); the gate flip is SMS plan Step H1 | Scheduling plan §9; spine §1.3 row 2 |
| **P9-4** (drr) | DRR deferred; token recipients SKIP | **Superseded by this release:** DRR is now the specified 77.9 build (EMS-779-DRR); the un-gate is DRR plan Steps 4–6 / AC-15 | Scheduling plan §9; DRR story §11 (#3 moves deferred → specified) |
| **P9-5** (other-system-emails-source) | "Other relevant system emails" has no source | **Carried, not closed — lives on as DRR-07 (open above, same question, original base-register #4)** | DRR story FR-10/§11; spine §6 row DRR-07 |
| **P9-6** (stop-condition-resolver-set) | `CART_CONVERTED` alias + `QUESTION_ANSWERED` [dep] | **Resolved by X1** (alias dropped) **+ the HARD RULE** (unimplemented resolvers force `end_window_at`/`repeatCount`); the [dep] residual rides ADD-Q3 (open above) | Addendum §8; scheduling contract §(g); addendum §4 |
| **P9-7** (snapshot-pii-retention) | Snapshot PII on occurrence rows — acceptable? | **Answered by S1+S7:** retention window (default 90d) bounds snapshot PII; D1's reference mode further reduces it; SCH-3 register note = user action, **tracked as M1 sub-item (b)** | Addendum §7; spine §1.1.3 (SMS variance: none) |
| **P9-8** (no-commits-convention) | Process convention | **Standing convention, not a decision:** the user reviews and commits every repo; no doc/track commits anything; carried in every plan's checklist and spine §4 gate F | Scheduling plan §9; all plans' Post-Atom checklists |

---

*Per project convention: no commits are made by this document or its pipeline; the user reviews and commits everything. The approved scheduling plan, both stories' source gap analyses, and both known-issues registers remain unedited — every register-affecting item above (M1 sub-items (a)–(c), covering the S7/SCH-3 and X1/SCH-4 register notes) is a proposal for the user to apply.*

# Email & SMS Scheduling — Known Issues Register

> **Purpose:** a running list of open items, deferrals, dependencies, and findings specific to the **Email & SMS Scheduling** work for the Email & SMS Management module. This register records *what is known* for the team picking up scheduling (engineering, BA, documentation, and teams owning adjacent services). It does **not** decide ownership or applicability of resources we do not own.
>
> **Scope:** dynamic, per-template scheduling — `ANCHOR_RELATIVE`, `RECURRING`, and `FOLLOW_UP` rules — as designed in:
> - `EMAIL_SMS_SCHEDULING_STORY.md` (user story + acceptance criteria, incl. the schedulability-gate AC-20/AC-21)
> - `EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` (tables, the `is_schedulable` / `supports_scheduling` marking + backfill, worker heartbeat poller, timezone `EVENT`|IANA, stop-conditions)
> - `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md` (per-field value reference for registering a non-seeded template + its schedule)
>
> This is a **sibling** register to `EMAIL_SMS_KNOWN_ISSUES.md` (the base-module register). Scheduling was deferred from the base sprint per a verbal BA agreement (2026-06-03) and is tracked here as its own effort. Items that originate in the base module but block or shape scheduling are cross-referenced by their base `#` number.
>
> **Implementation status:** design complete (now incl. the schedulability marking + dev integration guide); **build not started.**
>
> **Last updated:** 2026-06-18 — register extended alongside the updated implementation plan (the `is_schedulable` / `supports_scheduling` marking + the dev integration guide). Added **SCH-2** (open product decision — which triggers get `supports_scheduling = true`), **SCH-3** (FOLLOW_UP `recipients_snapshot` PII / staleness), **SCH-4** (`stop_condition` resolver set not finalized), **SCH-5** (`TEMPLATE_META` widening build-prerequisite), and **SCH-6** (recipient-feasibility — column-recipient sends in scope, token-recipient deferred to base #3 / DRR). Original entry **SCH-1** = three lead-distribution lifecycle slugs demoted to trigger-only stubs (recoverable from git).

---

## Main issues

| # | Issue | Status | Owner | Schema impact |
|---|-------|--------|-------|---------------|
| SCH-1 | Three lead-distribution lifecycle slugs (`lead_claimed_full_details`, `lead_claimed_by_other`, `lead_distribution_expired`) exist as **trigger-event + display-meta stubs with no template body and no sender** — they were once full templates, then stripped | Recorded (provenance traced) — recoverable from git; revisit when the lead-claim flow is built | Us (whoever finishes the lead-claim flow) | None |
| SCH-2 | Which trigger events get `supports_scheduling = true` is a **product decision**; the plan recommends opening it on six slugs (for future *same-trigger custom* templates, not the seeded receipts) — needs sign-off before the trigger seeder is changed | **Open — needs user confirmation** | Product + us | `trigger_events` seed values (no DDL beyond the new column) |
| SCH-3 | FOLLOW_UP `recipients_snapshot` (and column-recipient resolution) persists resolved recipient **emails on each occurrence row** — PII retention + **staleness** if the contact changes between capture and send | Open — define capture-time + retention/refresh policy | Us | new `recipients_snapshot` column on occurrences |
| SCH-4 | `stop_condition` resolver set **not finalized** — only `NONE` is guaranteed live; the planned resolvers (`CONTRACT_SIGNED` / `QUESTION_ANSWERED` / `CART_CONVERTED`) each need a worker resolver; **a series set to an unbuilt resolver never auto-stops** | Open — bound with `repeatCount` / `end_window_at` until resolvers land | Us | enum `NotificationStopCondition` |
| SCH-5 | `TEMPLATE_META` value type has no `is_schedulable` key — must **widen the type + update the seeder merge** before any schedulable seed compiles / its flag persists | Build prerequisite (tracked, sequencing) | Us | none (seeder code only) |
| SCH-6 | Recipient feasibility: scheduled sends **dispatch now only** when recipients are fixed or an **anchor-row column**; token recipients (`{salesperson}`, speaker lists) stay deferred to DRR | Scoped — column/fixed in scope; token deferred (base #3) | Us | new `recipient_source` / `replacements_map` columns on schedules |

---

## SCH-1. Lead-claim / expiry templates demoted to trigger-only stubs

**What is true today (`feature/SBE-671`, all 5 repos):** three notification slugs exist at the trigger and display-metadata layers but **not** as sendable templates:

| Slug | `trigger_events` row | `TEMPLATE_META` display name | Template body (`notification_templates` row) | Any sender in code |
|---|---|---|---|---|
| `lead_claimed_full_details` | ✅ (label + `available_placeholders`) | ✅ "Lead Claimed (Full Details)" | ❌ none | ❌ none |
| `lead_claimed_by_other` | ✅ | ✅ "Lead Claimed by Another Provider" | ❌ none | ❌ none |
| `lead_distribution_expired` | ✅ | ✅ "Lead Expired Unclaimed" | ❌ none | ❌ none |

Result: the seeder produces **18 template rows for 21 trigger events**; these three are the gap. They are part of the **PPL lead-distribution lifecycle** (the claim-outcome / expiry half: a provider claims a shared lead → contact details unlock; another provider claims it first; nobody claims it before expiry).

**This is not an accidental orphan — it is a deliberate scope-trim.** Git provenance:

1. **`bf9e72f` — "feat: lead distribution work"** (pre-SBE-671 PPL work): all three were introduced as **complete, sendable templates** with full `notification_type` + `subject` + `body`. Original subjects:
   - `lead_claimed_full_details` → `Lead unlocked — {{attendeeFullName}}`
   - `lead_claimed_by_other` → `A shared lead has been claimed by another provider`
   - `lead_distribution_expired` → `Unclaimed lead expired`
2. **`7476f90` — "feat: ppl work"** (Sushobhan Manna, 2026-06-11): the **bodies were removed** — the `notification_type`/`subject`/`body` blocks for all three were deleted from the `TEMPLATES` array. The trigger-event rows and placeholder sets were kept.
3. **`44325a4` — "feat(SBE-671): add Email & SMS Management schema foundation"**: the SBE-671 restructure re-added the three slugs to **`TEMPLATE_META` only** (display name + tag), but did **not** restore their bodies. `git log -S` confirms they were never re-added after step 2.

**Why the schema permits this:** the foreign key is one-directional — `notification_templates.notification_type → trigger_events.slug`. A *template* requires a *trigger*, but a *trigger* does not require a *template*. So these three can sit in the catalog with zero template rows and nothing breaks (the admin trigger/placeholder picker stays complete; see base register #13 on the global-unique `slug` FK design).

**Relevance to scheduling:** the lead-claim/expiry notifications are part of the same PPL lifecycle the scheduling effort touches, and `lead_distribution_expired` in particular is **time/anchor-driven by nature** (it fires when an assigned lead passes its claim deadline) — a natural `ANCHOR_RELATIVE` or worker-evaluated candidate once the lead-claim flow is wired. Whoever builds that flow should be aware the email **copy already exists in git** and can be **recovered from `bf9e72f` rather than rewritten**.

**Action / recommendation:**
- **No action required for the current scheduling build** — these slugs are out of the scheduling design's stated scope (which targets built triggers + existing anchors).
- **When the lead-claim flow is finished:** restore the three bodies from `bf9e72f` (or rewrite to current copy standards), re-add them to the `TEMPLATES` array (the seeder is create-only per base register #15, so seeded environments take the new rows via a one-off migration or admin create, not a seeder re-run), and wire their senders in `background-worker-service` alongside the existing `lead_assigned_preview` / `lead_daily_summary` / `low_balance_warning` paths.
- **Minor cleanup (optional):** `TEMPLATE_META` carries display names for these three even though no template row uses them — harmless dead config that becomes live when the bodies return.

**Cross-references:** base register #15 (create-only seeder), #16 (predefined-uniqueness invariant), #21 (live send path does not filter `is_predefined`). Also note base register entry on `lead_credits_renewed` — a fourth lead-suite slug that **is** seeded with a body but has **no sender** (dormant); distinct from these three (which have no body at all).

---

## SCH-2. Open product decision — which triggers get `supports_scheduling = true`

The updated plan adds two schedulability markers (plan §2.0): `NotificationTemplate.is_schedulable` (the per-template *switch*) and `TriggerEvent.supports_scheduling` (a **code-controlled catalog *ceiling***). A template may be `is_schedulable = true` only when its trigger's `supports_scheduling = true`. Opening the gate on a trigger is therefore a **product statement** about which events may *ever* carry a schedule.

The plan (§2.0.4) **recommends** opening the gate on six slugs, and that recommendation is **pending the user's confirmation** before the trigger seeder is changed:

| Slug | Why the gate is proposed |
|---|---|
| `cart_updated_notification` | `Cart.expiration_date` → ANCHOR_RELATIVE expiry reminders |
| `ppl_product_order_payment` | `PaymentTransaction.due_date` → ANCHOR_RELATIVE dunning |
| `lead_daily_summary` | RECURRING daily-digest cadence |
| `lead_credits_renewed` | RECURRING per-billing-cycle (dormant until a sender is wired) |
| `company_user_invitation` | FOLLOW_UP invite-reminder series |
| `ppl_subscription_canceled` | FOLLOW_UP win-back series |

**Important — what these gates do NOT do:** opening the gate does **not** make the seeded receipt/notice on those slugs schedulable. The 18 seeded predefined templates stay `is_schedulable = false` permanently (SCH backfill promotes **zero** of them). The gate exists for **future *same-trigger custom* templates** — a dev could author a new custom template on, say, the existing `cart_updated_notification` trigger and mark *it* schedulable. The reminder examples in the integration guide deliberately use **new** triggers (e.g. `cart_expiration_reminder`), because a "cart expiring soon" reminder is a semantically distinct event from a "cart was updated" notice.

**Status / recommendation:** **Open — needs user sign-off.** Default-safe path if undecided: ship every trigger gated `false` and open them one at a time as Product confirms; no schema change is needed to flip a gate later (it is a seed value). Cross-ref: plan §2.0.4, §9 (open product decision).

---

## SCH-3. FOLLOW_UP recipient snapshot — PII retention + staleness

To dispatch FOLLOW_UP (and column-recipient ANCHOR_RELATIVE) sends **without** DRR, the design captures the resolved recipients onto the occurrence row (`recipients_snapshot`, plan §2.2) / resolves them from the anchor at materialize time. Two open questions follow:

1. **PII on a high-volume table.** `recipients_snapshot` stores recipient email addresses on every occurrence. That is PII landing in the scheduling tables (not just `notification_logs`). A retention / redaction policy should be decided (e.g. null the snapshot after SENT, or rely on the existing log retention).
2. **Staleness.** If the contact's email changes between capture and the actual send, a snapshot taken early is stale. Decide **capture-at-fire vs capture-at-trigger**, and whether to **re-resolve at dispatch** when the recipient source is a live column (which would prefer freshness over the snapshot).

**Status:** Open — define capture timing + retention. Not a blocker for the email build, but should be settled before FOLLOW_UP ships. Cross-ref: plan §2.2, §4 (materialize), §9.

---

## SCH-4. `stop_condition` resolver set not finalized

`stop_condition` is an **enumerated, code-controlled** field (admins *select*, never author logic). The integration guide (§2.3) and plan (§4 stop-conditions, §9) flag that the resolver set is **not finalized**:

- Only **`NONE`** is guaranteed live at first.
- `CONTRACT_SIGNED` / `QUESTION_ANSWERED` / `CART_CONVERTED` are the **planned** resolvers — each needs a worker resolver that inspects the bound domain state every tick and cancels remaining occurrences when it resolves.
- **Risk:** if a rule is set to a `stop_condition` whose resolver does not exist yet, the series **never auto-stops**. Until the resolvers land, every bounded series **must** also carry a `repeatCount` and/or `end_window_at` as a backstop.

**Status:** Open — finalize the resolver enum + build order; the worked examples in the guide (`CONTRACT_SIGNED`, `CART_CONVERTED`) are illustrative and **resolver-pending**. Cross-ref: guide §2.3, plan §4 / §9.

---

## SCH-5. `TEMPLATE_META` widening — build prerequisite for any schedulable seed

Per plan §2.0.5 and guide §2.2, the seeder's `TEMPLATE_META` map currently types its value as `{ template_name, tag }` — there is **no `is_schedulable` key**. Two changes are a **prerequisite** before any schedulable template can be seeded:

1. Widen the `TEMPLATE_META` value type to `{ template_name; tag; is_schedulable: boolean }`.
2. Change the merge in `notification-template.seeder.ts` from `{ ...template, ...meta, is_predefined: true }` to also set `is_schedulable: meta.is_schedulable`.

Without (1) a `is_schedulable` literal is a TypeScript error; without (2) the seeded value is silently never written (DB default `false` wins). The 18 existing `TEMPLATE_META` entries must each gain `is_schedulable: false` at the same time.

**Status:** Build prerequisite (sequencing gotcha, not a defect). Do it once before authoring any schedulable seed. Cross-ref: plan §2.0.5, guide §2.2 prerequisite block.

---

## SCH-6. Recipient feasibility — column-recipient in scope, token-recipient deferred (base #3 / DRR)

The plan resolves *how* scheduled sends reach recipients without building DRR, for the in-scope cases:

- **ANCHOR_RELATIVE** reads the recipient from a **column on the anchor row** (`recipient_source`, e.g. the cart/order owner's email) and resolves body/subject tokens from the same row (`replacements_map`) — both new columns on `notification_schedules` (plan §2.1).
- **FOLLOW_UP** captures recipients at trigger time (`recipients_snapshot`, see SCH-3).

So scheduled sends whose recipients are **fixed or an anchor-row column dispatch now**. Sends whose recipients are **tokens needing resolution** (`{salesperson}`, `{all speaker email addresses}`) still require **DRR (base #3)** and stay **configured-and-stored but not dispatched** — the same send-time-gate pattern as SMS. A null recipient column → the occurrence is `SKIPPED`.

**Status:** Scoped (not open) — recorded so the DRR boundary is explicit: column/fixed = in scope; token = deferred. Cross-ref: story AC-21, base register #3, plan §2.1 / §4.

---

## Deferred scheduling scope (carried from the base module, for context)

These were specified in V2 and deferred from the base sprint; they are the substance of this effort. Tracked in full in `EMAIL_SMS_SCHEDULING_STORY.md` / `..._IMPLEMENTATION_PLAN.md` and summarized here so this register is self-contained.

- **Scheduling engine** (base #1) — `ANCHOR_RELATIVE` (multi-offset, time-of-day, `EVENT`|IANA timezone), `RECURRING` (cadence + stop-condition + end-window), `FOLLOW_UP` (post-trigger offsets + stop-condition). The design now also includes the **schedulability marking** (`is_schedulable` + `supports_scheduling`, with a zero-row backfill) and a dev integration guide. Build not started.
- **SMS provider** (base #2) — several scheduling targets are SMS (workshop confirmation −24h, unanswered-questions reminders). SMS sending is gated until a provider is integrated; SMS occurrences materialize but dispatch is `SKIPPED`.
- **Dynamic recipient resolution** (base #3) — token recipients (`{salesperson}`, speaker lists) are deferred; column/fixed recipients dispatch now (see **SCH-6** for the in-scope boundary).
- **Live send-path predefined scoping** (base #21) — the `is_predefined` + `orderBy` fix to `sendFromTemplate` is **planned to ship together with the scheduling logic**; carry it into this effort.
- **Unbuilt client anchors** — vendor/venue/GSC/electric logistics, event-alert / event-photos, workshop confirm/reminder emails and their primary anchors (event/show date + timezone, workshop scheduled time) are **not** among the currently-built predefined triggers; flagged as dependencies. The build targets anchors that exist today (`Cart.expiration_date`, `PaymentTransaction.due_date`, and the show date/timezone where already modelled).

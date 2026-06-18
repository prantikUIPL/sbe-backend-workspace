# Email & SMS Management — Outstanding Items

**Date:** 2026-06-17
**Module:** SBE-671 — Email & SMS Management

**Purpose:** A single "what's left to do" view for the Email & SMS Management stories. Lists only **open** and **planned** items, grouped **by owner / action type** so each can be picked up by the right party.

**Snapshot — collated from (see these for full detail):**
- `EMAIL_SMS_KNOWN_ISSUES.md` — numbered Known Issues register (#1–#23)
- `FINAL_EMAIL_SMS_RELEASE_NOTES_KNOWN_ISSUES.md` / `EMAIL_SMS_RELEASE_NOTES_KNOWN_ISSUES.md` — release-notes gap list
- `EMAIL_SMS_API_CHANGELOG.md` — API changelog
- `EMAIL_SMS_SCHEDULING_STORY.md` + `EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` — dynamic scheduling design (not started)

> Excluded by design: items already RESOLVED/CLOSED (#11, #13, #14, #15, #16, #20) and purely-RECORDED intentional behaviours. Source IDs are kept in brackets for traceability. No ticket IDs invented — factual recording only.

**Owner legend:** 🛠 Code (us) · 🗄 Data/seed (us) · 📝 BA / documentation · 🤔 Product decision · ⏳ Deferred (client / other-team dependency) · 🗓 Scheduling build

---

## 1. 🛠 Code fixes — our backend work

- **[#21] Live send path doesn't filter `is_predefined` / lacks deterministic `orderBy`.** An active *custom* template can nondeterministically shadow a predefined one on a live trigger. Fix: add `is_predefined: true` + a deterministic `orderBy` to the template lookup in all four `mailer.service.ts` (`background-worker-service`, `admin-backend-api`, `external-api-service`, `exhibitor-backend-api`). **Planned to ship WITH the scheduling logic** (send-side only; no admin API contract change). Until it ships, avoid active custom templates on live triggers in shared environments.
  Affected live trigger slugs: `welcome_email`, `forgot_password`, `exhibitor_welcome_admin_created`, `cart_updated_notification` (admin); `welcome_email_exhibitor`, `exhibitor_forgot_password`, `company_user_invitation`, `invitation_accepted_to_exhibitor`, `contact_us_acknowledgment`, `contact_us_admin_notification`, `ppl_subscription_canceled` (exhibitor); `ppl_order_confirmation`, `ppl_subscription_renewal`, `ppl_product_order_payment` (external API); `lead_assigned_preview`, `lead_daily_summary`, `low_balance_warning` (worker).

- **[#19 / Release #20] `channel_config` has no path back to system-default `null`.** Once `from_name`/`reply_to` are written via `PUT`, they can never be unset (null → 400, empty string → 400, merge never removes keys). Agreed direction: a clear-to-default sentinel on `PUT` (candidate: `""` stores the key as `null`). **Implementation explicitly deferred — do not code until directed.**

> Note: the **[#21]** fix is bundled into the Scheduling build (§6) — listed here for owner visibility; it ships there.

## 2. 🗄 Data / seed corrections

- **[#22 / Release #13] `lead_assigned_preview` seeded copy conflicts with its own trigger's placeholders.** Seeded subject/body use `{{attendeeName}}`, `{{attendeeEmail}}`, `{{attendeeMobile}}`, `{{attendeeZip}}`, `{{myLeadsUrl}}`; the trigger's `available_placeholders` are `expiryHours`, `attendeeFirstName`, `attendeeZipPrefix`, `categoryList`, `claimUrl` — zero overlap. Any `PUT` touching subject/body returns 400. Fix: align the trigger's placeholder list with the worker call site **or** rewrite the copy to the trigger's list. Ships as a one-off migration or manual edit (seeder is create-only).

- **[#23 / Release #14] `ppl_product_order_payment` ("Order Payment Receipt") body uses Handlebars block helpers.** Body contains `{{#if is_fully_paid}}` / `{{else}}` / `{{#if next_installment_amount}}`; the mailer renders via literal token splice (`split(token).join(value)`), so blocks render literally in delivered mail. Placeholder validation skips block tokens, so the problem doesn't surface on edit. Fix options: flatten to simple tokens (pre-compute e.g. `installment_note` at the call site), or upgrade body rendering to real Handlebars (larger change).

## 3. 📝 BA / documentation actions — story reconciliation

- **[#3 — predefined]** Predefined Dynamic Recipient Resolution row contradicts the agreed read-only design (predefined recipients are system-defined). BA to **remove it from the predefined epic**.
- **[#4 / Release #4]** Recipient-picker source lists — TO/CC/BCC select from predefined lists owned by other modules; "other relevant system emails" has **no observed source endpoint**. Owning team to define the source.
- **[#5 / Release #24]** Template Type enum: Filter stories say `Event`, Create/Edit stories say `System`; implementation uses `System`. Reconcile story wording to `System`.
- **[#6 / Release #25]** Predefined Listing/Detail says channel may indicate "Email, SMS, or both", but the model is single-channel. Drop "or both" from the description.
- **[#7]** From-Email domain strings were replaced by brand titles (auto-link/crawler artifact); implementation is correct. Restore the domain strings (`theshowproducers.com` / `thesmallbusinessexpo.com`) in story text.
- **[#8 / Release #22]** "Last modified by/date" is derived from `admin_audit_logs`, not stored on the template record, and is not in the listing. Update story 76.1 — remove/repoint the "last modified by/date" listing column.
- **[#9]** WYSIWYG "images": implementation stores provided HTML only (no upload; asset hosting is a separate module). Confirm "images" = hosted URL references only this sprint.
- **[#10 / Release #27]** Custom listing "event selector" wording is ambiguous — it means a placeholder dropdown (select trigger → show its placeholders), not a listing filter. Backend already returns `available_placeholders` per event; no code gap. Update the story wording.
- **[#17 / Release #28]** Validation rules enforced in code but specified in no story: channel-restriction message, length caps, recipient-array caps, email-format validation, placeholder whitelist, search matching `subject` (stories name only name + trigger), and TO recipients **not** deduped (stories mandate dedup for CC/BCC only). BA / documentation to define/confirm each.
- **[#18 / Release #26]** `DELETE /notification-templates/:id` (custom-only, audited, FK cascade) has **no backing user story**. BA to add a Custom Email "Delete Template" story or formally confirm the design-doc justification.

## 4. 🤔 Design limitations — pending product decision

- **[Release #17]** Active/Inactive status flag is largely unenforced.
- **[Release #18]** Template names are not unique (pending product decision).
- **[Release #23]** Audit snapshots are summaries; three-month retention exists but is un-wired (audit permanence currently conditional).
- **[Release #29]** Concurrent edits are last-write-wins — no version/precondition mechanism (audit records both edits but no API conflict warning).
- **[Release #30]** Behaviour for missing placeholder values at send time is undecided — raw tokens are left in the email; no fallback rule.
- **[Release #31]** Hardened id validation covers only the templates + booth-agreement routes; ~60 other admin routes still silently coerce ids. Repo-wide gap, undecided.

## 5. ⏳ Deferred — client / other-team dependency (blocks future scope)

- **[#1 / Release #1]** Scheduling & follow-up sends — **now being built** (see §6).
- **[#2 / Release #2]** SMS provider integration (client dependency). SMS templates are storable/editable, but the send path is gated until a provider is integrated. Zero schema change to enable later.
- **[#3 — custom / Release #3]** Dynamic Recipient Resolution Engine (custom) — send-time resolution of `{salesperson}`, `{main customer contact}`, `{all customer contacts}`, internal Gmail groups deferred to a follow-on mailer plan; `to_recipients` stores literal strings/tokens for now.
- **[Release #6 / #7 / #8 / #9]** Only ~4 of ~41 client-requested templates delivered. The remainder are gated on owning-module integration and the deferred capabilities above (Scheduling / SMS / DRR), including the client's "PPL Emails" row.

## 6. 🗓 Dynamic scheduling build — designed, NOT started

Full detail in `EMAIL_SMS_SCHEDULING_STORY.md` and `EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md`. Not yet implemented:

- **Schema:** `notification_schedules` + `notification_schedule_occurrences` tables + 3 enums (`NotificationScheduleKind`, `NotificationStopCondition`, occurrence `status`). Migration in `admin-backend-api`, mirrored into the other four schemas + `db push`.
- **Admin config (`admin-backend-api`):** schedule DTOs (`ScheduleRuleDto` + nested offset/recurrence/follow-up), service merge + two-tier enforcement (predefined recipients stay read-only), audit-snapshot extension, SQS live-refresh (the "dynamic, no redeploy" mechanism), and schedule exposure in detail/listing.
- **Worker executor (`background-worker-service`):** new `src/scheduler/schedule-dispatch/` module — heartbeat poller (interval from `ppl_settings`, default 5 min), `runTick()` = materialize (DST-correct `fire_at` via `date-fns-tz`, upsert PENDING) + dispatch (due PENDING → `MailerService.sendFromTemplate`, link `NotificationLog`, mark SENT/FAILED) + dedupe (unique `dedupe_key`).
- **Three schedule kinds:** ANCHOR_RELATIVE (against existing anchors — `Cart.expiration_date`, `PaymentTransaction.due_date`, `Order.paid_in_full_at`, show date where modelled), RECURRING, FOLLOW_UP. Timezone selectable EVENT | explicit IANA; multi-offset support; code-controlled stop-condition set.
- **Bundled [#21] fix** across the four mailers ships here.
- **Explicitly later:** SMS execution (when [#2] lands — occurrences SKIPPED with provider-not-integrated reason until then); and the unbuilt client templates + their anchors (vendor/venue/GSC/electric logistics, event-alert/event-photos, workshop confirm/reminder) which need new templates and a schedulable event/show + workshop anchor.
- **End-to-end verification not yet performed** (per implementation plan §8).

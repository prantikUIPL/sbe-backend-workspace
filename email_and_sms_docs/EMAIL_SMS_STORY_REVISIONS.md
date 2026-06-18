# Email & SMS Management — Suggested User-Story Revisions

**Module:** Email & SMS Management
**Audience:** Product / BA / Sprint planning
**Date:** 2026-06-01
**Source stories:** `Email & SMS Management.xlsx` (6 user stories)
**Reference design:** `EMAIL_SMS_DB_DESIGN_REVIEW.md` (schema, enums, JSONB shapes, predefined/custom rules, out-of-scope list)

---

## Purpose of this document

The 6 user stories were authored as the **full target spec** — they assume a working mailer, scheduler, SMS provider, dynamic recipient resolution, image upload, and freely-editable fields. The implementation we designed and agreed for **this phase is deliberately narrower**: a CRUD / configuration layer that *stores* everything on the shared database, while send-time behaviour is deferred to later phases.

This document realigns the stories with what the current implementation actually delivers. For each story it states: **what it says now → suggested change → why it's needed → should it be split**. Changes are kept minimal — the goal is accurate sprint planning, not a redesign.

Each suggested change has been cross-checked against the verbatim story text and against the confirmed schema in `EMAIL_SMS_DB_DESIGN_REVIEW.md`. None of them contradicts an already-agreed design decision.

---

## Two cross-cutting recommendations

These two themes drive most of the per-story changes below. They are stated once here and referenced by the individual stories.

### A. Make the **predefined vs custom** distinction explicit in the stories

The client agreed to a two-tier model on a single table (`is_predefined` flag):

- **Predefined templates** (the 18 system-seeded ones): `trigger_event`, `channel`, `FROM` (email) / `sender_id` (SMS), and `TO` are **read-only**. Only `subject` (email), `body`, `status`, `type`, and the email niceties (`from_name`, `reply_to`, `cc`, `bcc`) are editable.
- **Custom templates** (admin-created): full create/edit/delete, within validation rules (FROM domain whitelist, E.164 for SMS, etc.).

Stories 4, 5 and 6 currently describe **every field as uniformly editable for every template**. They need to state which rules apply to which tier, otherwise the build will look like it "doesn't match the story" when it correctly blocks editing a predefined trigger.

### B. Separate **"configure & store"** (this phase) from **"execute / resolve / send"** (later)

This phase builds the admin panel that *stores* configuration. It does **not** yet:

- fire scheduled / time-delayed sends,
- dispatch follow-up sequences,
- resolve dynamic recipient placeholders at send time,
- integrate an SMS provider,
- host uploaded images.

Several stories describe these execution-time behaviours as if they were live in this phase. The fix is to split each such behaviour into a clearly-labelled later-phase story, and have the current story cover only the *configuration/storage* half.

---

## Per-story revisions

### Story 1 — Email & SMS Template Listing → **Amend (minor)**

**What it says now:** the list shows `Template Name, Type, Trigger Event, Channel, Status, Last Modified Date, Last Modified By`; "Last Modified Date/By must be auto-captured each time the template is updated."

**Suggested change:** clarify the **source** of *Last Modified By / Last Modified Date*. The schema intentionally **dropped the `updated_by` column** from the template row — "who changed what, when" is captured in the existing `admin_audit_logs` table. So these two list columns are derived from the **latest audit-log entry** for the template, not from a column on the template itself. Add a line covering the **never-edited (freshly seeded)** state: there is no admin edit yet, so the column should show *System / Seed* (or blank), not a person.

**Why:** the story implies a dedicated column that the design deliberately removed to avoid duplicating the audit trail. Without this clarification, "Last Modified By" looks like a missing field rather than a derived one.

**Split?** No.

---

### Story 2 — Email & SMS Template Search → **No change (one confirmation)**

**What it says now:** search by **Template Name** or **Trigger Event**; partial, case-insensitive; combinable with filters.

**Suggested change:** none required — the implementation matches the story. One optional confirmation: the implementation can also match on **Subject** (it's cheap and useful). Decide whether to (a) expose Subject in the search scope and update the placeholder text accordingly, or (b) keep search strictly to Template Name + Trigger Event as written.

**Why:** the story is already aligned; this is a scope confirmation, not a correction.

**Split?** No.

---

### Story 3 — Email & SMS Template Filter → **Amend**

**What it says now:** filter by **Type** = `Store, Internal, Vendor, Product, PPL, Event`; **Channel** = `Email, SMS, Both`; **Status** = `Active, Inactive`; **Trigger Event** = predefined dropdown.

**Suggested change 3a — Type options:** the story's Type list ends in **"Event"**, but the schema enum is `Store, Internal, Vendor, Product, PPL, **System**`. Reconcile the taxonomy. Recommended: **replace "Event" with "System."** The 40-template client Excel never used a "Event" type; meanwhile genuine system templates (e.g. contact-us acknowledgements) exist outside that Excel and need a home. If "Event" is genuinely wanted as a distinct business type, it must be added to the enum deliberately — but today nothing maps to it.

**Suggested change 3b — Channel "Both":** **remove "Both"** from the Channel filter. Each template row is single-channel (`EMAIL` *xor* `SMS`) by design, so "Both" has no meaning for a single row. Selecting *no channel* already returns email and SMS templates together, which is what "Both" was trying to express. Keep the Channel filter as `Email | SMS`.

**Why:** filter values must map to actual column domains. "Event" and "Both" don't exist in the schema, so as written they would either error or silently return nothing.

**Split?** No.

---

### Story 4 — Template Detail View → **Amend**

**What it says now:** read-only view of all fields including `FROM (with Reply-To), TO, CC, BCC`, Subject, Body, plus a **Scheduling Configuration** section with examples like *"Send 7 days **before event date**"* and *"Send 1 hour after trigger event"*, and follow-up *delay + number of attempts*.

**Suggested change 4a — scheduling display:** the current `schedule_config` shape models **delay *after the trigger fires*** only (`delay_value` + `delay_unit` + `timezone`). It has **no event-date anchor**, so *"Send 7 days **before** event date"* cannot be represented or displayed in this phase. Either (i) narrow the example copy to *relative-to-trigger* only, or (ii) keep event-date-anchored scheduling in the story but label it a **later-phase capability** (this ties to Story 5's scheduling split). The detail view should display whatever `schedule_config` / `follow_up_config` hold, shown read-only.

**Suggested change 4b — predefined recipients:** for **predefined templates** (especially SMS), `FROM` / `TO` / `sender_id` are **system-controlled**. The detail view should present these as *system-managed / read-only* rather than implying they are admin-configured values.

**Why:** the detail view can only display what the schema can hold. Event-date anchoring is not modelled yet, and the recipient fields for predefined rows are not free-form.

**Split?** No (the scheduling split itself is tracked under Story 5).

---

### Story 5 — Template Edit → **Split + Amend (largest change)**

**What it says now:** Admin can edit **every** field — `Template Name, Type, Trigger Event, Channel, Status, FROM (with Reply-To), TO, CC, BCC, Subject, Body, Scheduling, Follow-up` — with a WYSIWYG editor supporting **image upload + inline images**, hyperlinks, CTA buttons, and merge fields from **Show Details, Customer, Contract, Order, Product, Salesperson, Employee**; plus scheduling relative to *event date or trigger event*, timezone, send time, and follow-up *delay + number of attempts*.

**Suggested change 5a — editable-field matrix (Amend):** replace the single flat "Admin can edit [all fields]" list with the **two-tier matrix** (see cross-cutting rec. A):

| Field | Predefined | Custom |
|---|---|---|
| Trigger Event | read-only | editable (from dropdown) |
| Channel | read-only | editable |
| FROM / `sender_id` | read-only (system) | editable (domain/E.164 rules) |
| TO | read-only (system) | editable |
| Subject (email) | editable | editable |
| Body | editable | editable |
| Status, Type | editable | editable |
| from_name, reply_to, CC, BCC (email) | editable | editable |

The story's "Save disabled until FROM/TO valid" rule must also acknowledge that for predefined rows those fields are system-supplied, not admin input.

**Suggested change 5b — image upload (Split → later phase):** the WYSIWYG requirement for **image upload + inline images** requires asset storage/hosting (S3 or equivalent), which is outside the CRUD/config scope. **Split this into its own story** (template asset upload & hosting). For this phase, restrict the editor to text formatting, hyperlinks, CTA buttons, and **referenced image URLs** (no upload).

**Suggested change 5c — merge-field sources (Amend / scope):** the merge-field sources include **Contract, Order, Product** — modules that **don't exist yet** (these are the same modules the 26 deferred templates depend on). Their placeholders cannot resolve for the 18 in-scope templates. Narrow the available merge-field sources **for this phase** to what exists (Show Details, Customer, Salesperson, Employee) and reintroduce Contract/Order/Product **with the modules that create them**.

**Suggested change 5d — scheduling & follow-up (Split → later phase):** editing schedule/follow-up is **store-only** in this phase — no worker consumes `schedule_config` / `follow_up_config` yet. **Split** "configure & store schedule/follow-up" (this phase, the admin fills the form and it's saved) from "scheduler/worker executes them" (later phase). Also reconcile the story's follow-up **"number of attempts"** with the implemented shape: `follow_up_config` is an **array of steps** (each a delay), where the number of attempts = number of steps. Stop conditions and per-step template references are explicitly deferred.

**Why:** the story bundles three different things — configuration (deliverable now), send-time execution (deferred), and asset hosting (deferred) — and it ignores the agreed read-only rules for predefined templates. Splitting keeps each sprint's commitment honest.

**Split?** **Yes** — carve out (1) image upload/hosting and (2) schedule/follow-up *execution* as separate later-phase stories; the remaining Edit story covers configuration + storage with the two-tier matrix.

---

### Story 6 — Recipient Configuration → **Split + Amend (second largest)**

**What it says now:** configure `FROM / TO / CC / BCC` using **static addresses, internal group aliases, dynamic placeholders** (`{client_email_address}`, `{salesperson_email_address}`, `{additional_client_email_address}`, `{all_speaker_email_addresses}`, SMS `{client_cellphone_number}` + speaker mobiles), and **show-detail based fields** "by column header and city," with placeholders **resolved at execution time** based on context.

**Suggested change 6a — dynamic placeholder resolution (Split → later phase):** **resolution of dynamic placeholders at send time is out of scope** for this phase — the schema stores **literal recipient values** today. Recommended boundary: **this phase stores the placeholder tokens as configuration** (the admin can pick `{client_email_address}` and it's saved on the template), and a **separate "dynamic recipient resolution" story** does the send-time resolution (with the graceful-failure behaviour the story already describes — skip/notify when a placeholder can't resolve). Make this configure-vs-resolve boundary explicit so the story isn't read as "sending to dynamic recipients works now."

**Suggested change 6b — internal group aliases (Amend / new dependency):** the story requires aliases be **selected from a configured list** and forbids free-text. **No alias lookup/table exists** in the current design. Either add a small **alias-configuration story** (a managed list admins pick from) or **defer alias support** entirely — but the story should not imply aliases work in this phase.

**Suggested change 6c — show-detail-based fields (Split → later phase):** the "by column header and city" show-detail recipient fields are **not modelled** in the schema. Defer to a dedicated later-phase story, alongside the dynamic-resolution work.

**Suggested change 6d — predefined recipients (Amend):** the story's validation says *"FROM and TO must not be empty"* and treats them as editable. For **predefined templates**, FROM/TO/`sender_id` are **system-controlled and read-only** (cross-cutting rec. A). State the tier rules so the validation reads correctly for both predefined and custom rows.

**Why:** the story describes a fully dynamic, resolved recipient engine; this phase implements a literal-value configuration store. Splitting the resolution/alias/show-detail pieces out keeps the in-scope work (store recipient config, including placeholder tokens) clearly deliverable.

**Split?** **Yes** — separate (1) dynamic-placeholder *resolution* at send time and (2) show-detail-based fields into later-phase stories; optionally (3) internal-group-alias management as its own story. The remaining story covers storing recipient configuration (literal values + placeholder tokens) with the two-tier rules.

---

## Summary

| # | Story | Verdict | Headline change | Phase impact |
|---|---|---|---|---|
| 1 | Listing | Amend (minor) | "Last Modified By/Date" sourced from audit log, not a dropped column; define never-edited state | No new phase |
| 2 | Search | No change | Aligned; confirm whether Subject is in search scope | No new phase |
| 3 | Filter | Amend | Type `Event` → `System`; drop Channel `Both` | No new phase |
| 4 | Detail View | Amend | Event-date-anchored scheduling not modelled; predefined recipients shown system-managed | Display narrows to current capability |
| 5 | Edit | **Split + Amend** | Add predefined/custom edit matrix; split out image upload + schedule/follow-up *execution*; defer Contract/Order/Product merge fields | 2 later-phase stories carved out |
| 6 | Recipient Config | **Split + Amend** | Store placeholder tokens now, resolve later; alias list doesn't exist; show-detail fields unmodelled; predefined FROM/TO read-only | 2–3 later-phase stories carved out |

**Net effect:** Stories 1–4 stay in this phase with wording corrections. Stories 5 and 6 stay in this phase for their *configuration/storage* half, with their *execution/resolution/asset-hosting* halves carved into clearly-labelled later-phase stories. Every change traces back to one of two root causes — the missing **predefined-vs-custom** distinction, or the **configure-now / execute-later** boundary — and none contradicts the confirmed schema design.

# Email & SMS Management — Suggested User-Story Revisions (V2)

**Module:** Email & SMS Management
**Version:** V2 — supersedes V1 (`EMAIL_SMS_STORY_REVISIONS.md`, 2026-06-01). V1 is retained unchanged as the historical baseline.
**Date:** 2026-06-03
**Audience:** Product / BA / Sprint planning / Management
**Source stories (V2):** `Email & SMS Management Upadated Epic.xlsx` — restructured into two epics (76.x Predefined, 77.x Custom)
**Source stories (V1):** `Email & SMS Management.xlsx` — original 6 single-spec stories
**Reference design:** `EMAIL_SMS_DB_DESIGN_REVIEW.md`, `.claude/plans/email-sms-management-crud-design.md`
**Related:** `EMAIL_SMS_KNOWN_ISSUES.md` (running register of deferrals, dependencies, contradictions)

---

## Purpose of this document

This version exists for two reasons:

1. **Carry the current revisions** — realign the suggested story revisions to the restructured two-epic backlog and the scope decisions confirmed since V1.
2. **Trace the history of how V1 became V2** — every material change is logged with *what changed, why, and what triggered it*, so the evolution of the requirement is auditable. This is deliberate: the requirement moved underneath the team (the epic was restructured mid-stream, and scope was negotiated down), and that movement — not the CRUD coding itself — is where the analysis time went. The Change Log below makes that defensible at a glance.

V1 remains on disk unedited. Read V1 for the original 6-story analysis; read this for the current, two-epic position plus the delta between them.

---

## Why this wasn't "just a CRUD" (effort narrative)

For management context: the build surface here genuinely is CRUD, but the **requirements work around it was not**. The hours are accounted for by analysis and scope control, each of which produced a concrete artifact:

- **Two-tier model on one table.** Predefined (system-seeded, mostly read-only) and custom (admin-owned, full CRUD) share one table via an `is_predefined` flag, each with different edit rules. Designing and documenting which fields are editable per tier is a rules problem, not a typing problem. → `EMAIL_SMS_DB_DESIGN_REVIEW.md`
- **Polymorphic channel config.** Email and SMS templates have different shapes; six email-only columns were folded into one `channel_config` JSONB so SMS rows don't carry dead columns and future channels need no migration. → schema design doc
- **A mid-stream epic restructure.** The single 6-story spec was reissued as **two epics** (predefined vs custom) with new numbering and rules. The earlier analysis had to be re-mapped onto the new structure. → this document's Change Log
- **Four scope deferrals, negotiated and confirmed.** Scheduling (×2), SMS provider, and dynamic recipient resolution were taken out of the current sprint — each confirmed to need **zero schema change** to defer. → `EMAIL_SMS_KNOWN_ISSUES.md` #1–3
- **A spec self-contradiction surfaced.** The stories disagree with themselves on the Template Type list (`Event` vs `System`); we identified it, chose `System`, and routed reconciliation to BA/docs. → `EMAIL_SMS_KNOWN_ISSUES.md` #5
- **Endpoint reconnaissance for the recipient picker.** The "select recipients from a predefined list" requirement depends on listing endpoints owned by other modules; those were located and catalogued (without us claiming ownership). → `EMAIL_SMS_KNOWN_ISSUES.md` #4

None of the above is inflation — each item is backed by a file in this repo.

---

## Change Log — V1 → V2

Every row is one discrete change from the V1 analysis to the V2 position. Trigger tags: `[Epic restructure]` (the backlog itself changed), `[Scope decision]` (item moved out of sprint), `[Spec contradiction]` (spec disagreed with itself), `[Dependency discovery]` (depends on something we don't own), `[Design confirmation]` (a previously-implied fact was nailed down).

| # | Area / Story | V1 position | V2 position | Why changed | Trigger | Date |
|---|---|---|---|---|---|---|
| 1 | Document basis | 6 single-spec stories (one combined backlog) | Two epics: **76.x Predefined** (edit-only; Email+SMS) and **77.x Custom** (full CRUD; Email only), shown separately in UI, same API endpoints (`is_predefined` branch) | Client reissued the backlog | `[Epic restructure]` | 2026-06-03 |
| 2 | Custom channel scope | Custom templates could be Email or SMS | **Custom = Email only** (no custom SMS anywhere in 77.x) | New epic has no custom SMS stories | `[Epic restructure]` | 2026-06-03 |
| 3 | Scheduling (`76.6` / `77.8`) | In-phase, store-only; "split execution into later story" | **Deferred — out of current sprint**; `schedule_config` / `follow_up_config` columns kept **nullable**, no writer this sprint | Sprint scope confirmed by stakeholder | `[Scope decision]` | 2026-06-03 |
| 4 | SMS provider (`76.8`) | Implied future capability; SMS templates manageable now | **Deferred — client dependency**; SMS templates still stored/edited, sending gated | Sprint scope confirmed | `[Scope decision]` | 2026-06-03 |
| 5 | Dynamic recipient resolution (`77.9`) | "Split resolution into later-phase story" | **Deferred story**; tokens stored now, resolution later | Sprint scope confirmed | `[Scope decision]` | 2026-06-03 |
| 6 | Image upload (WYSIWYG) | "Split into asset upload/hosting story" | **Separate story module** developed independently; **this implementation stores the provided HTML body only** | Confirmed as its own module | `[Scope decision]` | 2026-06-03 |
| 7 | Template Type enum | Noted `Event`→`System` as a recommendation | **Confirmed: we use `System`**; the `Event` vs `System` story contradiction routed to **BA/documentation** to reconcile | Contradiction confirmed across filter vs edit stories | `[Spec contradiction]` | 2026-06-03 |
| 8 | Recipient picker source | "Internal-group-alias list doesn't exist; add or defer" | **Reuse existing listing endpoints**; they are owned by other modules — we catalogue them, applicability/ownership is the owning team's call | Endpoints located during reconnaissance | `[Dependency discovery]` | 2026-06-03 |
| 9 | Manual recipient entry | Unspecified in V1 | **Manual free-text entry is custom-email only**; predefined picks from lists only | New epic states it explicitly | `[Epic restructure]` | 2026-06-03 |
| 10 | Schema impact of deferrals | Implied ("store-only, deferred later") | **Explicitly confirmed: deferring all four items needs zero schema change** | Stakeholder asked for explicit confirmation | `[Design confirmation]` | 2026-06-03 |
| 11 | Listing columns (custom) | Single listing spec incl. Channel | Custom listing (`77.2`) **drops the Channel column** (custom is all Email) | Two-epic split | `[Epic restructure]` | 2026-06-03 |
| 12 | Filter — Channel (custom) | Channel filter `Email \| SMS \| Both` | Custom filter (`77.4`) has **no Channel filter** (Email-only); predefined filter (`76.3`) keeps `Email \| SMS`, drops `Both` | Two-epic split + single-channel rows | `[Epic restructure]` + `[Spec contradiction]` | 2026-06-03 |

---

## Two cross-cutting recommendations (carried from V1, updated)

### A. Make the **predefined vs custom** distinction explicit

Single table, `is_predefined` flag:

- **Predefined** (76.x; system-seeded): `trigger_event`, `channel`, `FROM` / `sender_id`, and `TO` are **read-only**. Editable: `subject` (email), `body`, `status`, `type`, and email niceties (`from_name`, `reply_to`, `cc`, `bcc`). CC/BCC selected from a predefined recipient list (no manual free-text).
- **Custom** (77.x; admin-created): **Email only**, full create/edit/delete within validation rules (FROM domain whitelist; TO/CC/BCC from predefined list **or** manual free-text).

### B. Separate **"configure & store"** (this phase) from **"execute / resolve / send"** (later)

This phase stores configuration. It does **not** fire scheduled sends, dispatch follow-ups, resolve dynamic recipient placeholders, integrate an SMS provider, or host uploaded images. Those are deferred and tracked in `EMAIL_SMS_KNOWN_ISSUES.md`.

---

## Epic 76.x — Predefined Email & SMS Management

### 76.1 — Template Listing → **Amend (minor)**
- **Change:** *Last Modified By / Date* are derived from the latest `admin_audit_logs` entry, not from a column on the template row (the `updated_by` column was intentionally dropped). Define the **never-edited (freshly seeded)** state — show *System / Seed* or blank, not a person.
- **Why:** the story implies a dedicated column the design removed to avoid duplicating the audit trail.
- **Split?** No.

### 76.2 — Template Search → **No change (one confirmation)**
- Search by Template Name + Trigger Event matches the implementation. Optional: the implementation can also match **Subject** — decide whether to expose it.
- **Split?** No.

### 76.3 — Template Filter → **Amend**
- **Type:** story lists `…PPL, Event`; schema enum is `…PPL, System`. **Use `System`** (see Change Log #7 / known-issues #5).
- **Channel:** drop **`Both`** — each row is single-channel; no selection already returns both. Keep `Email | SMS`.
- **Why:** filter values must map to real column domains.
- **Split?** No.

### 76.4 — Template Detail View → **Amend**
- For predefined rows, `FROM` / `TO` / `sender_id` are **system-managed** — show read-only, not as admin-entered values.
- The scheduling section is **deferred** with story 76.6 — if shown at all, label it a later-phase capability.
- **Split?** No.

### 76.5 — Template Edit → **Amend**
- **Two-tier edit matrix:**

| Field | Predefined | Custom (Email) |
|---|---|---|
| Trigger Event | read-only | editable (from dropdown) |
| Channel | read-only | n/a (Email) |
| FROM / `sender_id` | read-only (system) | editable (domain rules) |
| TO | read-only (system) | editable (list or manual) |
| Subject | editable | editable |
| Body | editable | editable |
| Status, Type | editable | editable |
| from_name, reply_to, CC, BCC | editable (from list) | editable (list **or** manual) |

- **CC/BCC** selected from a predefined recipient list (admin users, exhibitors, system emails); **manual free-text entry is custom-only** (Change Log #9).
- **WYSIWYG** supports formatting, hyperlinks, CTA buttons, and referenced image URLs; **image upload/hosting is a separate module — this phase stores the provided HTML body only** (Change Log #6).
- Merge-field sources for this phase are limited to existing modules (Show Details, Customer, Salesperson, Employee); Contract/Order/Product return with those modules.
- **Split?** No new split here — the previously-suggested splits (image upload, scheduling execution) are now formally **separate/deferred** items, not part of this story.

### 76.6 — Email & SMS Scheduling → **Deferred (out of current sprint)**
- Admin-configurable follow-up schedule (frequency, days after trigger) is **out of scope this sprint**. `schedule_config` / `follow_up_config` columns are kept **nullable** with no writer/reader, so reintroduction later needs no migration. **Zero schema change** to defer. See known-issues #1.

### 76.7 — Template Constants / Placeholders → **No change**
- Controlled picker from a code-maintained list per trigger event; not admin-editable. Already aligned.

### 76.8 — Integrate an SMS Provider → **Deferred (client dependency)**
- Out of scope this sprint. SMS templates remain storable/editable via `NotificationChannel.SMS` + `channel_config`; sending is gated until a provider is integrated. **Zero schema change** to defer. See known-issues #2.

### 76.9 — Audit Log → **Amend**
- "Last modified timestamp & by user" is satisfied via `admin_audit_logs`; "by user" is **derived** from the latest audit entry (no `updated_by` column). Same source as 76.1.
- **Split?** No.

---

## Epic 77.x — Custom Email Management (Email only)

### 77.1 — Create Email Template → **Amend**
- Custom is **Email only**. **FROM** = free-text username + **fixed-domain dropdown** (`TheShowProducers.com` / `TheSmallBusinessExpo.com`) validated against `allowed_from_domains`. **TO / CC / BCC** = select from predefined list **or** manual free-text (subject to validation). WYSIWYG stores **HTML body only** (no upload).
- **Split?** No.

### 77.2 — Email Template Listing → **Amend**
- **No Channel column** (custom is all Email). Columns: Template Name, Type, Trigger Event, Status (Change Log #11).
- **Split?** No.

### 77.3 — Template Search → **No change**
- By Template Name + Trigger Event; aligned.

### 77.4 — Template Filter → **Amend**
- **Type:** use `System` (not `Event`). **No Channel filter** (Email-only) (Change Log #12). Status filter as written.
- **Split?** No.

### 77.5 — Template Detail View → **No change**
- Read-only full view; Subject always present (Email). Switch-to-edit as written.

### 77.6 — Template Edit → **Amend**
- Mirrors 77.1 field rules; full edit (custom). Same FROM/TO/CC/BCC and HTML-only WYSIWYG rules.
- **Split?** No.

### 77.7 — Template Constants / Placeholders → **No change**
- Code-controlled picker; aligned.

### 77.8 — Email & SMS Scheduling → **Deferred (out of current sprint)**
- Same as 76.6 — deferred, columns nullable, zero schema change. See known-issues #1.

### 77.9 — Dynamic Recipient Resolution Engine → **Deferred (out of current sprint)**
- Send-time resolution of `{salesperson}`, `{main customer contact}`, `{all customer contacts}`, internal Gmail groups, etc. is **out of scope**. `to_recipients` stores literal strings / tokens now; resolution is a later story. **Zero schema change** to defer. See known-issues #3.

### 77.10 — Audit Log → **Amend**
- Same as 76.9 — satisfied via `admin_audit_logs`, "by user" derived.

---

## Recipient picker (TO / CC / BCC predefined lists)

The "select from a predefined list" requirement reuses **existing listing endpoints owned by other modules**. We catalogue the available endpoints in `EMAIL_SMS_KNOWN_ISSUES.md` #4 and make **no judgment** on which apply or how they are scoped — that is the owning team's call. The "other relevant system emails" list referenced in the stories has **no observed source endpoint** and is flagged there for an owner.

---

## Summary — Epic 76.x (Predefined)

| Story | Verdict | Changed since V1? | Headline change |
|---|---|---|---|
| 76.1 Listing | Amend (minor) | refined | Last Modified By/Date from audit log; never-edited state |
| 76.2 Search | No change | — | Confirm whether Subject is in scope |
| 76.3 Filter | Amend | yes | `Event`→`System`; drop Channel `Both` |
| 76.4 Detail View | Amend | yes | Predefined recipients system-managed; scheduling deferred |
| 76.5 Edit | Amend | yes | Two-tier matrix; manual entry custom-only; HTML-only WYSIWYG |
| 76.6 Scheduling | **Deferred** | yes | Out of sprint; columns nullable; zero schema change |
| 76.7 Placeholders | No change | — | Code-controlled picker |
| 76.8 SMS provider | **Deferred** | yes | Client dependency; templates still stored |
| 76.9 Audit Log | Amend | refined | "By user" derived from audit log |

## Summary — Epic 77.x (Custom Email)

| Story | Verdict | Changed since V1? | Headline change |
|---|---|---|---|
| 77.1 Create | Amend | yes | Email-only; FROM domain dropdown; list-or-manual recipients; HTML-only |
| 77.2 Listing | Amend | yes | No Channel column |
| 77.3 Search | No change | — | Aligned |
| 77.4 Filter | Amend | yes | `Event`→`System`; no Channel filter |
| 77.5 Detail View | No change | — | Subject always present |
| 77.6 Edit | Amend | yes | Mirrors create; full edit |
| 77.7 Placeholders | No change | — | Code-controlled picker |
| 77.8 Scheduling | **Deferred** | yes | Out of sprint; zero schema change |
| 77.9 Dynamic Recipient Resolution | **Deferred** | yes | Store tokens now, resolve later |
| 77.10 Audit Log | Amend | refined | "By user" derived from audit log |

**Net effect:** the in-scope work is the CRUD/configuration layer across both epics with the wording corrections above. Four stories (76.6, 76.8, 77.8, 77.9) are deferred with **no schema change required to defer them**. The Change Log records why each of these positions differs from V1 — predominantly the mid-stream epic restructure and the confirmed scope deferrals, not rework of delivered code.

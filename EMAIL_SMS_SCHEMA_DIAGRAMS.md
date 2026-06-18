# Email & SMS Management — Schema Diagrams Explained

**Date:** 2026-06-18
**Companion files:** `EMAIL_SMS_SCHEMA_EXISTING.svg` (today) · `EMAIL_SMS_SCHEMA_PROPOSED.svg` (scheduling work)
**Source of truth:** `admin-backend-api/prisma/schema.prisma` (current) · `EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` §2.0–§2.3 (proposed)

This document walks through the two entity-relationship diagrams for the notification subsystem: what exists today, what the scheduling work adds, and *why* each change is shaped the way it is. It is the reading companion to the two SVGs — open the SVG alongside the matching section.

Throughout, the visual conventions are:

| Convention | Meaning |
|---|---|
| **bold red** column | primary key |
| *blue italic* column | foreign key |
| **green** text / heavy green border | NEW or changed in the proposed schema |
| solid connector | a real database foreign key |
| dashed grey connector | a *logical* reference resolved in code — **no** DB foreign key |
| grey entity box | existing domain table (not owned by this module) |

---

## 1. Existing schema (`EMAIL_SMS_SCHEMA_EXISTING.svg`)

The notification subsystem today is three tables plus a small whitelist, and **two** relationships.

### 1.1 Entities

**`trigger_events`** — the code-controlled catalog of valid trigger slugs. Each row is a `slug` (unique), a human `label`, an optional `available_placeholders` JSON, and an `is_custom` flag. There is no admin CRUD on this table; rows are seeded. It is the *vocabulary* of "things that can cause a notification."

**`notification_templates`** — the hub of the subsystem. One row per template: the message body/subject, its `channel` (`EMAIL` | `SMS`), its admin-facing `tag` (`Store` / `Internal` / `Vendor` / `Product` / `PPL` / `System`), `language`, an `is_predefined` flag (true for all 18 seeded rows), and `is_active`. Its `notification_type` column is a foreign key to `trigger_events.slug` — every template is bound to exactly one trigger.

> **Two JSON columns already exist here:** `schedule_config` and `follow_up_config`. They are **advisory** — nothing reads them at runtime today. They were added in anticipation of scheduling but carry no authoritative behavior.

**`notification_logs`** — the per-send delivery ledger. One row per attempted send, with the rendered `subject`/`body`, delivery `status`, provider message id, retry count, and `sent_at`. Its `id` is a **BigInt** (this table grows with send volume). FK to `notification_templates.id`, plus optional FKs to `user`/`exhibitor`.

**`allowed_from_domains`** — a standalone service-layer whitelist of domains a custom EMAIL template may send *from*. No relationship to the other three.

**Enums:** `NotificationChannel { EMAIL, SMS }` and `NotificationTemplateType { Store, Internal, Vendor, Product, PPL, System }`.

### 1.2 Relationships (only two exist today)

1. `trigger_events` **1 — N** `notification_templates` — via the `slug ← notification_type` FK. A trigger may have many templates; a template needs exactly one trigger. The direction is one-way: a template requires a trigger, a trigger needs no template.
2. `notification_templates` **1 — N** `notification_logs` — every send is logged against its template.

### 1.3 Domain tables (present, but unlinked)

`Cart`, `Order`, `PaymentTransaction`, and `Shows` are existing domain tables that happen to carry **date fields** that *could* anchor a scheduled send:

| Table | Candidate date | Recipient field | Notes |
|---|---|---|---|
| `Cart` | `expiration_date` (nullable) | `client_email` (nullable) | indexed on `expiration_date` |
| `Order` | `paid_in_full_at` (nullable) | `billing_email` (nullable) | completion-set — written *after* the event it marks |
| `PaymentTransaction` | `due_date` (**NOT NULL**) | `→ order.billing_email` (one hop) | indexed `(status, due_date)` — strongest anchor |
| `Shows` | `date` (date-only, nullable) | — | weak; model is named `Shows`, not `Show` |

**Today these have no FK and no logical link to the notification tables.** The whole point of the scheduling work is to *use* these dates without bolting hard foreign keys onto domain tables.

### 1.4 The gap this leaves

Sends are **immediate / transactional** — fired synchronously when a trigger occurs. There is no schedule table, no queue of future sends, and no time-based dispatch. "Send a reminder 7 days before the payment is due" is simply not expressible.

---

## 2. Proposed schema (`EMAIL_SMS_SCHEMA_PROPOSED.svg`)

The scheduling work makes **four** structural additions. The existing notification core keeps its shape; everything green is new.

### 2.1 Two new columns — the schedulability gate

| Column | Table | Type | Purpose |
|---|---|---|---|
| `supports_scheduling` | `trigger_events` | `Boolean @default(false)` | **catalog ceiling** — code-controlled. Marks which triggers are *allowed* to carry scheduled templates at all. |
| `is_schedulable` | `notification_templates` | `Boolean @default(false)` | **per-template marker** — the first-class switch that says "this template may carry a schedule." |

These are *marked*, never inferred from "does a schedule row exist?" The backfill leaves **all 18 seeded templates `is_schedulable = false`**; the trigger gate is opened on a small set of slugs for *future* custom templates (the exact set is a product decision — see scheduling known-issue **SCH-2**).

**Integrity rule (§2.3, enforced in the service layer — not a DB CHECK or partial index, so sibling-service `db push` stays clean):**

1. A template may be set `is_schedulable = true` **only if** its trigger's `supports_scheduling = true`.
2. A `notification_schedules` row may attach **only to** an `is_schedulable = true` template.

### 2.2 New table — `notification_schedules` (the send-rule)

One row per **send-rule** — the durable *intent*. Key columns:

- `id` (Int PK), `notification_template_id` (FK → templates, `onDelete: Cascade`, target must be schedulable).
- `schedule_kind` — `ANCHOR_RELATIVE` | `RECURRING` | `FOLLOW_UP` (the authoritative kind; the template's `schedule_config` hint is advisory only).
- **ANCHOR_RELATIVE fields:** `anchor_entity` / `anchor_field` (which domain date to read), `offsets` JSON (`[{ value, unit, direction }]`, multi-offset is first-class), `recipient_source` + `replacements_map` (a **restricted** resolver: a bare anchor column, or the fixed transforms `FULL_NAME(...)` / `DATE_FMT(...)` — never an arbitrary expression language).
- **RECURRING fields:** `recurrence` JSON (`{ daysOfWeek[], time }` or `{ intervalDays }`).
- **FOLLOW_UP fields:** `follow_up` JSON (`{ delayDays, repeatCount, frequency? }`).
- **Common:** `send_time`, `timezone` (`EVENT` or an IANA zone), `stop_condition` (`CONTRACT_SIGNED` / `QUESTION_ANSWERED` / `CART_CONVERTED` / `NONE`), `end_window_at`, `is_enabled`, `created_at` / `updated_at`.

> `updated_at` doubles as the **re-materialization watermark**: when a rule is edited, stale future PENDING occurrences are superseded and recomputed (plan §4.3).

**Per-kind field matrix (§2.1.1):** which fields are required/forbidden depends on `schedule_kind`, enforced with `@ValidateIf` at the DTO. A hard rule prevents unbounded series: every RECURRING / FOLLOW_UP must carry **at least one bound** (`end_window_at`, `repeatCount`, or an implemented `stop_condition`).

### 2.3 New table — `notification_schedule_occurrences` (the materialized send)

One row per **materialized due-send** computed from a rule — the executable, idempotent, auditable unit the worker dispatches. Key columns:

- `id` (**BigInt** PK — high-volume table, the one approved BigInt exception, mirroring `NotificationLog`), `schedule_id` (FK → schedules, `onDelete: Cascade`).
- **Stable identity:** `anchor_instance_ref` (e.g. `cart:123`), `offset_key` (e.g. `-7d`), `sequence_index` (FOLLOW_UP position) — and `dedupe_key` (`UNIQUE`) built from these, **never from `fire_at`** (which is derived and shifts with tz/DST). This is what guarantees exactly-once.
- `channel` — denormalized from the template so the dispatch query can filter `EMAIL` and a separate pass flips `SMS` rows to `SKIPPED` with no template join.
- `recipients_snapshot` JSON (`{ to[], cc[], bcc[], replacements, from_name?, reply_to? }`) — captured at materialize time (ANCHOR_RELATIVE) or at the live send site (FOLLOW_UP), then replayed verbatim at dispatch. **This is how FOLLOW_UP works without DRR.**
- `fire_at` (recomputed for PENDING rows, frozen once `SENT`/`SENDING`), `series_anchor_at`, `anchor_value_at_materialize`.
- **Lifecycle / safety:** `status` (`PENDING` → `SENDING` → `SENT` / `SKIPPED` / `CANCELLED` / `FAILED`), `attempt_count`, `next_attempt_at`, `claimed_at` (for the `SENDING`-reaper that self-heals a crashed claim).
- `notification_log_id` (BigInt FK → `notification_logs`, nullable) — links the actual send.
- **Indexes:** `(status, fire_at)` due-poller, `(status, next_attempt_at)` retry-scan, `(schedule_id)`.

For the full rationale of why occurrences are first-class rows rather than computed on the fly, see §4 below.

### 2.4 New enums

- `NotificationScheduleKind { ANCHOR_RELATIVE, RECURRING, FOLLOW_UP }`
- `NotificationStopCondition { CONTRACT_SIGNED, QUESTION_ANSWERED, CART_CONVERTED, NONE }` — only `NONE` is guaranteed live at launch; the resolver set is still being finalized (SCH-4).
- `OccurrenceStatus { PENDING, SENDING, SENT, SKIPPED, CANCELLED, FAILED }`
- `NotificationChannel` is reused, not duplicated.

### 2.5 Relationships in the proposed schema

| From | Card. | To | Kind |
|---|---|---|---|
| `notification_templates` | 1 — N | `notification_schedules` | real FK; **gated** by `is_schedulable` |
| `notification_schedules` | 1 — N | `notification_schedule_occurrences` | real FK |
| `notification_schedule_occurrences` | N — 1 | `notification_logs` | real FK, **nullable** (set on send) |
| `notification_schedules` | logical | `Cart` / `PaymentTransaction` / `Order` / `Shows` | **dashed — no FK**; resolved in code |

The dashed lines are deliberate: `anchor_entity` / `anchor_field` are an enum + string the **worker materializer** resolves at runtime. No foreign key is added to any domain table, which keeps the domain models untouched and avoids cross-module coupling.

### 2.6 Anchor roles (the dashed references)

| Anchor | Role in scheduling |
|---|---|
| `PaymentTransaction.due_date` | ANCHOR_RELATIVE (forward) — strongest; NOT NULL + indexed. First shippable anchor. |
| `Cart.expiration_date` | ANCHOR_RELATIVE (forward) — nullable, guarded; must be mirrored into the worker schema first. |
| `Order.paid_in_full_at` | **FOLLOW_UP-only** — completion-set, so forward `before` offsets are rejected. |
| `Shows.date` | Deferred — date-only, weak, timezone handling pending. |

---

## 3. What did *not* change

- The three existing tables keep their columns and their two relationships; only the two boolean flags are added.
- `schedule_config` / `follow_up_config` remain on `notification_templates` as **advisory author hints** — the new tables are the authoritative store; the dispatcher never reads the JSON columns.
- No DB CHECK constraints or partial indexes are introduced (the team avoids raw-SQL-only constructs because a sibling `db push` would drop them). All invariants are service-layer enforced.
- No foreign keys are added to domain tables (`Cart` / `Order` / `PaymentTransaction` / `Shows`).

---

## 4. Why two tables (rule vs. occurrence)?

The split between `notification_schedules` (intent) and `notification_schedule_occurrences` (materialized work) is the structural reason the engine can be **exactly-once, crash-safe, and editable after the fact**:

1. **Idempotent, exactly-once dispatch** — each occurrence has a stable `dedupe_key`; re-running a tick, a worker restart, or re-materialization after a rule edit never produces a duplicate send.
2. **"Never rewrite a sent occurrence" (AC-3/AC-4)** — PENDING rows recompute when the rule changes; `SENT`/`SENDING` rows are immutable. That guarantee needs a persisted per-send row.
3. **Safe concurrent dispatch** — the `PENDING → SENDING` atomic claim plus the `SENDING`-reaper prevent double-sends and self-heal a crash mid-send.
4. **Frozen recipients without DRR** — `recipients_snapshot` lets a FOLLOW_UP series fire later without Dynamic Recipient Resolution.
5. **Stop-conditions & downtime catch-up are row queries** — "cancel the rest once the contract is signed" and "skip sends older than the catch-up window" are simple `UPDATE`s because sends are first-class rows.
6. **Audit** — a permanent ledger of what was scheduled, when it fired, which `NotificationLog` it produced, and why anything was skipped/cancelled.

---

## 5. Scope boundary (shown on the proposed diagram)

The scheduling build **excludes** two things, called out in the diagram legend:

- **SMS dispatch** — SMS occurrences *materialize* (so the model is forward-compatible) but are **SKIPPED at dispatch** until an SMS provider is integrated (base known-issue #2). There are 0 SMS templates today regardless.
- **Dynamic Recipient Resolution (DRR)** — token recipients (`{salesperson}`, speaker lists) are deferred (base known-issue #3). Only column / one-hop / fixed recipients dispatch now; token-recipient occurrences SKIP at materialize.

---

## 6. Cross-references

- `EMAIL_SMS_SCHEDULING_STORY.md` — acceptance criteria (AC-20 schedulability gate, AC-21 recipient feasibility).
- `EMAIL_SMS_SCHEDULING_IMPLEMENTATION_PLAN.md` — §2.0 flags, §2.1/§2.2 tables, §2.3 integrity, §4 executor.
- `EMAIL_SMS_TEMPLATE_INTEGRATION_GUIDE.md` — field reference + worked examples for wiring a non-seeded template.
- `EMAIL_SMS_SCHEDULING_KNOWN_ISSUES.md` — SCH-1…SCH-6 (incl. SCH-2 trigger-gate sign-off, SCH-4 stop-condition resolver set).
- `EMAIL_SMS_SCHEDULING_FLOWCHART.svg` / `EMAIL_SMS_SCHEDULING_ARCHITECTURE.svg` — runtime flow and 3-layer architecture.

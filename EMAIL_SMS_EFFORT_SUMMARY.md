# Email & SMS Management — Management Summary

**What this is:** A one-page summary of why the Email & SMS Management module required substantial analysis and design effort before coding. Written for a technical-leadership / management audience comfortable with databases, services, and cloud infrastructure.

**The one-line takeaway:** This is not a standalone "build some screens" feature — it is a configuration layer on top of a **shared production database read by five backend services**, built while requirements were still changing (SMS and scheduling arrived mid-analysis). The upfront work is what makes it safe to ship without breaking 14 live notification flows.

---

## At a glance

- **Scope this phase:** Admin-panel CRUD for notification templates (list, search, filter, view, edit, recipient config).
- **Surface area:** 1 shared PostgreSQL DB · 5 NestJS services · 14 live email flows in production · 40-template client wish-list.
- **Deferred (designed-for, not built):** scheduler/time-delays, SMS provider integration, mailer changes — all can attach later with no rework.

---

## 1. Why analysis took real time (not just coding)

- Requirements came from **3 documents that contradicted each other** — two spreadsheets and a live client email thread. The email thread's decisions **overrode** the spreadsheets, so reconciling them was a prerequisite to any design.
- The client's wish-list of **40 templates overlaps with only ~5 of the 14 notifications the system actually sends today.** The other 26 depend on product modules (Contracts, Cart, Orders, Booth) **that don't exist yet.** We had to derive the *real* build list (18 templates) rather than build against the spreadsheet verbatim.
- Two requirements arrived **mid-analysis**: SMS (4 templates, but **no SMS provider exists**) and time-delay scheduling (client says essential, ~11 templates need it). Both forced a more flexible design than an email-only one.

## 2. Why this touches the whole platform, not one service

- **One PostgreSQL database is shared by all 5 backend services.** Any schema change must be safe for every service — a bad change breaks more than the admin panel.
- **Only one service (`admin-backend-api`) owns DB migrations;** the other four consume the same schema read-only. So changes must be coordinated and verified across all five before they're safe to deploy.
- **14 live notification flows** (welcome emails, password resets, lead notifications, Stripe/PPL order confirmations) already run in production across 4 services. The design had to guarantee these keep working untouched.
- There are **4 separate copies of the email-sending code** (one per sending service) — so backward compatibility had to be confirmed in four places, not one.

## 3. Key design decisions (and the trade-offs behind them)

- **Single table for both system and admin-created templates**, flagged by a boolean — keeps queries simple, but moves the "who can edit what" rules into application logic.
- **Recipient settings stored as flexible JSON instead of fixed columns** — so SMS rows don't carry empty email columns, and future channels (Push, WhatsApp) won't need a new DB migration. Trade-off: validation moves from the database into the application (extra logic we specified).
- **Channel field upgraded from free text to a strict enum (EMAIL/SMS)** — verified all existing rows are safe to convert before doing it.
- **A data-integrity guard** ensures each system trigger maps to exactly one template, so a lookup can never return duplicates — and admins are structurally prevented from inventing new triggers.
- **Reused the existing audit-log system** for edit history instead of building a new one — smaller change, full change-tracking.
- **Scheduling/follow-up settings are stored now but not yet acted on** — so the admin UI is built once, and the future scheduler (a background worker) plugs in without front-end rework.

## 4. Risks avoided through upfront analysis

- **Avoided shipping 26 broken templates** wired to triggers that don't exist.
- **Avoided a failed production migration** — the channel-type upgrade was verified safe against existing data first.
- **Avoided breaking 14 live notification flows** — every new field is optional and the send path is unchanged; a smoke-test plan covers all of them.
- **Avoided a cross-service outage** — the change is verified against all five services, not just the one being edited.
- **Avoided duplicate/ambiguous data** via the one-trigger-one-template integrity guard.
- **Avoided future rework** — the flexible design absorbs the deferred SMS and scheduling work without redesign.

## 5. Coordination & communication effort

- Tracked a **7-message client thread** (client SVP Ops + CEO) and mapped each decision onto the design.
- Handled an **open product disagreement** (scheduling: client = essential, us = later phase) by designing for "store now, act later" rather than forcing a premature call.
- Produced **19 itemized open questions, ranked by urgency** (must-answer-before-coding vs decide-later), so blockers surface before the sprint, not during it.
- Delivered **two review documents** with traceability mapping every design element back to a specific user story or client request.

---

## Bottom line for planning

The time went into **analysis, integrity, and safety on a shared production system** — deriving the real scope, protecting 14 live flows across 5 services, and designing once for requirements (SMS, scheduling) that are still settling. The result is a configuration foundation that the deferred scheduler and SMS work can build on **without revisiting this phase.**

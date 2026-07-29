# Order Epics — Jira / CI / Repo Snapshot

> **Session-close snapshot — 2026-07-29.** Read this first when resuming any Order History (Epic 13 / SBE-1070) or
> Order Management (Epic 24 / SBE-1078) work. It is the fast index of *ticket ↔ story ↔ status* plus the live CI /
> repo state as of close. For per-story requirements & implementation detail, go to the folders under
> `order_history/` and `order_management/` (GDrive-synced) and the feasibility `_Summary.xlsx` per epic.

## Atlassian coordinates (for JQL from a fresh session)

- **Jira cloudId:** `9d7cfd50-93fc-4f57-a572-9a45c4ae4455` (site `unifiedinfotech.atlassian.net`, project `SBE` / id 11158).
- **OM epic:** [SBE-1078](https://unifiedinfotech.atlassian.net/browse/SBE-1078) "Order Management" — status **To Do** (epic stays open until QA + release).
- **OH epic:** [SBE-1070](https://unifiedinfotech.atlassian.net/browse/SBE-1070) "Order History" — status **To Do**.
- Confluence: OM page `3859742741` (Admin Panel), OH page `3858137106` (Exhibitor Store). OM Page-2 `3984654414`.
- Handy JQL: `parent = SBE-1078 ORDER BY key ASC` / `parent = SBE-1070 ORDER BY key ASC`.
  (Default-field responses are huge — pass tight `fields` and/or `jq` the saved tool-result file.)

## Pattern: two ticket sets per epic

Each epic carries **build tickets** (assignee **Prantik Saha**, the dev deliverables — all merged to `dev`) **and a
parallel QA set** (assignee **Rohit Gupta**, status **In QA Testing**) that mirror the same story titles. Build =
DEV DONE; QA set tracks the QA pass separately.

## Order Management — Epic SBE-1078 (admin-backend-api, Swagger `/api/docs/admin`)

| Story | Title | Build ticket | Build status | QA ticket (Rohit) | QA status |
|---|---|---|---|---|---|
| 24.1 | View and manage all orders | SBE-1125 | ✅ Done | SBE-1541 | In QA Testing |
| 24.2 | Filters | SBE-1126 | ✅ Done | SBE-1542 | In QA Testing |
| 24.3 | Search Order | SBE-1127 | ✅ Done | SBE-1543 | In QA Testing |
| 24.4 | Sorting | SBE-1128 | ✅ Done | SBE-1544 | In QA Testing |
| 24.5 | Quick Actions Per Order Item | SBE-1129 | ✅ Done | SBE-1545 | In QA Testing |
| 24.6 | Order Details | SBE-1130 | ✅ Done | SBE-1546 | In QA Testing |
| 24.7 | Manual Payment Methods | SBE-1131 | ✅ Done | SBE-1547 | In QA Testing |
| 24.8 | Payment Plan Management | SBE-1132 | ✅ Done | SBE-1548 | In QA Testing |
| 24.9 | Refund Management | SBE-1133 | ✅ Done | SBE-1549 | In QA Testing |
| 24.10 | Order Cancellation | SBE-1134 | ✅ Done | SBE-1550 | In QA Testing |
| 24.11 | Order Cancellation — Email Notification | SBE-1135 | ✅ Done | SBE-1551 | In QA Testing |
| 24.12 | Booth Release & Other Products Inventory Behaviour | **SBE-1136** | ⏳ **To Do** | — | — |
| 24.13 | Move / Change Show functionality | **— (unticketed)** | not built | — | — |
| 24.14 | Internal Notes & Administrative Information | SBE-1138 | ✅ Done | SBE-1552 | In QA Testing |
| 24.15 | Payment Reminder Notifications | SBE-1139 | ✅ Done | SBE-1553 | In QA Testing |

**OM net:** 13 of 15 stories DEV DONE + in QA. **Remaining:** 24.12 (SBE-1136, To Do — deferred out of the Phase-1
release) and 24.13 (no Jira ticket — `SBE-1137` does not exist; treat as unticketed/deferred). Both were marked OOS
for this sprint at the feasibility gate.

## Order History — Epic SBE-1070 (exhibitor-backend-api)

| Story | Title | Build ticket | Build status | QA ticket (Rohit) | QA status |
|---|---|---|---|---|---|
| 13.1 | Order History | SBE-1145 | ✅ Done | SBE-1390 | In QA Testing |
| 13.2 | Order Listing Table | SBE-1146 | ✅ Done | SBE-1391 | In QA Testing |
| 13.3 | Order Details Page | SBE-1147 | ✅ Done | SBE-1392 | In QA Testing |

**OH net:** all 3 stories DEV DONE + in QA. `SBE-1147` was transitioned to **Done on 2026-07-28** — the previously
tracked "SBE-1147 → DEV DONE" action is **closed**; nothing pending.

> Jira description note: build-ticket descriptions carry the routes-only `| Method | Path |` table (per the
> close-out convention). SBE-1147's description still lists the *pre-rework* routes
> (`/orders/:orderId/invoice`, `/agreement/signed/:orderId/download`) rather than the shipped nested/invoice-by-id
> surface — cosmetic drift only, status is Done. Update only if asked.

## Recent shipped work (this + last session)

- **SBE-1147** (13.3) — exhibitor Order Details: product-gate + nested-by-show redesign, then bundled-item
  relationships (`id`/`is_default_included`/`parent:{id,type}`) + agreement `signature_url`. Merged to dev PR#387
  (`02a44be`, exhibitor HEAD). Docs recorded in workspace repo (`9d1ad47`). Jira **Done**.
- **SBE-1146** (13.2/13.3-s) — exhibitor invoice rework: `GET /orders/:orderId/invoices` (list) +
  `GET /orders/invoices/:id` (download by invoice id), replacing latest-only. Jira **Done**.

## CI / pipelines — 2026-07-29 (all green)

New Bitbucket API token **confirmed working 2026-07-29** (`scripts/.bitbucket-creds`; `scripts/check-pipelines.sh`).
Latest pipeline per repo (workspace `unified-dev-cls-a`):

| Repo | Build | Result | Trigger |
|---|---|---|---|
| admin-backend-api | #1082 | ✅ SUCCESSFUL | PR#672 staging→uat |
| exhibitor-backend-api | #567 | ✅ SUCCESSFUL | PR#391 fix/SBE-1742→dev |
| background-worker-service | #56 | ✅ SUCCESSFUL | PR#40 staging→uat |
| external-api-service | #198 | ✅ SUCCESSFUL | PR#134 staging→uat |
| pulse-broker-service | #30 | ✅ SUCCESSFUL | PR#26 staging→uat |

Release trains are moving **staging → uat** on four repos; exhibitor's latest is a `fix/SBE-1742` PR into dev
(ticket scope not order-epic-confirmed — verify if it surfaces again).

## Local repo state at close (2026-07-29)

All five code repos on `dev`, **working tree clean (0 uncommitted)**; workspace-docs repo (`sbe-backend-workspace`)
on `main`, clean, in sync with `origin/main` (HEAD `ea34dc5`). Local `dev` checkouts are **behind** `origin/dev`
(admin −28, exhibitor −13, worker −3; external/pulse in sync) — these are just stale local checkouts (others'
merges), **not** our unpushed work. Run `scripts/sync-dev-branch.sh` in a repo before starting new work there.

- exhibitor `dev` HEAD locally = `02a44be` (our SBE-1147 merge) — origin has moved past it.
- admin `dev` HEAD locally = `d970dd4` (someone else's `fix/SBE-1761` PR#662).

## What's genuinely open

1. **24.12 Booth Release** (SBE-1136) — To Do, deferred from Phase-1. Not started.
2. **24.13 Move/Change Show** — unticketed, not built.
3. **QA cycle** — all shipped OM+OH stories are In QA Testing under Rohit's mirror tickets; expect QA bug tickets
   (see the Sprint-5 bug pattern) rather than new build work.

Everything else across both epics is **DEV DONE and merged**. No uncommitted or unpushed work of ours remains.

# Order Management — Admin Panel User Stories

> **Source:** Confluence — [SBE - Admin Panel](https://unifiedinfotech.atlassian.net/wiki/spaces/SBE/pages/3859742741/SBE+-+Admin+Panel#Order-Management) (Space `SBE`, page `3859742741`)
> **Section:** Story 24 — Order Management (Epic)
> **Page last modified:** Jun 23, 2026 · **Extracted:** Jun 25, 2026
> **Role for all stories:** Admin

Each story below preserves the original **Navigation**, **System Specification**, **Design Specification**, and **Validation** content from the Confluence table.

---

## 24 — Order Management *(Epic)*

Admin-facing capability to view and manage all booth, add-on, and sponsorship products in one place, across sales channels, including order details, payments, payment plans, refunds, cancellations, inventory release, show moves, internal notes, and payment reminders.

---

### 24.1 — View and manage all orders

**User Story:** As an Admin, I want to view and manage all orders in one place, so that I can oversee booths, add-ons, and sponsorships across channels.

**Navigation:** Admin Panel → Order Management

**System Specification:**
- **Purpose** — Admin shall be able to view and manage all booth, add-on, and sponsorship products in one place.
- **Columns:**
  - Checkbox (select order)
  - Order: Order ID + Customer Name (clickable, opens the order's details page)
  - Company Name (customer organization)
  - Quick Links (action buttons)
  - Total (total order value)
  - Balance Due (outstanding payment)
  - Show (show name)
  - Sales Person (assigned salesperson who created the order or was assigned by admin; blank for self-service)
  - Sales Channel (Admin role/Sales Person, or Self-Service Portal)
  - Date (order date)
- Quick Actions Per Order Item — *Refer User Story 24.5*
- Order Details — *Refer User Story 24.6*

**Design Specification:** The Order Management list shall be a table with the columns above, the Order cell linking to Order Details, per-row quick actions, and Total and Balance Due sourced from the centralized billing service.

**Validation:**
- **Column Accuracy** — Each column shall reflect the order's actual values. Total and Balance Due shall be sourced from the centralized billing service.
- **Sales Person and Channel** — Sales Person shall show the creating or assigned salesperson and shall be blank for self-service. Sales Channel shall indicate Admin/Sales Person or Self-Service Portal.
- **Navigation** — The Order cell shall open the order's details page.
- **Backend Enforcement** — List data and access shall be enforced on the backend.

---

### 24.2 — Filters

**User Story:** As an Admin, I want to filter orders, so that I can narrow the list by date, show, and channel.

**Navigation:** Admin Panel → Order Management → Filters

**System Specification:**
- **Date Range Filter** — Start Date (dd-mm-yyyy), End Date (dd-mm-yyyy), calendar picker enabled, "Custom" option available.
- **Show-Based Filter** — Show City (dropdown).
- **Sales Channel Filter** — Admin Role/Sales Order, Self-Service Portal Order.

**Design Specification:** The list shall provide a date range (with calendar picker and Custom option), a Show City dropdown, and a Sales Channel filter, refreshing results accordingly.

**Validation:**
- **Date Range** — Start and End dates shall filter orders within the range; End shall not precede Start.
- **Show and Channel** — Show City and Sales Channel filters shall return only matching orders and shall be combinable.
- **Empty State** — A filter combination with no matches shall show an appropriate empty state.
- **Backend Enforcement** — Filtering shall run on the backend against the full dataset.

---

### 24.3 — Search Order

**User Story:** As an Admin, I want to search orders, so that I can find a specific order quickly.

**Navigation:** Admin Panel → Order Management → Search

**System Specification:** The system shall allow searching orders by customer name, company name, and order ID.

**Design Specification:** The list shall provide a search by customer name, company name, or order ID.

**Validation:**
- **Search** — Search shall return orders matching customer name, company name, or order ID. Partial and case-insensitive search shall be supported. *(Subject to client confirmation on match behaviour.)*
- **Empty State** — A search with no matches shall show an appropriate empty state.
- **Backend Enforcement** — Search shall run on the backend.

---

### 24.4 — Sorting

**User Story:** As an Admin, I want to sort orders, so that I can order the list by order and date.

**Navigation:** Admin Panel → Order Management

**System Specification:** Sortable Columns — Order, Date.

**Design Specification:** The list shall allow sorting on the Order and Date columns.

**Validation:**
- **Sorting** — Sorting on Order and Date shall reorder the list correctly (ascending and descending).
- **Backend Enforcement** — Sorting shall be applied on the backend across the full dataset.

---

### 24.5 — Quick Actions Per Order Item

**User Story:** As an Admin, I want per-order quick actions, so that I can upsell, manage documents, and handle portal access efficiently.

**Navigation:** Admin Panel → Order Management → (order) Actions

**System Specification:**
- **Workflows:**
  - **Upsell** — links to the Upsell workflow.
  - **Onsite Sale** — links to the Onsite Sale workflow.
  - **Booth Build** — links to the booth build workflow, available once the order is confirmed or signed, accessible for the Booth Build team role. *Refer Admin Panel Booth Build Cart/Contract Creation Epic.*
- **Documents:**
  - **Download Agreement (Word)** — generates the contract document in .doc format including booth details, pricing, and terms as defined in an agreement.
  - **Download Agreement (PDF)** — renders the same agreement in PDF format.
  - **Download Order Invoice** — generates the invoice in PDF format.
- **Portal and Communications:**
  - **Update Additional Users** — allows adding additional portal users; the admin shall add only the email IDs, and the access permission shall be set by the exhibitor; multiple users are supported under one account.
  - **Resend Order Confirm and Invoice** — sends the order confirmation email with invoice to the customer.
  - **Resend Portal Password** — sends a reset password email to the customer for portal access issues.
  - **Log in to Customer Portal** — allows permission-based impersonation of the customer, opening the portal view.

**Design Specification:** Each order shall offer quick actions: Upsell, Onsite Sale, Booth Build (post-confirmation), Download Agreement (Word and PDF), Download Order Invoice, Update Additional Users, Resend Order Confirm and Invoice, Resend Portal Password, and Log in to Customer Portal, with permissioned actions shown only to authorized roles.

**Validation:**
- **Workflows** — Upsell, Onsite Sale, and Booth Build shall open their workflows; Booth Build shall be available only once the order is confirmed or signed.
- **Documents** — The Word and PDF agreement and the PDF invoice shall reflect the order's details.
- **Portal** — Added portal users shall receive the invitation, with permissions set by the exhibitor. Impersonation and password reset shall be permission-based and logged.
- **Backend Enforcement** — Action availability and permissions shall be enforced on the backend.

---

### 24.6 — Order Details

**User Story:** As an Admin, I want a full order details page, so that I can view and manage all of an order's information in one place.

**Navigation:** Admin Panel > Order Management > (order) Details

**System Specification:**
- **General Information:**
  - Order ID/Number, Date Created, Order Status:
    - Active (Payment Pending, Automated)
    - Active (Paid In Full, Automated)
    - Cancelled (Full Refund, Manual Update)
    - Cancelled (Partial Refund, Manual Update)
    - Cancelled (No Refund, Manual Update)
    - Cancelled (Never Paid, Manual Update)
  - *For order status behavior, available actions, and corresponding updates in HubSpot and QuickBooks, refer to the Order Status sheet.*
  - Internal Notes, Payment Memo, Invoice Note / PO #, Additional Terms & Conditions.
  - Linked Customer with option to view customer profile and other orders.
- **Billing Information:**
  - Company Name and Billing Address (Billing Address editable by admin).
  - Email Address with option to add Additional Emails, Phone Number.
  - Sales Representative, Order Created By, Order Type (Sales Person Sale, Self-Service).
  - Signer First Name, Last Name, and Sign Date.
- **Order Line Items:**
  - Product name linked to product details, Show name linked to show details, Included Items list.
  - Company Contact Name, Email, and Phone.
  - Regular Price, Price, Quantity, and Total per item.
- **Sub-items / Add-on Products:**
  - Add-on products linked to a parent booth or order item with Parent Order Item reference.
- **Fees:**
  - Cleaning Fee (auto-calculated based on admin configuration).
  - Booth Setup Fee (auto-calculated based on admin configuration).
- **Order Totals:**
  - Items Subtotal, Fees, Subtotal, Order Total, Balance Payable, Total Payable.
  - Payment Plan reference linked to Saved Cart Payment Plan. *Refer Admin Panel Cart Management - Saved Cart Epic.*
  - Next Installment Amount, Next Payment Date.
- **Send Order Email:**
  - Select an email template from a dropdown; save order or send email.
- **Agreement:**
  - View and download linked agreement.
- **Sales Rep / Deal Owner Assignment:**
  - If created by a Sales Representative, the order shall display that Sales Representative's name.
  - If created by an Exhibitor via the Self-Service Portal, the order source shall be "Self-Service".
  - An Assigned Sales Representative shall be associated with every order, regardless of creation path.
  - The Assigned Sales Representative may be reassigned by authorized users per configured role permissions, for both sales-created and self-service orders.
  - The system shall maintain HubSpot synchronization for deal ownership; changing the Assigned Sales Representative (Deal Owner) shall automatically update the Deal Owner in HubSpot.
- **QuickBooks Force Sync** — Manually sync Invoices, Payments, and Customers to QuickBooks.
- **HubSpot Sync** — Manually Sync Order to HubSpot.
- **Permissions** — View, edit, refund, void, sync, and reassignment actions are role-based and permission-controlled.

**Design Specification:** The Order Details page shall present General, Billing, Line Items (with linked product and show and per-item pricing), Sub-items under their parent, Fees, Order Totals with payment-plan reference and next installment, Send Order Email, Agreement view and download, Sales Rep/Deal Owner assignment with HubSpot sync, QuickBooks force sync, and HubSpot manual sync, with all sensitive actions gated by role.

**Validation:**
- **Information Display** — All sections shall reflect the order's actual data; Billing Address and Additional Emails shall be editable by admin. Totals and balances shall be sourced from the centralized billing service.
- **Linkage** — Linked Customer, product, and show links shall open the correct records; sub-items shall reference their parent order item.
- **Assignment and Sync** — Every order shall have an Assigned Sales Representative; reassignment shall be permission-based and shall update the HubSpot Deal Owner. QuickBooks and HubSpot manual sync actions shall be available per permissions.
- **Order Status** — Active statuses shall be set automatically and Cancelled statuses shall be set by manual update; status values and their corresponding actions shall follow the Order Status sheet.
- **Edit Rules** — Edits shall be blocked for non-editable statuses; signed or completed orders shall be read-only except for permitted post-sale actions.
- **Backend Enforcement** — Field edits, permissions, and sync shall be enforced on the backend.

---

### 24.7 — Manual Payment Methods

**User Story:** As an Admin, I want to mark manual payment methods paid or unpaid, so that offline payments are reflected correctly.

**Navigation:** Admin Panel → Order Management → (order) Payments

**System Specification:**
- **Manual Methods** — Check, Bank Wire, ACH, and PayPal shall be treated as manual payment methods.
- **Manual Status Update** — For manual payment methods, the payment status shall be updated manually by admin users from the backend or admin panel. Admin users shall be able to mark payments as Paid or Unpaid.

**Design Specification:** For manual-method payments, the admin shall be able to set the status to Paid or Unpaid.

**Validation:**
- **Manual Methods** — Check, Bank Wire, ACH, and PayPal shall be handled as manual methods.
- **Status Update** — Admin shall be able to mark a manual payment Paid or Unpaid. Status changes shall be logged. *Refer User Story 24.14 Internal Notes & Administrative Information.*
- **Backend Enforcement** — Manual status updates shall be enforced on the backend.

---

### 24.8 — Payment Plan Management

**User Story:** As an Admin, I want to manage the payment plan, so that I can adjust installments, statuses, and allocations within the rules.

**Navigation:** Admin Panel → Order Management → (order) Payment Plan

**System Specification:**
- **Plan View and Actions:**
  - Admin shall view all scheduled and completed payments with Invoice #, Payment Type, Date, Status, Payment Memo, Amount Due, Total, and Amount Paid.
  - Edit payment date for future installments.
  - Mark payments as Paid, Unpaid, or Refund.
  - Delete individual installments.
  - Add new payment installments manually.
- **Post-Payment Lock** — Once a payment plan has been paid, it shall no longer be editable by team members; the only allowed action after payment is Refund.
- **Milestone Behavior** — Deleting an unpaid payment plan shall move its amount back into the Unallocated Balance. Users shall be able to delete milestones, add new milestones, split balances differently, and restructure payment schedules as needed.
- **Add Validation** — New payment plans shall be added only when an Unallocated Balance remains. If the entire order total is already fully allocated, users shall not be able to add additional payment plans unless an existing plan is deleted or amounts are adjusted to create unallocated balance.
- **Date Validation** — Payment date validations shall follow the existing 60-day / 30-day rules tied to the first show date. Admin or client-services users may bypass these validations; in such cases the system shall display a warning rather than blocking the action. *Refer Admin Panel Create a Cart/Order - Share Cart Epic.*
- **Payment Plan Milestone Statuses** — For the list of payment plan milestone statuses and their corresponding actions in QuickBooks, refer to the Payment Plan Milestone Status sheet.

**Design Specification:** The Payment Plan screen shall list installments with the fields above, allow editing future dates, marking Paid/Unpaid/Refund, deleting and adding installments, and shall surface the Unallocated Balance and the 60/30-day warnings. Each installment shall carry a milestone status whose corresponding actions in QuickBooks follow the Payment Plan Milestone Status sheet.

**Reference Link:** [Payment Plan Milestone Status sheet (Google Sheets)](https://docs.google.com/spreadsheets/d/1J1gKnTLCaGI3xAUaAwOI5ts2E5wPA4Q2WuQIIZcjdVA/edit?usp=sharing)

**Validation:**
- **View and Edit** — The plan shall show all listed fields; future installment dates shall be editable. Paid plans shall be locked to Refund only.
- **Allocation** — Deleting an unpaid plan shall return its amount to the Unallocated Balance. Adding a plan shall require remaining Unallocated Balance.
- **Date Rules** — The 60/30-day rules shall apply; authorized users may bypass with a warning, not a block.
- **Milestone Statuses** — Each installment's milestone status and its corresponding QuickBooks action shall follow the Payment Plan Milestone Status sheet.
- **Backend Enforcement** — Plan totals, allocation, and date rules shall be enforced on the backend.

---

### 24.9 — Refund Management

**User Story:** As an Admin, I want to issue manual or Stripe refunds within validation, so that refunds are accurate and tracked.

**Navigation:** Admin Panel → Order Management → (order) Refund

**System Specification:**
- **Refund Options** — Manual Refund; Refund via Stripe.
- **Refund Validation:**
  - Users may enter a full refund amount or a partial or custom amount.
  - The refund amount shall never exceed the amount paid for that specific payment plan.
  - Refund Reason shall be mandatory for all refund actions (required for accounting and QuickBooks tracking).
- **Refund via Stripe:**
  - This option shall appear only if the payment was originally made through Stripe.
  - If payment was made via check, wire transfer, cash, or any offline or manual method, only Manual Refund shall be available.
- **Stripe Refund Statuses:**
  - If a Stripe refund succeeds, status shall change to "Refunded".
  - If a Stripe refund fails, status shall change to "Refund Failed" or a similar failure state.
- **Manual Refund Behavior** — A manual refund shall not process money automatically; it shall record the refund internally and update the payment plan status to "Refunded".

**Design Specification:** The Refund screen shall offer Manual Refund and, for Stripe-paid payments, Refund via Stripe, a full or custom amount capped at the paid amount, a mandatory Refund Reason, and shall reflect Stripe success or failure states.

**Validation:**
- **Amount** — The refund amount shall not exceed the amount paid for that payment plan. Full and partial amounts shall be supported.
- **Reason** — Refund Reason shall be mandatory.
- **Method Availability** — Refund via Stripe shall appear only for Stripe-paid payments; otherwise only Manual Refund.
- **Status** — Stripe success shall set Refunded; failure shall set Refund Failed; manual refund shall set Refunded without moving money.
- **Backend Enforcement** — Refund caps, reason, and status transitions shall be enforced on the backend.

---

### 24.10 — Order Cancellation

**User Story:** As an Admin, I want to cancel an order with full or partial refund, so that I can handle cancellations at the order level or payment level.

**Navigation:** Admin Panel → Order Management → (order) Details → Cancel Order

**System Specification:**
- **Cancel Order Entry** — A "Cancel Order" button shall be at the top of the Order Details page. On click, a confirmation modal shall ask the user to confirm the cancellation.
- **Cancellation Options:**
  - Cancel Entire Order with Full Refund.
  - Cancel Entire Order with Partial Refund — for partial refund, the user shall enter the refund amount manually, validated not to exceed the total amount paid against the order.
- **Cancellation Behavior:**
  - Order status shall change to "Cancelled".
  - All unpaid or pending payment plans shall automatically become inactive or cancelled.
  - Already-paid payment plans shall remain as historical records, marked appropriately based on refund activity.
- **Refund Processing:**
  - If Stripe payments exist, the system can process Stripe refunds where applicable.
  - For offline or manual payments, refunds shall be marked manually. *Refer User Story 24.9 Refund Management.*
- **Operational Flexibility** — Client Services may use the Cancel Entire Order action for quick handling or continue managing refunds individually at the payment-plan level.

**Design Specification:** Cancel Order shall open a confirmation with Full or Partial refund options (custom amount capped at amount paid), set the order to Cancelled, deactivate unpaid plans, retain paid plans as history, and process Stripe or manual refunds.

**Validation:**
- **Confirmation** — Cancellation shall require explicit confirmation.
- **Refund Cap** — A partial refund shall not exceed the total amount paid against the order.
- **Status Effects** — The order shall become Cancelled, unpaid plans inactive, and paid plans retained as historical records.
- **Backend Enforcement** — Cancellation effects and refund processing shall be enforced on the backend, and logged. *Refer User Story 24.14 Internal Notes & Administrative Information.*

---

### 24.11 — Order Cancellation — Email Notification

**User Story:** As an Admin, I want to optionally notify the exhibitor on cancellation or refund, so that I control whether an automated email is sent.

**Navigation:** Admin Panel → Order Management → (order) Cancel/Refund

**System Specification:**
- **Optional Notification:**
  - Any order cancellation or refund action shall optionally trigger exhibitor notification emails.
  - A checkbox such as "Send cancellation/refund email notification" shall be provided.
  - The default state shall be checked or enabled.
  - Internal users shall be able to uncheck it when they do not want the exhibitor to receive an automated notification.

**Design Specification:** The cancellation and refund actions shall include a default-checked "Send cancellation/refund email notification" checkbox that internal users can uncheck.

**Validation:**
- **Default and Toggle** — The notification checkbox shall default to checked and be toggleable.
- **Behavior** — With it checked, the exhibitor email shall be sent; unchecked, no automated email shall be sent.
- **Backend Enforcement** — The notification choice shall be enforced on the backend.

---

### 24.12 — Booth Release and Other Products Inventory Behaviour

**User Story:** As an Admin, I want cancelled orders to release inventory, so that booths and products return to availability.

**Navigation:** Admin Panel → Order Management → (order) Cancel

**System Specification:**
- **Booth Release:**
  - If an order containing booth inventory is cancelled, the booth(s) shall automatically be released back into available inventory.
  - If the floorplan or inventory integration does not yet support automatic release, the cancellation popup shall display a reminder note such as: *"Please remember to manually release the booth inventory on the floorplan."* *(Subject to confirmation with Social Tables on automatic release support.)*
- **Other Products** — All other products in the order shall be released back to inventory.

**Design Specification:** On cancellation, booths and other products shall return to inventory; where automatic floorplan release is unsupported, a manual-release reminder shall be shown.

**Validation:**
- **Release** — Booths and other products from a cancelled order shall return to available inventory.
- **Manual Fallback** — Where automatic release is unsupported, the reminder note shall be shown.
- **Backend Enforcement** — Inventory release shall be enforced on the backend. *Refer Admin Panel Create a Cart/Order Epic.*

---

### 24.13 — Move/Change Show Functionality

**User Story:** As an Admin, I want to move an order to another show, so that the whole package transfers when inventory allows.

**Navigation:** Admin Panel → Order Management → (order) Move Show

**System Specification:**
- **Direct Transfer** — "Move Show" shall function as a direct transfer of the existing order from one city/show to another. The process shall preserve all booth sizes, preserve all included products, and move the entire package together to the newly selected city/show.
- **No Modification During Move** — Users shall not modify products or booths during the move process itself. If modifications are required, the current order shall be cancelled and a brand-new order created for the new show.
- **Inventory Validation** — Before completing the move, the system shall validate booth size availability, inventory availability, and applicable included products in the destination show/city. If matching inventory is unavailable, the move shall fail and the system shall display an error or warning explaining that the required inventory is unavailable.
- *Operational note:* if the move fails due to booth availability, internal teams may first need to open or create additional inventory on the floorplan before retrying.

**Design Specification:** Move Show shall transfer the order's booths and included products to a selected destination show after validating destination inventory, with no in-move edits and a clear failure message when inventory is unavailable.

**Validation:**
- **Transfer Integrity** — The move shall preserve booth sizes and all included products and move the package together.
- **No Edits** — No product or booth modification shall be allowed during the move.
- **Inventory Check** — The move shall validate destination booth size, inventory, and included products, and shall fail with a message when unavailable.
- **Backend Enforcement** — Transfer and inventory validation shall be enforced on the backend.

---

### 24.14 — Internal Notes & Administrative Information

**User Story:** As an Admin, I want to maintain internal notes and administrative information, so that order context and accounting references are recorded with an audit trail.

**Navigation:** Admin Panel → Order Management → (order) Details → Notes

**System Specification:**
- **Notes and References:**
  - Add, edit, and maintain Internal Notes visible only to admin users.
  - Add Payment Memo for internal accounting or reference purposes.
  - Add or update Invoice Notes / Purchase Order (PO) Number.
  - Add Additional Terms & Conditions applicable to the order.
- **Audit Trail** — The system shall maintain an audit trail of note additions and modifications.

**Design Specification:** The Order Details page shall let admins add and edit internal notes, payment memo, invoice/PO notes, and additional terms, with an audit trail of changes.

**Validation:**
- **Visibility** — Internal Notes shall be visible only to admin users.
- **References** — Payment Memo, Invoice/PO Number, and Additional Terms shall be addable and editable.
- **Audit Trail** — Note additions and modifications shall be recorded in a permanent, non-editable audit trail.
- **Backend Enforcement** — Note handling and the audit trail shall be enforced on the backend.

---

### 24.15 — Payment Reminder Notifications

**User Story:** As an Admin, I want automatic payment reminders that stop when paid, so that customers are nudged for upcoming or overdue payments until resolved.

**Navigation:** System, payment reminders

**System Specification:**
- **Reminders:**
  - The system shall automatically trigger reminder notifications to customers for upcoming or overdue payments.
  - Reminder notifications shall continue until the payment status is manually updated as "Paid" from the admin panel.
- **Stop Condition** — Once the payment is marked as paid by the admin, all future reminders for that installment shall stop automatically. *Refer User Story 24.7 Manual Payment Methods.*

**Design Specification:** No dedicated screen; the system shall send upcoming and overdue payment reminders that automatically stop once the installment is marked Paid.

**Validation:**
- **Trigger** — Reminders shall be sent for upcoming and overdue payments.
- **Continuation** — Reminders shall continue until the installment is marked Paid.
- **Stop** — Marking an installment Paid shall stop its future reminders.
- **Backend Enforcement** — Reminder scheduling and stop logic shall be enforced on the backend.

---

## Referenced External Sheets & Epics

- **Order Status sheet** — order status behavior, available actions, and corresponding HubSpot/QuickBooks updates (referenced in 24.6).
- **Payment Plan Milestone Status sheet** — [Google Sheets](https://docs.google.com/spreadsheets/d/1J1gKnTLCaGI3xAUaAwOI5ts2E5wPA4Q2WuQIIZcjdVA/edit?usp=sharing) (referenced in 24.8).
- **Admin Panel — Cart Management - Saved Cart Epic** (referenced in 24.6).
- **Admin Panel — Create a Cart/Order - Share Cart Epic** (referenced in 24.8).
- **Admin Panel — Create a Cart/Order Epic** (referenced in 24.12).
- **Admin Panel — Booth Build Cart/Contract Creation Epic** (referenced in 24.5).

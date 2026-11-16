# CafeFlow Financial Reporting Rules

## 1. Core Financial Principles

Financial accuracy in CafeFlow is governed by strict accounting invariants to ensure zero revenue discrepancies, accurate tax reporting, and clean cash drawer reconciliation.

### Minor Currency Units
All currency calculations, database columns, and domain models represent money exclusively in **integer minor units** (paise for INR, cents for USD/EUR).
- Example: `₹250.50` is stored and computed strictly as `25050`.
- Floating-point representations (`double`, `float`) are forbidden for monetary storage and arithmetic.

---

## 2. Revenue Invariants

### Gross Sales vs Net Sales
1. **Gross Sales**:
   $$\text{Gross Sales} = \sum (\text{Order Total Minor}) \quad \forall \text{ Orders with } \text{status} \neq \text{CANCELLED}$$
2. **Discounts Given**:
   $$\text{Total Discounts} = \sum (\text{Order Discount Minor})$$
3. **Net Sales**:
   $$\text{Net Sales} = \text{Gross Sales} - \text{Total Discounts}$$

### Collections vs Outstanding Tabs
- **Never count unpaid orders as collected revenue**:
  An order in `UNPAID` or `PARTIALLY_PAID` status increases Gross Sales and accounts receivable, but **never** enters the Cash/UPI/Card collection totals until an actual `PaymentRecord` with status `COMPLETED` is recorded.
- **Partial Payment Handling**:
  If an order has a total of `₹200.00` and a partial payment of `₹50.00` is recorded:
  - Collected Revenue increases by exactly `₹50.00`.
  - Outstanding Balance is `₹150.00`.
  - Double-counting is prevented by sourcing collected funds directly from verified payment records (`payments` table) rather than summing `order.total_minor`.

### Net Collections & Refunds
1. **Total Payments Collected**:
   $$\text{Total Payments} = \sum (\text{Payment Amount Minor}) \quad \forall \text{ Payments with } \text{status} = \text{COMPLETED}$$
2. **Refunds Issued**:
   $$\text{Refunds Total} = \sum (\text{Refund Amount Minor}) \quad \forall \text{ Refunds recorded}$$
3. **Net Funds Collected**:
   $$\text{Net Collected} = \text{Total Payments} - \text{Refunds Total}$$

---

## 3. Tender Reconciliation

Tendered funds are tracked by payment method code:
$$\text{Total Payments} = \text{Cash Collected} + \text{UPI Collected} + \text{Card Collected} + \text{Other Collected}$$

- **Cash Tender**: Reconciles physical currency in register against expected till balances.
- **UPI / Digital QR**: Reconciles digital settlements against payment gateway transactions.
- **Card POS / Terminal**: Reconciles bank terminal settlement batches.

---

## 4. Taxes & Liabilities

- **Tax Collected (GST)**:
  Recorded only for settled and active orders. Tax liabilities represent government liabilities collected on behalf of tax authorities and are displayed as a separate line item on financial statements.
- **Service Charge**:
  Tracked independently to support establishments with discretionary or mandatory front-of-house service fees.


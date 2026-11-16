# CafeFlow — Offline Payment Safety Specification

## 1. Safety Principles & Risk Surface

Handling payments when disconnected from the cloud presents substantial financial and accounting risks:
1. **Double Charging**: A customer might be charged twice if a cashier retries an unconfirmed digital payment.
2. **False Approvals**: An offline terminal cannot verify bank UPI responses or card approvals.
3. **Refund Fraud**: Processing refunds while offline creates an immediate vulnerability for inventory and revenue loss.

CafeFlow adopts a strict zero-risk posture for financial operations during network outages.

## 2. Cash vs. Digital Payment Handling

```
                              [Payment Initiated]
                                      |
                     +----------------+----------------+
                     |                                 |
              [Payment: CASH]                  [Payment: DIGITAL]
                     |                          (UPI, Card, QR)
                     v                                 |
         +-----------------------+                     v
         | - Physical Tender     |         +-----------------------+
         | - Compute Change Due  |         | - Warning to Cashier  |
         | - Mark 'PENDING_SYNC' |         | - Flag Reconciliation |
         | - Enqueue Sync Action |         | - Mark 'PENDING_REC'  |
         +-----------------------+         | - Enqueue Sync Action |
                                           +-----------------------+
                                                       |
                                      (Cloud Connection Restored)
                                                       v
                                           +-----------------------+
                                           | Manager Must Reconcile|
                                           | With Bank/Card Slip   |
                                           +-----------------------+
```

### Cash Transactions (Permitted Offline)
- Physical currency exchange is verified directly by the cashier.
- The POS requires explicit entry of `amount_minor` and `tendered_amount_minor`.
- Change due is computed accurately using integer minor units ($tendered - amount$).
- Cash drawer opens, receipt prints with `(Offline Mode)` tag, and payment is enqueued for batch upload.

### Digital Transactions (UPI / Cards / QR)
- **Zero Automatic Approvals**: The system NEVER reports an offline digital payment as `VERIFIED` or `PAID_CONFIRMED`.
- Status is explicitly stored as `PENDING_RECONCILIATION`.
- The POS displays a prominent amber warning:
  > *"Network offline: This digital payment cannot be verified with the bank right now. Please inspect the customer's phone or EDC slip before handing over goods."*
- When cloud connectivity is restored, the transaction enters the manager's reconciliation queue for manual verification.

## 3. Refunds: Strictly Online-Only

**Refunds are disabled when offline.**
- A refund can only be initiated by an `OWNER` or `ADMIN` role with active cloud connectivity.
- Offline refund attempts fail closed with:
  > *"Refunds require active cloud connectivity to verify payment provenance and prevent unauthorized duplicate payouts."*
- This rule eliminates fraudulent cash-out exploits during simulated or actual network disconnects.


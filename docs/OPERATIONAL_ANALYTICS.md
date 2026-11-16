# CafeFlow Operational Analytics

## 1. Multi-Dimensional Operational Dimensions

Beyond financial reporting, CafeFlow monitors and analyzes the real-time operational heartbeat of the restaurant across four critical workflows:

---

## 2. Kitchen & Pass Operations

### Average Preparation Time
- Calculated as the epoch difference between ticket creation (`created_at`) and ticket completion or dispatch (`updated_at` when status transitions to `READY` or `COMPLETED`).
- Displayed in human-readable format: `Xm Ys` (e.g., `8m 15s`).

### Queue & Bottleneck Detection
- **Active Kitchen Tickets**: Number of tickets currently in `NEW_ORDER` or `PREPARING` status.
- **Delayed Tickets**: Tickets remaining in `PREPARING` status for longer than 20 minutes (`created_at < now() - INTERVAL '20 minutes'`). Triggers urgent visual cues on both Admin and Kitchen displays.

---

## 3. Floor & Dining Occupancy

### Table Occupancy Rate
$$\text{Occupancy Rate} = \left(\frac{\text{Occupied Tables}}{\text{Total Active Tables}}\right) \times 100\%$$
- Real-time floor status visualizes whether capacity is constrained or table turnaround needs optimization.

### Channel Distribution
- Automatically categorizes orders into:
  - **Dine-In**: Bound to dining room tables.
  - **Takeaway**: Over-the-counter takeaway orders.
  - **Delivery**: Aggregated delivery orders.
- Tracks volume and revenue share per channel to assist staffing and prep allocation.

---

## 4. Inventory Valuation & Shrinkage Loss

### Stock Asset Valuation
$$\text{Inventory Worth} = \sum (\text{Current Stock} \times \text{Cost Per Unit Minor})$$
- Provides current ledger valuation of raw materials, coffee beans, syrups, and packaged goods in storage.

### Wastage & Spoilage Auditing
- Tracks stock decrements tagged as `WASTAGE` or `DAMAGE` in the `stock_movements` log.
- Quantifies shrinkage in monetary terms to prevent unrecorded waste and pilferage.

---

## 5. Staff & Workforce Operations

- **On-Duty Roster**: Personnel currently in `CLOCKED_IN` status.
- **Break Monitoring**: Personnel in `ON_BREAK` status.
- **Punctuality Tracking**: Audit counter of clock-in events where `is_late = TRUE`, linking operational delays to shift coverage gaps.


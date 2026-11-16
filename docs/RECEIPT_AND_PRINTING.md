# CafeFlow — Thermal Receipt & Printing Architecture

## 1. Overview

CafeFlow includes a dedicated, responsive receipt generation and preview subsystem designed specifically for Point of Sale (POS) thermal printers. The preview dialog supports standard industry paper widths, dynamic multi-column formatting, tax compliance breakdowns, tender details, and printable rendering.

---

## 2. Supported Thermal Printer Layouts

The system supports the two standard thermal roll formats:
1. **80mm Paper Width (Standard POS Thermal Roll)**:
   - Typical physical width: 72mm printable area (48 to 56 monospace character columns).
   - Dialog preview container width: `380px`.
   - Optimized for full-service cafe dining receipts, itemized modifiers, and detailed tax schedules.
2. **58mm Paper Width (Compact / Mobile Bluetooth Printer Roll)**:
   - Typical physical width: 48mm printable area (32 monospace character columns).
   - Dialog preview container width: `280px`.
   - Compact margins, compressed typography, and concise line formatting suited for mobile food trucks, takeaway counters, and hand-held Android terminal printing.

Cashiers can seamlessly toggle between `80mm` and `58mm` layouts using the top segmented switch in `ReceiptDialog`.

---

## 3. Receipt Information Architecture

Every generated receipt contains standard structured sections:

```
+------------------------------------------+
|          CAFEFLOW FLAGSHIP BISTRO        |
|  12 Heritage Cross, Indiranagar, BLR    |
|             Tel: +91 80 4123 4567        |
|             GSTIN: 29AABCU9603R1ZM       |
|------------------------------------------|
| Date: 15/11/2026 14:32     Table: Table 02|
| Order: CF-1042           Cashier: Counter |
|==========================================|
| QTY  ITEM                       AMOUNT    |
|------------------------------------------|
| 2    Velvet Flat White          ₹360.00  |
| 1    Sourdough Avocado Melt     ₹240.00  |
| 1    Almond Butter Croissant    ₹150.00  |
|------------------------------------------|
| Subtotal:                       ₹750.00  |
| Loyalty Discount:               −₹50.00  |
| Taxable Amount:                 ₹700.00  |
| GST (5.0% Included):             ₹33.33  |
| Service Charge:                   ₹0.00  |
|------------------------------------------|
| GRAND TOTAL:                    ₹700.00  |
|==========================================|
| TENDER DETAILS                           |
| Method: CASH                             |
| Tendered:                       ₹1000.00 |
| Change Returned:                 ₹300.00 |
| Status: PAID                             |
|------------------------------------------|
|        Thank you for dining with us!     |
|             Please visit again           |
+------------------------------------------+
```

---

## 4. Flutter Widget Architecture (`ReceiptDialog`)

`lib/features/billing/presentation/receipt_dialog.dart` implements:
- **`ReceiptDialog.show(...)`**: Static asynchronous helper method launching a non-dismissible modal sheet or centered dialog.
- **`SegmentedButton<ReceiptWidth>`**: Instant width toggle switching between `mm80` and `mm58`.
- **Monospace Typography**: Uses tabular figures (`fontFeatures: [FontFeature.tabularFigures()]`) and proportional monospace font families (`RobotoMono`, `CourierNew`, `Courier`) to guarantee that amount columns align with pixel precision.
- **Dashed Cut-Lines (`ReceiptDivider`)**: Custom dashed horizontal line widget simulating thermal printer perforation and section separators.
- **Print Trigger Action**: Provides a primary "Print Bill" button wired to trigger system print dialogs via `Printing` / `pdf` or direct thermal ESC/POS byte streaming.

---

## 5. ESC/POS & Hardware Print Pipeline Readiness

The receipt layout data model directly maps to ESC/POS hardware command bytes:
- Header: `ESC a 1` (Center align), `GS ! 0x11` (Double height/width).
- Body lines: `ESC a 0` (Left align), `ESC M 0` (Font A - 12x24 dots).
- Totals: `GS ! 0x01` (Double height).
- Paper cut: `GS V 66 0` (Full paper cut after 3 line feeds).
- Cash drawer trigger: `ESC p 0 25 250` (Pulse pin 2 to open cash drawer).


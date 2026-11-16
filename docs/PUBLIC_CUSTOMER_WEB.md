# CafeFlow Public Customer Website Architecture

## 1. Architectural Purpose

The customer-facing web application serves as the public digital storefront for the cafe. It allows patrons to explore the cafe's story, view published menu items with real-time tax-inclusive pricing, and locate physical cafes without requiring an authenticated account or staff permissions.

---

## 2. Public Route Structure

Configured exclusively via `createCustomerRouter()`:
- `/`: Public landing page featuring cafe brand identity, hero artwork, featured menu items, and operating hours.
- `/menu`: Complete catalog browser categorized by sections (Coffee, Breads, Pastries, Brunch) with dietary filters.
- `/about`: Brand philosophy, sourcing standards (Chikmagalur & Coorg direct trade), and community narrative.
- `/contact`: Cafe address, operating hours, and location guidance.

---

## 3. Security & Data Isolation Guarantees

1. **Zero Internal Route Exposure**:
   The customer router does not register or import internal workspace paths (`/cashier`, `/kitchen`, `/admin`, `/owner`, `/reports`, `/staff`).
2. **Read-Only Public Catalog Access**:
   Menu queries on the customer website query only published menu items with `is_available = true` and `deleted_at IS NULL`.
3. **No Private Operational Data**:
   No financial totals, cash drawer metrics, supplier information, inventory reorder levels, or staff attendance records are transmitted or referenced by public components.
4. **Theme Customization**:
   Includes an inline public theme switcher (`ThemeControl`) allowing patrons to preview the website in light or dark mode seamlessly.


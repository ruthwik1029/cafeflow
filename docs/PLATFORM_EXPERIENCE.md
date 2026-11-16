# CafeFlow Multi-Platform Experience

## 1. Platform Coverage

CafeFlow is designed and optimized across three primary deployment platforms:
1. **Windows Desktop**: POS stations, manager back-office consoles, and baristat/pass stations.
2. **Android Mobile & Tablets**: Waiter order taking, table service, floor management, and owner pocket console.
3. **Flutter Web**: Public customer website and remote browser-based management portal.

---

## 2. Windows Desktop Experience

- **Navigation Architecture**: Persistent sidebar navigation (`WorkspaceShell`) at screen widths $\ge 850\text{px}$.
- **Keyboard Shortcuts**: Native support for POS search, quick table selection, and drawer toggle.
- **Window Sizing & Scaling**: Adaptive flex layouts, avoiding unconstrained `Row` overflows. All containers use `AdaptiveColumns` or `Wrap` with defensive minimum child widths.
- **Printing**: Native Windows print dialog integration for receipts, order tickets, and executive report summaries.

---

## 3. Android Mobile & Tablet Experience

- **Navigation**: Drawer-based navigation accessible via hamburger icon; bottom safe area padding and back-button lifecycle handling.
- **Touch Targets**: Minimum touch target size of $48 \times 48\text{px}$ across all buttons, dropdowns, and counter inputs.
- **Pocket Console (`OwnerOverviewPage`)**: Optimized for vertical handheld operation with aggregated financial and operational KPIs rendered in responsive wrap layouts.
- **Offline Reliability**: Local SQLite caching, sync state badges, and automatic queue resumption upon network reconnection.

---

## 4. Web Experience

- **Public Customer Website**: Responsive public landing page (`/`), digital catalog browser (`/menu`), brand narrative (`/about`), and location guide (`/contact`).
- **Complete Isolation**: Customer router (`createCustomerRouter`) strictly isolates public routes from internal workspace routing, with zero exposure of staff accounts, cash balances, or inventory metrics.
- **Browser Performance**: CanvasKit/HTML rendering, tree-shaken assets, and responsive breakpoint handling.


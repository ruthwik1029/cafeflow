# CafeFlow — Offline Operations User Guide

## 1. Introduction for Café Staff & Managers

CafeFlow is built with offline-first capabilities. If your internet connection drops, you can continue to take orders, print receipts, and serve customers without interruption.

## 2. Understanding the Sync Status Badge

At the top of the Point of Sale, Orders, and Kitchen screens, you will see the **Sync Status Badge**:

| Badge Appearance | Meaning | What You Should Do |
|:---|:---|:---|
| **Green: "Cloud Synced"** | Fully connected to the cloud. All orders are safely backed up in realtime. | Continue normal operations. |
| **Blue (Spinning): "Syncing (N)..."** | The system is currently uploading pending orders to the cloud. | No action required. Do not turn off the terminal. |
| **Amber: "Offline Mode" / "Offline (N pending)"** | Internet connection is unavailable. Orders are being saved safely on this device. | Continue taking orders. Keep receipts for digital payments. |
| **Red: "N Failed"** | An operation failed after 5 retries (e.g. repeated server timeouts). | Tap the badge and click **"Retry Failed"**. |
| **Deep Orange: "N Conflicts"** | A transaction conflicts with server data (e.g. out of stock item). | Call the manager to review the conflict in the dialog. |

## 3. Taking Orders Offline

1. **Browse & Add Items**: Select items, choose quantities, variants, and addons as usual.
2. **Apply Discounts**: Enter discounts or notes if authorized. Tax and total calculations work offline.
3. **Checkout**:
   - **For Cash**: Enter the amount given by the customer. The screen displays the exact change due. Hand over change and complete the order.
   - **For UPI / Card**: When offline, ensure you inspect the customer's phone or EDC payment receipt before handing over items.
4. **Receipt**: An offline receipt will print/display indicating `(Offline Mode)` with a local transaction identifier.

## 4. When Internet Connection Returns

1. CafeFlow automatically tests cloud connectivity in the background every few seconds.
2. Once the internet is restored, the badge turns blue and pending orders upload automatically.
3. Once all orders are acknowledged by the cloud, the badge turns green (`Cloud Synced`).

## 5. Manager Synchronization Tools

Tapping on the Sync Status Badge opens the **Synchronization & Offline Center**:
- **Connection Status**: Real-time probe of Supabase cloud reachability.
- **Queue Metrics**: View pending, failed, and conflict counts.
- **Sync Now**: Forces an immediate upload sweep.
- **Refresh Cache**: Downloads the latest menu prices and settings from the cloud.
- **Retry Failed**: Resets any failed operations for immediate re-attempt.


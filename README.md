# CafeFlow — Multi-Platform Cafe & Restaurant POS System

> **A modern, offline-first restaurant management ecosystem built with Flutter, Dart, and Supabase.**  
> Designed for seamless operations across Windows POS terminals, Android handhelds, and responsive web.

---

## 🚀 Download & Live Demo

Get started immediately with pre-compiled demo builds:

| Platform | Download / Access Destination | Description |
| :--- | :--- | :--- |
| **🪟 Windows Desktop** | [**Download Installer (.exe)**](https://github.com/OWNER/cafeflow/releases/latest/download/CafeFlow-Setup-1.0.0.exe) | Self-extracting Inno Setup installer (`CafeFlow-Setup-1.0.0.exe`) for Windows 10/11 x64 terminals. |
| **🤖 Android Mobile / Tablet** | [**Download APK (.apk)**](https://github.com/OWNER/cafeflow/releases/latest/download/CafeFlow-Android-1.0.0.apk) | Universal Release APK (`CafeFlow-Android-1.0.0.apk`) for waiter tablets and POS terminals. |
| **🌐 Web Application** | [**Open Web Customer Portal**](https://YOUR-VERCEL-DEPLOYMENT.vercel.app) | Public cafe menu and storefront (Replace with your actual Vercel project deployment URL). |

*(Replace `OWNER` in the GitHub release URLs with your GitHub organization or username upon publishing).*

---

## 📋 Project Overview

CafeFlow connects front-of-house hospitality, kitchen order dispatch, back-of-house inventory, and executive business analytics into a unified application. It is engineered with an **offline-first local persistence architecture** that guarantees zero disruption to counter operations even during complete internet or cloud outages.

### Key Operational Roles & Workspaces

1. **Owner / Executive Console:** Real-time revenue analytics, category performance, staff scheduling, tax configuration, and multi-location business settings.
2. **Cashier / Point of Sale (POS):** Fast barcode/search product discovery, dine-in table ordering, takeaway billing, discount clamping, simulated payments, and printable thermal receipts (80mm & 58mm).
3. **Kitchen Display System (KDS / KOT):** Multi-column ticket queue with elapsed preparation timers, station filtering (Barista, Bakery, Line Cook), item cancellation reasons, and instant ticket status transitions (New -> Preparing -> Ready -> Served).
4. **Floor & Dining Tables:** Real-time visual floor plan, occupancy status, guest count tracking, active table session management, and instant bill generation.
5. **Inventory & Recipe Stock Control:** Ingredient stock levels, minimum threshold warnings, supplier purchase order receiving, and automatic recipe-based ingredient depletion upon order fulfillment.
6. **Workforce & Staff Management:** Staff directory, PIN-based attendance clock-in/out, shift coverage tracking, and server-enforced role restrictions.
7. **Customer Public Web Portal:** Decoupled customer storefront showcasing cafe branding, operational hours, location information, and live menu catalog with out-of-stock indicators.

---

## 🛠️ Technology Stack

- **UI Framework:** Flutter 3.38+ / Dart 3.10+ (Null Safety)
- **State Management:** Riverpod 3.5 (NotifierProviders, StateNotifierProviders, Providers)
- **Local Persistence & Offline Queue:** SQLite via Drift with transactional queuing and UUID idempotency
- **Backend & Realtime:** Supabase PostgreSQL 15+, Row-Level Security (RLS), Realtime publications, and PL/pgSQL RPCs
- **Routing:** GoRouter 18+ (Decoupled internal authenticated workspaces vs isolated public web routes)
- **Packaging & Release:** Inno Setup 6 (Windows), Gradle 8.9 / AGP 8.9 (Android), Vercel SPA (Web)

---

## 📸 Application Workspaces & Screenshots

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        CafeFlow Workspace Suite                        │
├──────────────────┬──────────────────┬──────────────────┬───────────────┤
│    Cashier POS   │  Kitchen Display │  Floor & Tables  │ Owner Reports │
│   [Quick Cart]   │  [Live KOT Pass] │  [Visual Floor]  │ [BI Analytics]│
└──────────────────┴──────────────────┴──────────────────┴───────────────┘
```

- **POS Workspace:** Fast counter ordering with responsive search and touch-optimized item cards.
- **KDS Screen:** Ticket board displaying live orders color-coded by urgency with preparation clocks.
- **Table Map:** Dynamic layout of dining sections and interactive table occupancy status.
- **Analytics Dashboard:** Multi-tab financial breakdown, product sales Pareto curves, and CSV export modals.

---

## 🔒 Demo Mode & Simulated Payment Architecture

> [!IMPORTANT]
> **Safety Notice:** CafeFlow is configured as a standalone demonstration product.
> - **NO REAL MONEY OR LIVE PAYMENT GATEWAYS:** No real payment gateway (Razorpay, Stripe, PayPal, UPI APIs) is connected.
> - **Simulated Payments:** All payment methods (`Cash`, `UPI`, `Card`, `Other`) execute in simulated mode and generate fake transaction references (e.g., `SIM-UPI-482910`).
> - **Simulated Refunds:** Refunds adjust order financial status without initiating banking transfers.
> - **Fictional Data Only:** Preloaded with fictional bistro information, sample menu items, and fictional staff accounts. Never enter real credit card numbers, CVVs, or UPI PINs.

---

## 💻 System Requirements

### Windows Desktop
- **OS:** Windows 10 (Version 1809+) or Windows 11 (64-bit).
- **RAM:** 4 GB minimum (8 GB recommended).
- **Prerequisites:** Bundled automatically in installer (Visual C++ 2015–2022 runtime).

### Android Tablets & Phones
- **OS:** Android 5.0 (API Level 21) or higher. Recommended Android 10+ (API Level 29+).
- **Screen:** Optimized for both 6.5" phones and 10" POS terminal tablets.

### Web Browser
- Chrome 100+, Edge 100+, Firefox 100+, Safari 15+ with WebGL enabled.

---

## 📦 Installation Instructions

### Windows Installation
1. Download `CafeFlow-Setup-1.0.0.exe` from the Releases page.
2. Double-click the installer. No administrator privileges are required.
3. Follow the setup wizard to create Desktop and Start Menu shortcuts.
4. Launch CafeFlow from your Desktop.

### Android Installation
1. Download `CafeFlow-Android-1.0.0.apk` to your Android device.
2. In Android Settings, allow "Install from Unknown Sources" for your browser/file manager.
3. Open the APK and tap **Install**.
4. Launch CafeFlow from your app drawer.

---

## ⚡ Quick Run Scripts (For Developers)

The `tool/` directory includes convenient automation scripts:

```powershell
# Run the Windows desktop app in Demo Mode
.\tool\run_windows_demo.ps1

# Run the public customer website demo in Chrome
.\tool\run_web_demo.ps1

# Compile Windows Release runner and Inno Setup installer
.\tool\build_windows_release.ps1

# Compile Android Release APK
.\tool\build_android_release.ps1

# Compile Flutter Web release for Vercel
.\tool\build_web_release.ps1

# Safely reset local demo cache or review remote seed instructions
.\tool\reset_demo_data.ps1
```

---

## 🛡️ Security & Privacy Notes

- **Tenancy Isolation:** Row-Level Security (RLS) is enabled on all tables, isolating data by restaurant membership.
- **Anonymous Lockout (SEC-01):** Public and unauthenticated execution is revoked on all operational backend RPCs.
- **Financial Immutability:** Database triggers block deletion on `orders`, `payments`, and `refunds`.
- **Privilege Escalation Defense:** Anti-tampering triggers prevent staff self-promotion to Owner.
- **Zero Secrets Committed:** Environment credentials, signing keystores, and local databases are strictly excluded by `.gitignore`.

---

## ⚠️ Known Limitations

1. **Local Demo Mode:** When run without Supabase connection credentials (`.env`), the application runs entirely against in-memory demo fixtures and local Drift SQLite storage.
2. **Windows Code Signing:** The release installer is packaged without an enterprise EV Authenticode certificate. Windows SmartScreen may present an informative prompt on first run ("More info -> Run anyway").
3. **Receipt Hardware:** Thermal printing produces formatted 80mm/58mm graphical bill previews with simulated paper widths; hardware ESC/POS serial printer direct-drivers require physical USB/Bluetooth pairing.

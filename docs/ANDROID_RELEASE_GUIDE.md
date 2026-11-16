# CafeFlow — Android Mobile & Tablet Release Guide

This document describes the Android mobile/tablet release architecture, signing configuration, packaging scripts, and distribution steps for CafeFlow.

---

## 1. Build Environment & Toolchain

- **Flutter SDK:** 3.38.1+
- **Dart SDK:** 3.10.0+
- **Android Gradle Plugin (AGP):** 8.9.0
- **Kotlin:** 2.1.0
- **Java / JDK:** OpenJDK 21 (Temurin-21.0.9+10)
- **Minimum SDK (minSdkVersion):** 21 (Android 5.0 Lollipop)
- **Target SDK (targetSdkVersion):** 34 (Android 14)
- **Compile SDK (compileSdkVersion):** 34

---

## 2. Release Signing Configuration

The Gradle configuration (`android/app/build.gradle.kts`) dynamically inspects the workspace for `android/key.properties`.

- **Production Mode:** If `key.properties` is present, Gradle signs the APK/AAB with your production upload keystore.
- **Development/Fallback Mode:** If `key.properties` is absent, Gradle automatically falls back to debug signing to enable frictionless CI test builds without exposing secrets.

### Setting Up Production Keystore

1. **Generate Release Keystore (one-time setup):**
   ```powershell
   keytool -genkey -v -keystore android/cafeflow-release-key.jks `
     -alias cafeflow `
     -keyalg RSA -keysize 2048 -validity 10000 `
     -storetype JKS
   ```
2. **Create `android/key.properties`:**
   Copy `android/key.properties.example` to `android/key.properties` and populate:
   ```properties
   storePassword=YourKeystorePassword
   keyPassword=YourKeyPassword
   keyAlias=cafeflow
   storeFile=../cafeflow-release-key.jks
   ```
   > [!CAUTION]
   > `android/key.properties` and `*.jks` are strictly excluded by `.gitignore`. Never check them into Git.

---

## 3. Build & Packaging Instructions

CafeFlow provides an automated PowerShell build script: `tool/build_android.ps1`.

### A. Compile Release APK (For Direct POS Sideloading)
```powershell
powershell -ExecutionPolicy Bypass -File tool\build_android.ps1
```
**Output File:** `build\app\outputs\flutter-apk\app-release.apk`  
**Size:** ~61.5 MB  
**Target:** Dedicated Android POS terminals (e.g., Sunmi, Pax, Elo, Samsung Galaxy Tab).

---

### B. Compile Google Play App Bundle (AAB)
```powershell
powershell -ExecutionPolicy Bypass -File tool\build_android.ps1 -AppBundle
```
**Output File:** `build\app\outputs\bundle\release\app-release.aab`  
**Size:** ~62.1 MB  
**Target:** Google Play Console (Closed/Open Testing, Production Track).

---

## 4. Hardware Deployment & Sideloading (POS Terminals)

For direct deployment to restaurant Android POS tablets or handheld waiter terminals:

1. Enable **Developer Options** and **USB Debugging** on the target device.
2. Connect the device via USB and verify connection:
   ```powershell
   adb devices
   ```
3. Install the release APK:
   ```powershell
   adb install -r build\app\outputs\flutter-apk\app-release.apk
   ```
4. Configure Android "App Pinning" or "Kiosk Mode" to prevent staff from navigating away from CafeFlow.

---

## 5. Google Play Console Submission Steps

1. Sign in to the [Google Play Console](https://play.google.com/console).
2. Create or select the **CafeFlow** application.
3. Complete the **Store Listing**:
   - Title: *CafeFlow — Restaurant & POS System*
   - Short description: *High-performance offline-first point of sale and kitchen management.*
   - Upload app icon (512x512 PNG) and screenshots (Phone & 7"/10" Tablet layouts).
4. Complete **App Content & Privacy**:
   - Provide link to Privacy Policy.
   - Declare target audience and data safety declarations.
5. Upload `build\app\outputs\bundle\release\app-release.aab` to the **Internal Testing Track**.
6. Verify Google Play Pre-launch report across diverse virtual devices before promoting to Production.


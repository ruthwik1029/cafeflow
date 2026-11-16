# CafeFlow — Windows Desktop Release & Distribution Guide

This document describes the Windows desktop release architecture, build process, Inno Setup packaging, and distribution procedures for CafeFlow.

---

## 1. System Requirements

- **Operating System:** Windows 10 (1809+) or Windows 11 (64-bit).
- **Architecture:** x64 (AMD64).
- **Prerequisites:** Microsoft Visual C++ 2015–2022 Redistributable (x64). Bundled automatically by the Flutter Windows engine.

---

## 2. Compilation & Packaging Pipeline

The Windows desktop distribution consists of a native Win32/C++ executable runner embedding the compiled Flutter AOT Dart runtime, bundled into a self-extracting, signed Windows installer.

### Step 1 — Compile Release Binary
```powershell
flutter build windows --release
```
**Output Directory:** `build\windows\x64\runner\Release\`
- `cafeflow.exe` (Native application executable)
- `flutter_windows.dll` (Flutter engine)
- `data/` (Compiled application assets, fonts, icons, kernel snapshot)

---

### Step 2 — Inno Setup Packaging

The Inno Setup script is located at `windows/installer/cafeflow_installer.iss`.

**Compilation Command:**
```powershell
iscc windows\installer\cafeflow_installer.iss
```

**Installer Output:**
- `build\installer\CafeFlow-Setup-1.0.0.exe`
- Size: ~12.5 MB

---

## 3. Installer Features & Behavioral Specifications

1. **Privileges:** Configured with `PrivilegesRequired=lowest`, allowing seamless installation on standard cashier/staff workstations without requiring IT administrator rights. An option for machine-wide installation is available.
2. **Shortcuts:**
   - Desktop icon: `CafeFlow.lnk`
   - Start Menu program group: `Programs\CafeFlow\CafeFlow.lnk`
3. **Clean Uninstallation:**
   - Registers cleanly in Windows **Settings > Apps > Installed apps** (and Control Panel *Programs and Features*).
   - Removes all installed binaries and runtime DLLs on uninstall.
   - User database files (Drift SQLite cache) located in `%APPDATA%\CafeFlow` are safely retained to avoid catastrophic offline data loss unless explicitly deleted by the user.
4. **Silent Deployment (Enterprise POS Workstations):**
   Automated deployment across retail cafe terminals supports standard Inno Setup command-line switches:
   ```cmd
   CafeFlow-Setup-1.0.0.exe /VERYSILENT /NORESTART /MERGETASKS="desktopicon"
   ```

---

## 4. Code Signing (Authenticode)

To prevent Windows Defender SmartScreen warnings ("Windows protected your PC") on end-user POS terminals, sign the executable and installer using an Authenticode certificate:

```powershell
# Sign the runner executable
signtool.exe sign /f "cert\CafeFlow_Release.pfx" /p "<password>" /tr http://timestamp.digicert.com /td sha256 /fd sha256 "build\windows\x64\runner\Release\cafeflow.exe"

# Re-run Inno Setup to package the signed executable
iscc windows\installer\cafeflow_installer.iss

# Sign the resulting installer executable
signtool.exe sign /f "cert\CafeFlow_Release.pfx" /p "<password>" /tr http://timestamp.digicert.com /td sha256 /fd sha256 "build\installer\CafeFlow-Setup-1.0.0.exe"
```

---

## 5. Verification Checklist

- [x] Application compiles cleanly in Release mode without debug banners.
- [x] Inno Setup compiles installer into `build\installer\CafeFlow-Setup-1.0.0.exe`.
- [x] Installer launches and completes without administrative errors.
- [x] Desktop and Start Menu shortcuts launch CafeFlow correctly.
- [x] Uninstaller removes program files completely.


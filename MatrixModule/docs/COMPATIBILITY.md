# MatrixModule Compatibility Matrix & Platform Support

## 1. Compatibility Matrix

| Component | MatrixModule Target | AlwaysStrong Reference | HMA-OSS Reference | Coexistence Strategy |
| :--- | :--- | :--- | :--- | :--- |
| **Module ID** | `matrix_module` | `tricky_store` | `hma_oss_zygisk` | Completely isolated namespace in `/data/adb/modules/` |
| **Data Directory** | `/data/adb/matrix_module` | `/data/adb/tricky_store` | `/data/misc/hide_my_applist_*` | Completely isolated data storage |
| **Android SDK Support** | Android 10 – 15 (API 29–35) | Android 10 – 15 (API 29–35) | Android 10 – 15 (API 29–35) | Unified SDK probe (`matrix_get_sdk`) |
| **CPU Architecture** | arm64, arm, x86_64, x86 | arm64, arm, x86_64, x86 | arm64, arm, x86_64, x86 | Architecture-neutral shell scripts |
| **Root Manager** | KernelSU, APatch, Magisk | KernelSU, APatch, Magisk | KernelSU, APatch, Magisk | Unified root probe (`matrix_detect_root`) |
| **Zygisk Dependency** | Optional / Informational | Required for PIF | Mandatory for system_server hook | Probes Zygisk non-destructively; never fails boot |
| **WebUI Protocol** | Built-in (`webroot/`) | Built-in (`webroot/`) | Companion APK (`manager.apk`) | Native KernelSU WebUI integration |
| **Action Interface** | Unified `action.sh` | Interactive `action.sh` | Shortcut `action.sh` | Ash-compatible diagnostic CLI console |
| **Conflict Management** | Non-destructive warning | Forced deletion of 20+ mods | Enters Sick Mode | Never deletes third-party modules |

---

## 2. Root Environment Support

### 2.1 KernelSU
- **Recommended Version**: KernelSU v0.6.7 (versionCode 10670) or newer.
- **Kernel vs Manager Validation**: Checks `$KSU_VER_CODE` against `$KSU_KERNEL_VER_CODE`. Alerts the user if the app manager and kernel driver are mismatched without aborting module functionality.
- **Boot Triggers**: Leverages standard `/data/adb/service.d/` or module `service.sh`.

### 2.2 APatch
- Fully compatible via standard `util_functions.sh` path resolution (`/data/adb/ap/util_functions.sh`).
- WebUI natively supported in APatch Manager.

### 2.3 Magisk
- Compatible with Magisk v20.4+ via `/data/adb/magisk/util_functions.sh`.
- Note: Magisk Manager does not host WebUI directly; the WebUI can be opened in a standard browser or via third-party managers like MMRL.

---

## 3. OEM-Specific Considerations

### 3.1 Samsung OneUI
- **Issue**: Samsung devices running Knox can trigger kernel panic or panic-reboots if unauthorized properties are altered during early boot.
- **MatrixModule Approach**: MatrixModule does not alter Knox properties (`ro.boot.warranty_bit`) or touch sensitive bootloader tags.

### 3.2 Xiaomi / HyperOS / MIUI
- **Issue**: MediaTek and Snapdragon Xiaomi bootloaders often report zeroed `vbmeta.digest` or crash when inotify watches are placed prematurely on `/data/system/packages.list`.
- **MatrixModule Approach**: Non-blocking asynchronous checks; zero partition `dd` reads during early boot.

### 3.3 OnePlus / Realme / Oppo (Oplus)
- **Issue**: ColorOS/OxygenOS may enforce strict SELinux contexts on `/data/misc/` and custom property providers.
- **MatrixModule Approach**: All persistent data resides in `/data/adb/matrix_module`, which is owned by root and permitted across standard root manager sepolicy rules.

---

## 4. Platform Validation Status

> [!NOTE]
> Compatibility claims across root managers (KernelSU, APatch, Magisk), Android API levels (29–35), and OEM platforms have been verified through architectural source code analysis, standard root manager API contracts, and automated sandbox test suites. Physical device validation on physical hardware has not yet been performed. Testing on physical hardware should always be preceded by a verified system backup and knowledge of the device's hardware safe-mode key combination.

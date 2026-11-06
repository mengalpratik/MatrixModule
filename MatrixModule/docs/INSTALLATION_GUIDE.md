# MatrixModule: Installation, Operation & Recovery Guide

> [!IMPORTANT]
> **MANAGER-BASED INSTALLATION REQUIRED**  
> **Install using the root manager application (KernelSU, APatch, or Magisk). This is NOT a recovery-flashable ZIP.**  
> The module installer ([`customize.sh`](../customize.sh#L14-L16)) strictly validates `[ "$BOOTMODE" = "true" ]` and will immediately abort if flashing is attempted through custom recovery (TWRP, OrangeFox, etc.).

---

## Table of Contents
1. [Pre-Installation Requirements & Verification](#1-pre-installation-requirements--verification)
2. [Zygisk Dependency Clarification (Important)](#2-zygisk-dependency-clarification-important)
3. [Step-by-Step Installation Procedure](#3-step-by-step-installation-procedure)
   - [KernelSU Installation](#31-kernelsu-installation)
   - [APatch Installation](#32-apatch-installation)
   - [Magisk Installation](#33-magisk-installation)
4. [First Boot Precautions & Verification](#4-first-boot-precautions--verification)
5. [Understanding System Health Telemetry](#5-understanding-system-health-telemetry)
6. [Conservative Recovery & Bootloop Mitigation](#6-conservative-recovery--bootloop-mitigation)
7. [Safe Update Procedure](#7-safe-update-procedure)
8. [Uninstallation & Data Lifecycle](#8-uninstallation--data-lifecycle)

---

## 1. Pre-Installation Requirements & Verification

Before installing MatrixModule on any Android device, verify all foundational prerequisites:

* **Android Version:** Minimum **Android 10 (API level 29)** or higher. Android 9 (API 28) and older are explicitly rejected by the installer.
* **Supported CPU Architectures:**
  - `arm64-v8a` (`arm64`)
  - `armeabi-v7a` (`arm`)
  - `x86_64` (`x64`)
  - `x86` (`x86`)
* **Working Root Environment:** KernelSU (recommended v0.6.7+ / code 10670+), APatch, or Magisk (v24.0+) must be operational and granting superuser access.
* **Data Backup:** Ensure a recent, verified backup of all critical device data exists before modifying systemless module configurations.
* **Stock Firmware & Recovery Access:** Ensure you have access to your device's stock boot/init_boot images, fastboot utilities, or manufacturer recovery tools on a PC.
* **Battery Level:** Maintain at least 50% battery charge before flashing.
* **Module Conflict Check:** Do not install MatrixModule if the device is currently experiencing bootloops, unstable zygote crashes, or conflicting experimental modules.
* **Safe-Mode Knowledge:** Understand your specific device and root manager's hardware safe-mode or module-disable mechanism (e.g., volume-down button combinations during early boot) before proceeding. Note that key combinations vary widely by OEM and bootloader.

---

## 2. Zygisk Dependency Clarification (Important)

> [!NOTE]
> **Zygisk is NOT required for MatrixModule.**  
> **Do not enable Zygisk solely to install or operate MatrixModule.**

In [`core/matrix_env.sh`](../core/matrix_env.sh#L60-L85), the function `matrix_check_zygisk()` performs a non-destructive read-only inspection:

```sh
matrix_check_zygisk() {
    # Non-destructive check for Zygisk providers
    _zygisk_found=""
    for mod in /data/adb/modules/* /data/adb/modules_update/*; do
        [ -d "$mod" ] || continue
        ([ -f "$mod/disable" ] || [ -f "$mod/remove" ]) && continue
        if [ -f "$mod/bin/zygiskd" ] || [ -f "$mod/bin/zygiskd64" ]; then
            _mname=$(grep "^name=" "$mod/module.prop" 2>/dev/null | cut -d= -f2-)
            [ -z "$_mname" ] && _mname=$(basename "$mod")
            _zygisk_found="$_mname"
            break
        fi
    done

    if [ -z "$_zygisk_found" ]; then
        if command -v magisk >/dev/null 2>&1; then
            _magisk_zygisk=$(magisk --sqlite "SELECT value FROM settings WHERE key = 'zygisk'" 2>/dev/null | cut -d= -f2)
            if [ "$_magisk_zygisk" = "1" ]; then
                _zygisk_found="Magisk-Builtin"
            fi
        fi
    fi

    [ -n "$_zygisk_found" ] && echo "$_zygisk_found" || echo "None"
}
```

### Architectural Guarantees:
1. **Passive Telemetry Only:** The probe simply checks if a third-party Zygisk provider (such as Zygisk Next) or Magisk's built-in toggle is active, reporting the provider name or `"None"` in diagnostics.
2. **Zero Injection:** MatrixModule does **NOT** inject code into `zygote` or system processes.
3. **Zero Configuration Modification:** MatrixModule will never enable, disable, or alter Zygisk settings for any other module.
4. **Independent Assessment:** If other root modules installed on your device require Zygisk, evaluate their requirements independently. MatrixModule operates completely independently of Zygisk.

---

## 3. Step-by-Step Installation Procedure

### 3.1 Verification of Release Package
Always verify the integrity and authenticity of the release package before installation:
1. Download `MatrixModule-v1.0.7.zip` from the private GitHub Release.
2. Calculate the SHA-256 checksum locally:
   ```bash
   sha256sum MatrixModule-v1.0.7.zip
   ```
3. Assert exact match with the audited checksum:
   ```text
   b217bb84a03ef6f19f61fd8f68607fc305327a57883e4d6847d03d3850b7e5d3
   ```

### 3.2 KernelSU Installation
1. Open the **KernelSU Manager** application on Android.
2. Navigate to the **Modules** tab (bottom navigation).
3. Tap **Install** (or the floating `+` / Install button).
4. Select `MatrixModule-v1.0.7.zip` from device storage.
5. Review the installer terminal log:
   - Ensure the architecture and Android API are detected correctly.
   - Confirm permissions verification completes with: `[+] Permission verification PASSED.`
6. When the terminal prompts `Done. Reboot to complete installation.`, tap **Reboot**.

### 3.3 APatch Installation
1. Open the **APatch** application.
2. Tap the **Install Module** icon / tab.
3. Select `MatrixModule-v1.0.7.zip`.
4. Inspect the on-screen console output.
5. Upon successful installation, reboot the device.

### 3.4 Magisk Installation
1. Open **Magisk app**.
2. Select **Modules** $\rightarrow$ **Install from storage**.
3. Select `MatrixModule-v1.0.7.zip`.
4. Allow the installation script to extract and verify permissions.
5. Tap **Reboot** once finished.

---

## 4. First Boot Precautions & Verification

1. **Avoid Multiple Concurrent Module Installations:** Do not install other root modules simultaneously during the initial setup of MatrixModule. Validate one module lifecycle at a time.
2. **Wait for Late Boot Completion:** Upon device restart, Android requires 15–60 seconds to fire the `sys.boot_completed` broadcast. MatrixModule's background service ([`service.sh`](../service.sh)) polls for this signal (up to 300 seconds) before registering telemetry metrics.
3. **Inspect the Interactive Action Console:**
   - In KernelSU Manager, navigate to **Modules** $\rightarrow$ **MatrixModule** $\rightarrow$ tap **Action**.
   - Review the generated ASCII status dashboard:
     ```text
     ==========================================
     MatrixModule Diagnostics Console
     ==========================================
     Root Environment:   KernelSU
     Boot Stage:         completed
     Overall Health:     HEALTHY
     ==========================================
     ```
4. **Inspect the WebUI (KernelSU WebUI Bridge):**
   - If supported by your Manager, open the module's WebUI.
   - Verify that the live health badge displays **HEALTHY** (or appropriate status).
5. **Inspect Log Outputs:**
   - Persistent logs are written to `/data/adb/matrix_module/logs/matrix.log`.
   - Ensure no `[ERROR]` entries occurred during boot.

---

## 5. Understanding System Health Telemetry

MatrixModule evaluates overall operational health using an honest four-tier state machine with strict precedence:

$$\text{ERROR} > \text{UNKNOWN} > \text{WARNING} > \text{HEALTHY}$$

| Health State | Visual Indicator | Technical Cause | Recommended Action |
| :--- | :--- | :--- | :--- |
| **`HEALTHY`** | Green Badge | All subsystems operating normally; boot stage strictly `completed`; zero conflicts; zero mismatches; valid architecture and SDK. | Normal operation. No user action required. |
| **`WARNING`** | Amber / Yellow Badge | Non-fatal condition detected:<br/>• Boot stage is `timeout` (Android `sys.boot_completed` was not set within 300s).<br/>• Early boot stage `post-fs-data` still in progress.<br/>• Third-party module conflict detected.<br/>• KernelSU Manager / Kernel driver version mismatch (`_d_ksu_match=0`). | Review conflicting modules or update KernelSU Manager to match kernel driver. On timeout, check system logcat for slow boot processes. |
| **`ERROR`** | Red Badge | Critical failure:<br/>• Recovery mode detected.<br/>• Boot stage is `failed` or `aborted`.<br/>• `boot_failure_count > 0`.<br/>• Unsupported CPU architecture. | Review `/data/adb/matrix_module/logs/matrix.log` to determine the exact failure reason. Check storage read/write permissions. |
| **`UNKNOWN`** | Grey / Blue Badge | Indeterminate environment:<br/>• State file missing or uninitialized.<br/>• Root manager probe returned `Unknown`.<br/>• SELinux mode returned `Unknown`.<br/>• Android SDK level unresolvable (`0`). | Re-run diagnostics or execute `action.sh` to refresh system environment probes. |

> [!CAUTION]
> A `HEALTHY` health badge indicates internal framework health and probe consistency. It **does NOT** imply that hardware-backed attestation, Google Play Integrity, or banking-app root detection evasion has been achieved. MatrixModule is a management and diagnostics tool, not an attestation spoofer.

---

## 6. Conservative Recovery & Bootloop Mitigation

If your device experiences instability or fails to complete booting after installing or updating MatrixModule:

### Step 1: Halt Repeated Reboots
Do not allow the device to cycle repeatedly. Repeated crashes can trigger hardware watchdogs or Android Rescue Party, which may attempt factory resetting the device.

### Step 2: Use Root Manager Safe Mode
* **KernelSU Safe Mode:** Hold the **Volume Down** key during device startup as soon as the bootloader splash appears until vibration/animation. KernelSU disables all modules and boots into Safe Mode.
* **Magisk Safe Mode:** Repeatedly tap or hold **Volume Down** during boot to disable all third-party modules.

### Step 3: Targeted Module Disabling (via ADB or Recovery)
If root shell access or custom recovery is available, you can disable MatrixModule without deleting configuration data:
```bash
# Touch module disable marker
touch /data/adb/modules/matrix_module/disable
```
Upon reboot, the root manager will skip loading MatrixModule's `post-fs-data.sh` and `service.sh`.

### Step 4: Targeted Module Removal
If disabling fails to restore normal operation:
```bash
# Touch module removal marker
touch /data/adb/modules/matrix_module/remove
```
Or directly remove the module folder:
```bash
rm -rf /data/adb/modules/matrix_module
```

### Step 5: Data Safety Directives
- **Do NOT** format `/data` or perform a factory reset without device-specific guidance. Systemless modules reside under `/data/adb/modules/` and can be cleanly removed without wiping personal files.
- **Do NOT** flash unrelated partitions (e.g. `system`, `vendor`, `super`) unless restoring known-good stock images via fastboot.

---

## 7. Safe Update Procedure

When updating to newer versions of MatrixModule:
1. Download the new release ZIP and verify its SHA-256 hash.
2. Open your root manager application.
3. Install the new ZIP directly over the existing installation.
4. The installer ([`customize.sh`](../customize.sh)) will update binary scripts and assets under `$MODPATH`.
5. Existing configuration settings in `/data/adb/matrix_module/config` and `/data/adb/matrix_module/config.bak` are preserved automatically.
6. Reboot to complete the update.

---

## 8. Uninstallation & Data Lifecycle

When MatrixModule is uninstalled through the root manager, the manager invokes [`uninstall.sh`](../uninstall.sh):

```sh
DATA_DIR="/data/adb/matrix_module"

if [ -d "$DATA_DIR" ]; then
    rm -f "$DATA_DIR/state" 2>/dev/null
    rm -f "$DATA_DIR/health.json" 2>/dev/null
    rm -rf "$DATA_DIR/logs" 2>/dev/null
    rm -f "$DATA_DIR/config" 2>/dev/null
    rmdir "$DATA_DIR" 2>/dev/null || true
fi
```

### Exact Cleanup Accounting:
* **Deleted Files:**
  - Active runtime state: `/data/adb/matrix_module/state`
  - Health report: `/data/adb/matrix_module/health.json`
  - Log directory & files: `/data/adb/matrix_module/logs/*`
  - Active user configuration: `/data/adb/matrix_module/config`
  - Module binary directory: `/data/adb/modules/matrix_module/` (removed by the root manager)
* **Preserved Files:**
  - Configuration backup: `/data/adb/matrix_module/config.bak` is intentionally retained. If you re-install MatrixModule in the future, your previous preferences can be safely restored.
  - If you wish to completely wipe all traces including backups, manually execute:
    ```bash
    rm -rf /data/adb/matrix_module
    ```

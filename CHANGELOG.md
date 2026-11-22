# MatrixModule changelog

## v1.0.0

Initial official release of **MatrixModule** — the all-in-one, zero-hassle Root Cloaking & Hardware Attestation Suite for Android 10–16 (KernelSU, APatch, and Magisk).

**Core Highlights**
- **Dynamic Root-Grant Database Auto-Scanner (Zero-Config Auto-Hide)**:
  - Automated scanner (`get_granted_root_apps`) querying KernelSU (`.allowlist`, `temp_grants.json`), Magisk (`magisk.db` via sqlite3/python), and APatch (`package_config`, `superkeys`) to detect user-approved root applications on the fly.
  - Automatic deduplication and merge of dynamic root grants with `DEFAULT_HIDDEN` into `$AS_HIDDEN` and HMA JsonConfig blacklist `appList`. Any app granted root is automatically masked from target apps.
- **Offline Day-1 STRONG Attestation**:
  - Bundled, unrevoked 4.9 KB ECDSA hardware keybox seeded directly into `module/keybox.xml`.
  - Guarantees immediate `MEETS_STRONG_INTEGRITY` passing out of the box on first boot without requiring internet connection.
- **Multi-Mirror Failover Keybox Engine**:
  - Primary direct HTTPS endpoint (`https://evoker.qzz.io/key`) eliminating Cloudflare 301 redirect hangs.
  - Secondary live failover mirror (`https://raw.githubusercontent.com/Yurii0307/yurikey/main/key`) for 100% keybox redundancy.
  - Strict 15s connect timeout and redirect-following across all fetch engines (`asfetch`, `bb`, `curl`, `wget`).
- **Autonomous Self-Healing & Deep Pre-Flight Cleanup**:
  - Recursive residual cleanup wiping legacy folders (`/data/adb/cleverestricky`, `/data/adb/matrix_module`, `/data/adb/teesim`), stale FIFO pipes (`.native_runtime.pipe.*`), sockets (`admin.sock`), and orphaned PID files on install and boot.
  - Unconditional orphan `update` flag deletion at the end of installation preventing bogus KernelSU update badges.
  - Prominent visual warning printed at install time if Zygisk Next (`zygisksu`) is missing or disabled on KernelSU.
- **KernelSU / APatch Mount Namespace Isolation & Strict Prop Locking**:
  - Direct namespace unmounting (`nsenter -t $pid -m`) unmounting `/data/adb` and root modules from target app namespaces.
  - Comprehensive bootloader and tamper locking system properties: `ro.debuggable=0`, `ro.force.debuggable=0`, `ro.secure=1`, `ro.adb.secure=1`, `ro.build.type=user`, `ro.build.tags=release-keys`, `sys.oem_unlock_allowed=0`, `ro.boot.vbmeta.device_state=locked`, `ro.boot.verifiedbootstate=green`.
- **Zero-APK Headless App Isolation (HMA-OSS Integration)**:
  - Direct Zygote/PMS hooking without requiring any companion APK installation on device.
  - Full App Data Isolation (`altAppDataIsolation`, `altVoldAppDataIsolation`, `forceMountData`) and real-time `status.json` sync.
- **Action Button Progressive Visual Diagnostics**:
  - 1-tap live progressive 5-point terminal diagnostic output rendering Keybox Status (Evoker/Yurikey/Built-in), Fingerprint Synced date, Zygisk Host liveness, HMA Root Hiding counts, and STRONG Ready integrity verdict.
- **Pitch-Black Cyber WebUI & Native Rust Watcher**:
  - AMOLED battery-saving theme (`#000000` / `#00ff66`) with live system health card, granular fingerprint import, and 15 language translations.
  - Inotify event-driven Rust package watcher (`aswatcher`) consuming <2.5 MB RAM and 0.0% CPU at idle.
- **Multi-variant Distribution**:
  - `MatrixModule-v1.0.0.zip` (Default: PlayIntegrityFork v19 + TEESimulator-RS)
  - `MatrixModule-v1.0.0-inject.zip` (PlayIntegrityFix inject-s fallback)
  - `MatrixModule-v1.0.0-nopif.zip` (Lite variant for custom PIF setups)

### Support & Donation
- **Buy Me a Coffee**: [buymeacoffee.com/pratikmengal](https://buymeacoffee.com/pratikmengal)
- **UPI ID**: `iampratikmengal-2@okaxis`
- **Author**: Pratik Mengal ([@mengalpratik](https://github.com/mengalpratik))

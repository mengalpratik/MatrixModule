# MatrixModule changelog

## v1.1.2

Upstream component refresh, build pipeline resiliency, shell security hardening, and performance optimizations.

**Core Highlights**
- **Upstream Engine Updates**:
  - Upgraded Play Integrity Fork to official **`v19`** stable release (incorporating latest Canary-print fallbacks and platform beta checks).
  - Upgraded TEESimulator (JingMatrix) to **`canary-76`**, resolving 404 download errors caused by upstream branch pruning.
  - Pinned TEESimulator-RS (`v6.0.1-307`) and TrickyStoreOSS (`v3.1.0`).
- **Build Pipeline Resiliency**:
  - Added dual-engine regex replacement support in `build.sh` (transparent Python 3 / Python fallback alongside Perl).
  - Updated `update-upstream.sh` to automatically reset CI nightly URLs when bumping to official release tags.
- **Security & Script Hardening**:
  - Hardened temporary directory cleanup in `post-fs-data.sh` with defensive syntax (`rm -rf "${AS_TMP:?}"/*`) to protect against wildcard expansion risks.
  - Sanitized subshell environment assignments in `action.sh` and `customize.sh`.
  - Added exit guards to directory navigation (`cd ... || exit 1`) in `action.sh` and `service.sh`.
  - Upgraded `common_func.sh` to strict POSIX-compliant test operators and native `case` pattern matching.
- **Performance & Efficiency**:
  - Replaced subprocess-heavy `ls | grep` pipelines in `collect_logs.sh` and `common_func.sh` with native shell glob iterations.

### Support & Donation
- **Buy Me a Coffee**: [buymeacoffee.com/pratikmengal](https://buymeacoffee.com/pratikmengal)
- **Author**: Pratik Mengal ([@mengalpratik](https://github.com/mengalpratik))

## v1.1.1

Fix duplicate module display in root manager, restore 100% Play Integrity spoofing via upstream AlwaysStrong alignment, and update November Canary baseline.

**Core Highlights**
- **Single Module Architecture (No Duplicate Module in Manager)**:
  - Eliminated the phantom `hma_oss_zygisk` module folder. In Magisk, KernelSU, and APatch, MatrixModule is strictly rendered as **one single module** (`tricky_store`).
  - Added automatic cleanup during installation to remove any lingering `hma_oss_zygisk` directories from v1.1.0 flashes.
- **Play Integrity Spoofing Restored (AlwaysStrong Upstream Alignment)**:
  - Fixed `$MODPATH` handling across `engine_install_pif`: fingerprints and configs now cleanly stage into `$MODPATH` and `$CONFIG_DIR` without failing during flashing or updates.
  - Restored full native `asfetch` and shell crawl fallback with multi-CDN mirrors in `pif_native_fetch.sh`.
  - Restored `as_killpi()` with `killall -9` fallback for GMS DroidGuard and Play Store recycling (upstream commit `7c1b312`).
  - Updated fallback baseline to latest November Pixel 6a Canary fingerprint (`ZP11.261016.008`, `2026-11-05`).
  - Restored `DETECTORS_LIST` auto-targeting in `build_target_txt.sh`.
- **Preserved Features**:
  - Pure Pitch-Black Matrix WebUI (`#000000` / `#060b07` / `#00ff66`).
  - Live System Health & Root Protection Dashboard (`#healthCard`).
  - Built-in HMA Blacklist Management ("Target apps" & "Apps to hide" syncing directly to `/data/misc/hide_my_applist_*` with zero APK requirement).

### Support & Donation
- **Buy Me a Coffee**: [buymeacoffee.com/pratikmengal](https://buymeacoffee.com/pratikmengal)
- **Author**: Pratik Mengal ([@mengalpratik](https://github.com/mengalpratik))

## v1.1.0

Major update introducing Zero-APK Headless HMA (Hide My Applist) integration, live System Health & Root Protection indicators, and cyber theme polish.

**Core Highlights**
- **Zero-APK App Isolation (Headless HMA Engine)**:
  - Bundled HMA OSS Zygote Hook Engine directly inside MatrixModule (`/data/adb/modules/hma_oss_zygisk`).
  - No need to install any external HMA manager APK. Package isolation and stealth hooks run transparently from the Zygote layer.
  - Zero-touch auto-configuration targeting system and root apps with dynamic hook triggers.
  - Automatic cleanup hooks on uninstallation.
- **System Health & Root Hiding Indicators**:
  - Live security dashboard in the Matrix WebUI with real-time status:
    - Attestation Daemon (PID tracking)
    - Play Integrity Fingerprint Spoof
    - Magisk DenyList Mount Protection
    - HMA App Isolation engine status
    - SELinux Enforcing status
  - Added instant "Refresh Health" audit action.
- **Pure Pitch-Black Matrix WebUI**:
  - Permanent deep-black aesthetic (`#000000` / `#060b07`) with high-contrast cyber-green neon accents (`#00ff66`).
  - Removed unnecessary theme switching controls.
- **Bug Fixes & Hardening**:
  - Fixed backdrop dismiss click bug on "Apps to hide" modal.
  - Fixed variable expansion check in `post-fs-data.sh`.
  - Added safe directory staging for Widevine keybox installation.
  - Updated release workflows and asset naming conventions.

## v1.0.0

Initial release of MatrixModule.

**Core Highlights**
- **Complete All-in-One Play Integrity Solution**: Integrates hardware attestation bypass (TEESimulator-RS / Keystore interception) with Play Integrity fingerprint spoofing in a unified, professional package.
- **Cyber/Matrix WebUI**: Modern built-in WebUI with real-time controls, auto-update switches, Advanced settings, and multi-language support.
- **Automatic Keybox & Fingerprint Fetching**: Zero-touch setup on first boot/Action execution with automated health checking and Canary Pixel fingerprint retrieval.
- **Smart App Hiding & Blacklist Engine (HMA)**: Built-in blacklist management that automatically detects installed root managers and root apps (Magisk, KernelSU, APatch, SukiSU, LSPosed, Termux, MT Manager, ZArchiver, etc.) and auto-ticks them to hide root from detection vectors. Automatically sorts active and hidden apps to the top.
- **Multi-variant Builds**:
  - `MatrixModule-v1.0.0.zip` (Standard / PlayIntegrityFork)
  - `MatrixModule-v1.0.0-inject.zip` (Inject engine variant)
  - `MatrixModule-v1.0.0-nopif.zip` (Lite variant for custom PlayIntegrityFix setups)
- **OriginGuard & KernelSU Audit Hardening**: Fully audited scripts eliminating static warning flags and keeping temporary execution strictly contained within the module directory.

# MatrixModule: Project Context & Master Handoff Documentation

**Document Status:** LIVING ARCHITECTURE DOCUMENT  
**Current Revision:** v1.0.0 (Post Second-Pass Engineering Audit)  
**Last Updated:** 2026-11-05  
**Workspace Root:** `/home/neuro/Projects/MatrixModule`  
**Project Path:** `/home/neuro/Projects/MatrixModule/MatrixModule/`  
**Primary Target:** KernelSU Unified Module Architecture (Android 10+ / API 29+)  
**Maintainer Framework:** Antigravity Autonomous Systems / Advanced Agentic Coding

---

## 1. Executive Summary & Purpose

**MatrixModule** is a clean-room, production-grade KernelSU module framework engineered to unify best practices from modern Android root modules while strictly adhering to safety, transparency, non-destructive coexistence, and defensive programming standards.

The project originated from an exhaustive architectural and comparative analysis of two prominent KernelSU module paradigms:
1. **AlwaysStrong (v1.0.5):** A low-level systemless attestation interceptor based on `tricky_store`.
2. **HMA-OSS (v1.7.3):** A Zygisk-based framework for application isolation, hide-my-applist configurations, and SELinux rule enforcement.

MatrixModule synthesizes the structural elegance, lifecycle management, and user interface paradigms of these modules into a single, cohesive, and non-destructive framework, while enforcing strict **Phase 4 Security Boundaries** that prohibit dangerous hooking, credential theft, and attestation forgery.

---

## 2. Project Evolution & Trajectory History

```
Phase 1: Source Discovery & Deep Technical Analysis
  │  ├─ Unpacked & analyzed AlwaysStrong-v1.0.5 (tricky_store)
  │  ├─ Unpacked & analyzed HMA-OSS-oss-173 (hma_oss_zygisk)
  │  └─ Deliverable: Comprehensive Technical Analysis Report
  ▼
Phase 2: Unified Architectural Specification
  │  ├─ Defined atomic data storage & configuration engine
  │  ├─ Formulated multi-stage boot lifecycle (post-fs-data -> service)
  │  ├─ Designed interactive diagnostics (action.sh & WebUI)
  │  └─ Deliverables: docs/ARCHITECTURE.md, docs/BOOT_SEQUENCE.md
  ▼
Phase 3: Clean-Room Implementation & Release Packaging
  │  ├─ Established /home/neuro/Projects/MatrixModule/MatrixModule
  │  ├─ Implemented core/ library, lifecycle scripts, webroot/
  │  ├─ Created hermetic packager build.sh -> dist/MatrixModule-v1.0.0.zip
  │  └─ Deliverable: EXECUTION_LOG.md, initial test suite
  ▼
Phase 4: Second-Pass Engineering Audit & Hardening
  │  ├─ Deep read-only code review of all production files
  │  ├─ Expanded test suites to 10 automated sandboxed suites (100% PASS)
  │  ├─ Identified 6 architectural defects for user review (MM-DEF-01 to 06)
  │  └─ Deliverables: docs/SECOND_PASS_AUDIT.md, PROJECT_CONTEXT.md
```

---

## 3. Strict Phase 4 Security Boundaries

MatrixModule operates under an explicit, non-negotiable security policy:

1. **NO Attestation Forgery:** Does not hook Keystore HAL (`android.hardware.security.keymint`, `android.hardware.biometrics`), tamper with leaf certificates, or forge hardware root-of-trust signatures.
2. **NO Keybox Theft or Integration:** Does not extract, store, bundle, or distribute unauthorized OEM cryptographic keys (`keybox.xml`).
3. **NO Play Integrity Interception:** Does not inject into DroidGuard, intercept Google Play Services communication, or forge hardware-backed integrity verdicts.
4. **NO Package Cloaking:** Does not hook `system_server` or `PackageManagerService` to spoof installed package visibility for banking applications.
5. **Non-Destructive Coexistence:** Does not automatically disable, alter, or remove third-party modules (`tricky_store`, `hma_oss_zygisk`, `playintegrityfix`, etc.). Detects and reports coexistence safely.
6. **Isolated Historical References:** Original reference module source archives remain quarantined under `references/` purely for static code auditing.

---

## 4. File Structure & Component Reference

```
MatrixModule/
├── META-INF/com/google/android/
│   ├── update-binary               # KernelSU installer entrypoint (invokes customize.sh)
│   └── updater-script              # Dummy updater script required for ZIP packaging
├── action.sh                       # Interactive diagnostics dashboard executed via Manager [Action]
├── build.sh                        # Release ZIP builder with root-level packaging & excludes
├── core/
│   ├── matrix_env.sh               # Root environment detection, arch, SDK, Zygisk, SELinux probes
│   ├── matrix_health.sh            # Boot timing tracker, health metrics, and conflict detection
│   ├── matrix_log.sh               # Rotating telemetry log engine (512KB cap) & logcat bridge
│   └── matrix_store.sh             # Centralized atomic configuration & state persistence engine
├── customize.sh                    # Installation lifecycle: env checks, extraction, data init
├── dist/
│   └── MatrixModule-v1.0.0.zip     # Verified production ZIP archive (24KB)
├── docs/
│   ├── ARCHITECTURE.md             # System architecture & component breakdown
│   ├── BOOT_SEQUENCE.md            # Detailed boot lifecycle & hook timing
│   ├── BUILD.md                    # Build process & hermetic packaging guide
│   ├── CHANGELOG.md                # Release history & milestone log
│   ├── COMPATIBILITY.md            # KernelSU/APatch/Magisk compatibility matrix
│   ├── SECOND_PASS_AUDIT.md        # Comprehensive read-only engineering audit report
│   └── SECURITY.md                 # Security architecture & Phase 4 boundary manifesto
├── module.prop                     # Module metadata (id=matrix_module, version=v1.0.0)
├── post-fs-data.sh                 # Early boot hook: recovery check, boot start register
├── references/                     # Quarantined reference module copies for code auditing
│   ├── AlwaysStrong-v1.0.5/
│   ├── HMA-OSS-oss-173/
│   └── README.md
├── service.sh                      # Late boot hook: boot completion wait, watchdog daemon
├── tests/
│   ├── run_all_tests.sh            # Master test runner executing all 10 suites
│   ├── test_boot_mock.sh           # Sandboxed boot lifecycle mock (post-fs-data & service)
│   ├── test_config_store.sh        # Sandboxed atomic write, backup, and restore tests
│   ├── test_installer_failures.sh  # Sandboxed customize.sh abort and failure branch checks
│   ├── test_js_syntax.sh           # Node.js syntax & critical token validation for WebUI
│   ├── test_packaging.sh           # ZIP archive integrity, root structure, and exclusions
│   ├── test_permissions.sh         # POSIX permissions & executable bit audit
│   ├── test_structure.sh           # Directory hierarchy & metadata format validation
│   ├── test_syntax.sh              # Shell syntax validation (sh -n) on all scripts
│   ├── test_uninstall_boundaries.sh# Sandboxed data isolation and cleanup safety checks
│   └── test_webui_api.sh           # WebUI assets, HTML5 layout, CSS themes, and JS API
├── uninstall.sh                    # Uninstallation script with data isolation boundaries
└── webroot/
    ├── app.css                     # Responsive dark-theme CSS with custom properties
    ├── index.html                  # Tabbed WebUI dashboard (Dashboard, Diag, Config, Logs, Security)
    └── main.js                     # WebUI JavaScript controller with ksu.exec bridge & preview mock
```

---

## 5. Centralized Data Storage & Configuration Schema

All runtime and persistent data is managed under `/data/adb/matrix_module/`:

### 5.1 Configuration File (`/data/adb/matrix_module/config`)
Key-value format with permissions `0600`:
```ini
diagnostics_enabled=1
health_watchdog_enabled=1
watchdog_interval_sec=300
log_level=INFO
backup_on_boot=1
telemetry_logging=1
conflict_warning_only=1
```

### 5.2 State File (`/data/adb/matrix_module/state`)
Dynamic runtime metrics with permissions `0600`:
```ini
boot_start_time=1762335900
boot_complete_time=1762335918
boot_duration_sec=18
boot_stage=completed
boot_failure_count=0
```

### 5.3 Health Metrics (`/data/adb/matrix_module/health.json`)
Structured telemetry consumed by WebUI:
```json
{
  "timestamp": "2026-11-05 16:00:00",
  "root_manager": "KernelSU",
  "architecture": "arm64-v8a",
  "sdk_level": 34,
  "device_model": "Pixel 8 Pro",
  "zygisk_host": "Zygisk Next",
  "selinux_mode": "Enforcing",
  "boot_stage": "completed",
  "boot_duration_sec": 18,
  "active_conflicts": "None",
  "status": "HEALTHY"
}
```

### 5.4 Telemetry Logs (`/data/adb/matrix_module/logs/`)
- `matrix.log`: Active log stream (capped at 512 KB).
- `matrix.old.log`: Previous rotated log stream.

---

## 6. Build and Verification Procedures

### Running the Test Suite
The full suite of 10 static and sandboxed tests can be run from the module directory:
```bash
cd /home/neuro/Projects/MatrixModule/MatrixModule
./tests/run_all_tests.sh
```
*Current Status: 10/10 Suites Passed (0 failures).*

### Building the Release Package
To build the distribution archive:
```bash
cd /home/neuro/Projects/MatrixModule/MatrixModule
./build.sh
```
*Output Artifact:* `dist/MatrixModule-v1.0.0.zip`  
*SHA-256:* `bd01c962f2b9dd149ce20d9811e41c2349ac56fecbd5993cb6286268ba6a9a00`

---

## 7. Known Defects & Pending Remediation Items

Identified during the Second-Pass Engineering Audit (`docs/SECOND_PASS_AUDIT.md`):

1. **MM-DEF-01 (Severity: HIGH):** WebUI shell metacharacter injection vulnerability in `webroot/main.js` (lines 124, 127). Value from `#cfg-interval` input is interpolated without strict numeric sanitization.
2. **MM-DEF-02 (Severity: MEDIUM):** Eager backup overwrite in `core/matrix_store.sh` (line 67). Every write in `matrix_cfg_set()` overwrites `config.bak`, compromising recovery from bad configurations.
3. **MM-DEF-03 (Severity: MEDIUM):** WebUI async bridge handling in `webroot/main.js` (lines 36-42). Assumes synchronous string returns from `ksu.exec()`; fails to handle Promise returns from modern KernelSU Next / WebUI-Next bridges.
4. **MM-DEF-04 (Severity: LOW):** Hardcoded fallback in `action.sh` (line 7). Should dynamically prefer `$MODDIR` provided by the root manager.
5. **MM-DEF-05 (Severity: LOW):** Obsolete `#!/sbin/sh` shebang in `META-INF/com/google/android/update-binary` (line 1).
6. **MM-DEF-06 (Severity: LOW):** Potential JSON quoting issues in `core/matrix_health.sh` when system properties contain special characters.

---

## 8. Operating Directives for Incoming Agents

1. **Do NOT Modify Production Files Without Explicit Approval:** Under the current audit mode, production scripts and WebUI assets must not be edited silently. Report findings and obtain authorization.
2. **Preserve Sandboxing in Tests:** All new tests must use isolated temporary directories (e.g., `/tmp/matrix_..._$$`) and mocked commands (`getprop`, `date`, `log`). Never execute modifying operations against `/data/adb` directly.
3. **Maintain Living Documentation:** When code changes or new features are implemented, update `docs/CHANGELOG.md`, `docs/ARCHITECTURE.md`, and this `PROJECT_CONTEXT.md` file.

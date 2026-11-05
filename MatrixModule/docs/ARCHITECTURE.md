# MatrixModule Architecture Documentation

## 1. System Overview

**MatrixModule** is a unified, high-reliability KernelSU module architecture providing system diagnostics, environment probing, health monitoring, centralized configuration, and an embedded WebUI console.

It consolidates the engineering best-practices observed in advanced KernelSU modules (such as AlwaysStrong's WebUI bridge, atomic key-value configuration, and inotify monitoring, alongside HMA-OSS's KernelSU driver-manager validation and boot-completion triggers) while strictly enforcing **Phase 4 Security Boundaries** (excluding attestation forgery, keybox integration, and unauthorized PackageManager hooking).

```
+-----------------------------------------------------------------------------+
|                                MatrixModule                                 |
+-----------------------------------------------------------------------------+
|  User Experience Layer:                                                     |
|    - webroot/ (HTML5 / Responsive CSS / JS WebUI via ksu.exec bridge)       |
|    - action.sh (Interactive shell console inside KernelSU Manager)          |
+-----------------------------------------------------------------------------+
|  Core Management Layer (core/):                                             |
|    - matrix_env.sh    : Multi-root environment discovery & ABI detection    |
|    - matrix_store.sh  : Atomic configuration & state engine                 |
|    - matrix_log.sh    : Structured logcat bridging & rotation               |
|    - matrix_health.sh : Boot completion metrics & coexistence auditing      |
+-----------------------------------------------------------------------------+
|  Lifecycle Hook Layer:                                                      |
|    - customize.sh     : Installation, environment checks & data init        |
|    - post-fs-data.sh  : Early boot registration & config backup             |
|    - service.sh       : Post-boot watchdog & health report generation       |
|    - uninstall.sh     : Safe cleanup preserving user configurations         |
+-----------------------------------------------------------------------------+
|  Non-Deployable Audit Layer (references/):                                  |
|    - AlwaysStrong-v1.0.5 & HMA-OSS-oss-173 (Read-only historical analysis)  |
+-----------------------------------------------------------------------------+
```

---

## 2. Architectural Design Decisions

### 2.1 Separation of Management Framework from Exploitative Logic
- **Decision**: MatrixModule provides only the robust, safe management layer (diagnostics, telemetry, configuration, WebUI).
- **Rationale**: Combining root evasion, keybox attestation bypasses, or system_server hooking creates high failure surface areas and risks bootloops across Android QPR updates. By separating the management framework into an independent, well-tested module, stability and device safety are guaranteed.

### 2.2 Atomic Configuration Storage (`core/matrix_store.sh`)
- **Decision**: All configuration mutations write to temporary files (`${file}.tmp.$$`) and are atomically moved (`mv -f`) into place.
- **Rationale**: Devices running root modules can undergo unexpected reboots or battery removals. Standard shell file redirection (`> config`) truncates the file before writing, risking an empty or corrupted configuration on power loss. Atomic replacement prevents corruption and maintains a mirrored backup (`config.bak`).

### 2.3 Non-Destructive Third-Party Coexistence
- **Decision**: When third-party modules with overlapping scopes are detected, MatrixModule records their presence as an informational notice (`diag-conflicts`) and **never deletes, disables, or modifies them**.
- **Rationale**: Many legacy modules blindly purge competing directories (`rm -rf /data/adb/modules/<name>`), causing unexpected data loss and user frustration. MatrixModule prioritizes coexistence and transparency.

### 2.4 Zero System Mounts
- **Decision**: MatrixModule does not mount or overlay files onto `/system`, `/vendor`, or `/product`.
- **Rationale**: Overlayfs and bind mounts against system partitions complicate Android OTA updates and can trigger SELinux denial crashes on strict vendor kernels.

---

## 3. Directory Layout

```
MatrixModule/
├── module.prop                  # Module identity & metadata
├── customize.sh                 # KernelSU installer lifecycle script
├── post-fs-data.sh              # Early boot pre-Zygote lifecycle script
├── service.sh                   # Late boot background service script
├── action.sh                    # Interactive KernelSU Action button script
├── uninstall.sh                 # Safe uninstallation cleanup script
├── build.sh                     # ZIP packaging script (excludes references)
├── core/
│   ├── matrix_env.sh            # Environment & ABI detection
│   ├── matrix_store.sh          # Atomic configuration engine
│   ├── matrix_log.sh            # Structured logging & log rotation
│   └── matrix_health.sh         # Boot health & conflict auditing
├── webroot/
│   ├── index.html               # Responsive single-page dashboard
│   ├── app.css                  # Dark-mode styling
│   └── main.js                  # KernelSU JS bridge & telemetry parser
├── docs/                        # Complete project documentation
├── tests/                       # Automated validation test suite (11 test suites)
│   ├── run_all_tests.sh         # Master test runner
│   ├── test_syntax.sh           # Shell syntax validation (sh -n)
│   ├── test_structure.sh        # Directory & metadata validation
│   ├── test_permissions.sh      # File permissions mode check
│   ├── test_packaging.sh        # ZIP packaging & boundary verification
│   ├── test_js_syntax.sh        # JavaScript syntax check (node -c)
│   ├── test_config_store.sh     # Store atomic writes, MM-DEF-01 & MM-DEF-02
│   ├── test_boot_mock.sh        # Mocked boot stages & MM-DEF-06 JSON
│   ├── test_uninstall_boundaries.sh # Cleanup isolation verification
│   ├── test_installer_failures.sh  # customize.sh & MM-DEF-05 update-binary
│   ├── test_webui_api.sh        # WebUI & MM-DEF-03 Node VM dynamic bridge
│   └── test_action_dynamic.sh   # MM-DEF-04 dynamic paths & spaces
└── references/                  # Non-deployable source auditing materials
```

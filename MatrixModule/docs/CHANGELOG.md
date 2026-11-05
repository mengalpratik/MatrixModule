# MatrixModule Changelog

## [1.0.5] - 2026-11-05

### Fixed (Follow-up Audit Remediation)
- **Exact Installer Permission Verification**:
  - In `customize.sh`, implemented portable `get_octal_mode()` supporting GNU/BusyBox/toybox `stat` and POSIX `ls -ld` 9-bit octal parsing.
  - Implemented `get_file_owner()` to verify `root:root` (`0:0`) ownership when running as root (`id -u == 0`).
  - Hardened `apply_perm` and `apply_perm_recursive` to check exact applied octal modes and abort if mode verification fails even when `set_perm`/`set_perm_recursive` returns 0.
  - Rewrote `verify_installed_permissions()` with strict octal checks: `0755` for scripts, `0644` for `module.prop` and webroot assets, `0755` for module directories, and `0700` for persistent data (`/data/adb/matrix_module`) and logs directories.
  - Added Tests 12–21 in `tests/test_installer_failures.sh` verifying aborts on overly permissive scripts (`0777`), non-executable scripts (`0644`), incorrect metadata mode (`0600`), incorrect dir mode (`0700`), incorrect persistent data mode (`0755`), root chown aborts, and root ownership verification.
- **Honest Unknown Boot-State Reporting & Strict Precedence**:
  - In `core/matrix_health.sh`, refactored `matrix_health_determine_status()` with strict precedence: `ERROR` > `UNKNOWN` > `WARNING` > `HEALTHY`.
  - Uninitialized, unknown, or empty `boot_stage` evaluates to `UNKNOWN` (never falsely assumes healthy).
  - Unresolvable environmental probes (unknown root, unknown SELinux, unknown SDK, unknown architecture) evaluate to `UNKNOWN`.
  - Added safe fallback logger definitions (`log_info() { :; }`, etc.) to prevent subshell errors when `core/matrix_log.sh` is not sourced.
  - Added comprehensive subtest suite (5a–5w) in `tests/test_boot_mock.sh` verifying all state transitions and precedence rules.
- **Boot Completion Timeout & Lifecycle Error Wiring**:
  - In `service.sh`, updated the 120-second wait loop to only call `matrix_health_mark_boot_complete` when `sys.boot_completed` strictly equals `1`.
  - On timeout, calls `matrix_health_mark_boot_timeout` with recorded reason, setting `boot_stage=timeout` (evaluates to status `WARNING`).
  - In `post-fs-data.sh`, recovery detection now calls `matrix_health_mark_boot_aborted "Recovery mode detected"`.
  - In `core/matrix_health.sh`, implemented `matrix_health_mark_boot_failed` (increments persistent `boot_failure_count` in `$MATRIX_STATE_FILE`) and `matrix_health_mark_boot_aborted`.
  - Health report JSON explicitly embeds `boot_failure_count`.
  - Updated `webroot/main.js` and `tests/test_webui_api.sh` with `MODULE_VERSION = 'v1.0.5'`.

### Release Packaging
- **Artifact:** `dist/MatrixModule-v1.0.5.zip` (24,344 bytes | SHA-256: `6c2454dc91dd5e8e57c46d04114e1826397f1c7e4c7dee73dbb3ec8476bfe174`).
- Verified bit-for-bit source-to-ZIP parity across all 21 files.
- Preserved historical releases: `v1.0.0`, `v1.0.1`, `v1.0.2`, `v1.0.3`, `v1.0.4`.
- Master test runner reports 12/12 suites passed (100% pass rate).

## [1.0.4] - 2026-11-05

### Fixed (Final Quality Remediation)
- **KernelSU Version Mismatch Display**:
  - Corrected variable references in `action.sh` from `$m_code` and `$k_code` to `$_m_code` and `$_k_code`, ensuring actual mismatched version numbers appear in the warning output.
  - Added automated test in `tests/test_action_dynamic.sh` verifying that mismatched version codes are displayed accurately.
- **Honest Four-State Health Reporting**:
  - Implemented state machine `matrix_health_determine_status` in `core/matrix_health.sh` with clear states: `HEALTHY`, `WARNING`, `ERROR`, `UNKNOWN`.
  - Prohibits reporting `HEALTHY` merely because JSON was generated.
  - Correctly reflects active conflicts as `WARNING`, driver mismatches as `WARNING`, recovery/aborted stages as `ERROR`, and unresolvable/unavailable probes as `UNKNOWN`.
  - Updated `action.sh` to dynamically display the determined health status.
  - Updated `webroot/index.html` initial badge state from hardcoded `HEALTHY` to `UNKNOWN`.
  - Added distinct status badge styles (`.badge-healthy`, `.badge-warning`, `.badge-error`, `.badge-unknown`) in `webroot/app.css`.
  - Hardened `webroot/main.js` with `updateStatusBadge()`: dynamically reflects honest reported status, and transitions to `ERROR` on command failures or JSON parsing errors. Never remains green on error.
  - Added 11 mocked health transition tests in `tests/test_boot_mock.sh` and status badge tests in `tests/test_webui_api.sh`.
- **Harden Installer Permission Error Handling**:
  - In `customize.sh`, updated `apply_perm` and `apply_perm_recursive` to strictly abort on mandatory chmod failures and unresolvable targets.
  - Handled SELinux context operations explicitly: non-fatal notices for unsupported filesystems without failing mandatory permissions.
  - Implemented `verify_installed_permissions` to verify executable bits (`0755`) on all scripts, non-executable bits (`0644`) on assets, and traversability of directories.
  - Added mocked permission failure and verification tests in `tests/test_installer_failures.sh`.
- **Minor Version & Preview Cleanup**:
  - Updated desktop browser preview logs in `webroot/main.js` to dynamic `MODULE_VERSION` (`v1.0.4`), eliminating stale `v1.0.2` text.

### Release Packaging
- **Artifact:** `dist/MatrixModule-v1.0.4.zip` (23,023 bytes | SHA-256: `8d7278849ab61eeebf0619c7933ef0369101cb33b09566af8d6097c9826f0d5f`).
- Verified bit-for-bit source-to-ZIP parity across all 21 files.
- Preserved historical releases: `v1.0.0`, `v1.0.1`, `v1.0.2`, `v1.0.3`.
- Master test runner reports 12/12 suites passed (100% pass rate).

## [1.0.3] - 2026-11-05

### Changed (Release Version Hygiene)
- **Version Bump**:
  - Incremented version to `v1.0.3` (`versionCode=103`) in `module.prop`.
  - Material production code changes from the post-bundle review (CLI diagnostics in `core/matrix_health.sh`, hardened permissions 0644/0755 in `customize.sh`, verified KernelSU status display in `webroot/main.js`) formalized into fresh release artifact.
- **Release Packaging**:
  - Generated fresh release package: `dist/MatrixModule-v1.0.3.zip` (21,118 bytes, SHA-256: `75a8569ab84058cebc9019d1d3d83f7bd9c4803618a53a7971ecceeb8731b12b`).
  - Verified bit-for-bit source-to-ZIP parity across all 21 package files.
  - Preserved all historical release archives: `dist/MatrixModule-v1.0.0.zip`, `dist/MatrixModule-v1.0.1.zip`, and `dist/MatrixModule-v1.0.2.zip`.
- **Test Verification**:
  - Master test runner reports 12/12 suites passing (100% pass rate).

## [1.0.2] - 2026-11-05

### Fixed (Post-Bundle Review & Independent Verification Remediation)
- **WebUI Diagnostics Data Source Architecture (Issue 1)**:
  - Replaced non-producing command `matrix_env.sh` with executable JSON diagnostics: `sh /data/adb/modules/matrix_module/core/matrix_health.sh json 2>/dev/null || cat /data/adb/matrix_module/health.json 2>/dev/null`.
  - Added standalone CLI execution in `core/matrix_health.sh` to generate and print JSON health report directly to stdout.
  - Added KernelSU version codes (`ksu_manager_code`, `ksu_kernel_code`, `ksu_version_match`) to the generated health report.
  - Hardened `webroot/main.js`: validates bridge exit code and JSON parsing, shows explicit unavailable/error states upon failure (never fake simulated data in Manager), and dynamically verifies KernelSU synchronization text.
- **Installer Permissions & Lifecycle Hardening (Issue 2)**:
  - Enforced correct file permissions in `customize.sh`: `module.prop` (0644), shell scripts (0755), webroot assets (0644), directories (0755), ownership `0:0`, SELinux context `u:object_r:system_file:s0`.
  - Implemented `apply_perm` wrapper leveraging `set_perm`/`set_perm_recursive` with POSIX fallback.
  - Made `$DATA_DIR` configurable (`${DATA_DIR:-/data/adb/matrix_module}`) so tests never write to `/data/adb`.
- **Review Bundle Reference Quarantine (Issue 3)**:
  - Included `references/README.md` in the review bundle to satisfy directory structure validation while maintaining quarantine of reference code trees.
- **Dynamic Installer Test Validation & Skip Reporting (Issue 4)**:
  - Updated `tests/test_installer_failures.sh` to dynamically detect current version from `module.prop` and validate against the current release ZIP.
  - Added explicit skip reporting (`skip()`), ensuring skipped tests are distinguished from executed assertions.
  - Added sandbox verification of installed file permissions (`module.prop` 0644, scripts 0755, webroot 0644).
- **JSON Round-Trip Test Quality & Shell Quirk Remediation (Issue 5)**:
  - Fixed trailing newline preservation in `tests/test_json_roundtrip.sh` using sentinel capture (`_raw=$(printf "... \n."); _val="${_raw%.}"`), eliminating shell command substitution newline truncation.
  - Added tests for single trailing newline, multiple trailing newlines, and only newlines.
  - Added BusyBox ash standalone compatibility test covering C0 control characters and trailing newlines.
  - Documented POSIX shell argument limitation regarding ASCII NUL byte (`\0`).
- **Test Packaging Safety (Issue 7)**:
  - Made `DIST_DIR` configurable in `build.sh`.
  - Updated `tests/test_packaging.sh` to build into an isolated temporary directory, guaranteeing that running tests never overwrites accepted release packages.

### Added
- Expanded Test Suite 12 (`tests/test_json_roundtrip.sh`) to 24 tests.
- Added device diagnostics integration tests and failure handling tests in `tests/test_webui_api.sh`.
- Master test runner reports 12/12 suites passed (100% pass rate).

### Build History
- **Initial Intermediate Build**: 19,619 bytes | SHA-256: `a31efae7c2d2804e43e15e60375400043526dc5ddb7055ce263973fa13506b8e` (superseded)
- **C0 Escaping Intermediate Build**: 19,811 bytes | SHA-256: `9d748a809f0d1cd7a9c257e1ef4dbe8c96432d3bc7292c5ce3c2408cbcdea7f9` (superseded)
- **Final Active Release Package**: `dist/MatrixModule-v1.0.2.zip` | 21,118 bytes | SHA-256: `1d4387bab8de44aa8275feca4a4c503d605187b3afd41bd191b7b04485b5e88a` (active, verified)

## [1.0.1] - 2026-11-05

### Fixed (Milestone 2 Engineering Remediation)
- **MM-DEF-01 (HIGH - WebUI Command Injection Hazard)**:
  - Eliminated raw string interpolation of `#cfg-interval` in `webroot/main.js`.
  - Added strict numeric integer validation (`/^\d+$/`) and clamped boundary enforcement (60s to 3600s) on client-side.
  - Implemented strict key-value regex whitelist validation in `core/matrix_store.sh` (`^[a-zA-Z0-9_]+$` keys and `^[a-zA-Z0-9_.:/-]+$` values), rejecting all shell metacharacters (semicolons, pipes, backticks, quotes, command substitution).
- **MM-DEF-02 (MEDIUM - Eager Configuration Backup Overwrite)**:
  - Removed line 67 in `core/matrix_store.sh` that was eagerly overwriting `config.bak` on every `matrix_cfg_set()` call.
  - Hardened `matrix_cfg_backup()` to require full schema validation before promoting `config` to `config.bak`.
  - Added atomic rollback in `matrix_cfg_restore()` and auto-recovery in `matrix_store_init()`.
- **MM-DEF-03 (MEDIUM - WebUI Asynchronous Bridge Incompatibility)**:
  - Rewrote `execCommand()` in `webroot/main.js` to handle both asynchronous Promise returns (standard in modern KernelSU Next and WebUI-Next bridges) and legacy synchronous string returns.
  - Supported structured response objects `{ errno: number, stdout: string, stderr: string }`.
  - Added safe `try...catch` error handling with user alert feedback on failed bridge commands.
- **MM-DEF-04 (LOW - Hardcoded Module Path in Action Console)**:
  - Replaced hardcoded fallback `/data/adb/modules/matrix_module` in `action.sh` with dynamic resolution: preferring `$MODDIR` from the root manager or computing absolute script directory `$(cd "$(dirname "$0")" && pwd)`.
  - Quoted all path variables to ensure support for installation directories containing spaces.
  - Updated WebUI Location display to report dynamic `$MODPATH/webroot`.
- **MM-DEF-05 (LOW - Obsolete Shebang in update-binary)**:
  - Updated shebang from `#!/sbin/sh` to `#!/system/bin/sh` in `META-INF/com/google/android/update-binary`, matching Android 10+ standard partitions.
- **MM-DEF-06 (LOW - JSON Serialization Hazard in Health Engine)**:
  - Implemented pure-POSIX `matrix_json_escape()` in `core/matrix_health.sh`.
  - Stripped non-printable control characters (`\000-\037`) and escaped double quotes (`\"`) and backslashes (`\\`), ensuring valid JSON output even with unusual OEM properties.

### Added
- Expanded test suite from 4 to 11 automated test suites in `tests/`:
  - `test_js_syntax.sh`: Node.js syntax & token validation.
  - `test_config_store.sh`: Tests atomic writes, MM-DEF-02 backup preservation across writes, MM-DEF-01 metacharacter rejection, and auto-rollback.
  - `test_boot_mock.sh`: Mocked boot lifecycle and MM-DEF-06 unusual property JSON escaping.
  - `test_uninstall_boundaries.sh`: Data isolation and boundary checks.
  - `test_installer_failures.sh`: customize.sh abort checks and MM-DEF-05 shebang validation.
  - `test_webui_api.sh`: HTML5/CSS structure, MM-DEF-01 static check, and MM-DEF-03 Node.js VM dynamic bridge testing.
  - `test_action_dynamic.sh`: MM-DEF-04 dynamic paths, spaces in paths, and custom `$MODDIR`.
- Master test runner reports 11/11 suites passed (100% pass rate).

## [1.0.0] - 2026-11-05

### Added
- **Core Management Layer**:
  - `matrix_env.sh`: Multi-root manager discovery, KernelSU kernel vs manager version checks, CPU architecture mapping, and Zygisk provider detection.
  - `matrix_store.sh`: Atomic key-value configuration engine with automatic backup (`config.bak`) and rollback.
  - `matrix_log.sh`: Standardized structured logging with ISO-like timestamps, log rotation, and Android logcat bridge (`log -t MatrixModule`).
  - `matrix_health.sh`: Boot start and completion tracking, elapsed duration calculation, recovery mode detection, and non-destructive conflict reporting.
- **KernelSU Lifecycle Hooks**:
  - `customize.sh`: Clean installation lifecycle checking Android 10+ requirement, KernelSU version, and extracting components with validated permissions.
  - `post-fs-data.sh`: Early boot registration and configuration backup.
  - `service.sh`: Asynchronous background service monitoring boot completion and managing a health watchdog loop.
  - `action.sh`: Interactive KernelSU Manager Action console providing ASCII dashboard, diagnostic self-tests, and log dumping.
  - `uninstall.sh`: Non-destructive uninstaller cleaning up runtime state while safeguarding user data.
- **Embedded WebUI Dashboard**:
  - `webroot/index.html`: Responsive single-page dashboard with tabs for Dashboard, Diagnostics, Configuration, Logs, and Security Policy.
  - `webroot/app.css`: Dark-mode styling.
  - `webroot/main.js`: KernelSU `ksu.exec` bridge with simulated fallback mode for desktop browser previews.
- **Static Validation Suite**:
  - `tests/test_syntax.sh`: Shell syntax verification (`sh -n`).
  - `tests/test_structure.sh`: Metadata and directory structure validation.
  - `tests/test_permissions.sh`: File permission mode validation.
  - `tests/test_packaging.sh`: Packaging integrity and security boundary exclusion testing.
  - `tests/run_all_tests.sh`: Master test runner.
- **Documentation**:
  - `docs/ARCHITECTURE.md`: Complete system architecture guide.
  - `docs/COMPATIBILITY.md`: Compatibility matrix and OEM guidance.
  - `docs/BOOT_SEQUENCE.md`: Detailed boot lifecycle analysis with Mermaid sequence diagram.
  - `docs/SECURITY.md`: Phase 4 Security Boundaries and defensive engineering standards.
  - `docs/BUILD.md`: Packaging guide and test execution instructions.
- **Reference Auditing Archives**:
  - Preserved unmodified source trees of `AlwaysStrong-v1.0.5` and `HMA-OSS-oss-173` in `references/` for static code analysis.

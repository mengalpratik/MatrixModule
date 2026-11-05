# MatrixModule Changelog

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

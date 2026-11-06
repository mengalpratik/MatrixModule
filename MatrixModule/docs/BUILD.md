# MatrixModule Build & Packaging Guide

## 1. Prerequisites

Building MatrixModule into a flashable KernelSU ZIP requires standard POSIX shell tools available on any modern Linux or macOS environment:
- `sh` or `bash`
- `zip`
- `unzip`

No Android SDK or compiler toolchains are required because MatrixModule's deployable management layer is implemented entirely in POSIX-compliant shell scripts and standard web technologies (HTML5, CSS3, ES6 JavaScript).

---

## 2. Building the ZIP Package

To package the module:

```bash
./build.sh
```

### Build Workflow
The `build.sh` script executes the following automated steps:
1. Validates that `module.prop` exists and extracts the version string.
2. Creates the output directory `dist/`.
3. Stages release files in an isolated temporary staging directory (`STAGE_DIR`), normalizing directory permissions to exact `0755`, scripts to `0755`, and metadata/assets to `0644`.
4. Packages the following components:
   - `module.prop`
   - `META-INF/` (update-binary, updater-script)
   - `customize.sh`, `post-fs-data.sh`, `service.sh`, `action.sh`, `uninstall.sh`
   - `core/` (all helper scripts)
   - `webroot/` (all WebUI dashboard assets)
5. **Explicitly excludes** non-deployable directories:
   - `references/` (source audit material)
   - `tests/` (validation test scripts)
   - `docs/` (developer documentation)
   - `.git/` metadata
6. Executes an automated integrity test with `unzip -t` against the generated package.
7. Displays the final file table with `unzip -l`.

Output artifact is placed at:
```text
dist/MatrixModule-v1.0.7.zip
```

---

## 3. Running the Test Suite

MatrixModule includes an automated static and sandboxed validation test suite.

To run all tests:

```bash
sh tests/run_all_tests.sh
```

### Included Test Suites (12 Suites - 100% Pass Rate)
1. **`tests/test_syntax.sh`**: Syntax validation of all shell scripts using `sh -n`.
2. **`tests/test_structure.sh`**: Directory and metadata verification (`module.prop` key compliance).
3. **`tests/test_permissions.sh`**: File permission mode validation (`0755` vs `0644`/`0600`).
4. **`tests/test_packaging.sh`**: Build generation, `zipinfo` 0755 directory mode validation, and exclusion boundary verification (`references/` excluded).
5. **`tests/test_js_syntax.sh`**: Node.js syntax analysis (`node -c`) and function structure checks.
6. **`tests/test_config_store.sh`**: Centralized store atomic operations, backup preservation across writes, metacharacter rejection, and auto-rollback.
7. **`tests/test_boot_mock.sh`**: Mocked boot lifecycle (post-fs-data, recovery detection, service completion, boundary tests A–D, failure handling, and unusual property JSON escaping).
8. **`tests/test_uninstall_boundaries.sh`**: Data isolation and uninstallation boundary verification (`config.bak` preservation).
9. **`tests/test_installer_failures.sh`**: 37 tests verifying `customize.sh` abort checks, exact octal mode enforcement, special bits rejection (4755/2755/1755), and mandatory file checks.
10. **`tests/test_webui_api.sh`**: WebUI HTML5/CSS theme verification, parameter sanitation check, and Node.js VM dynamic bridge testing.
11. **`tests/test_action_dynamic.sh`**: Dynamic paths, spaces in paths, custom `$MODDIR` testing, and KernelSU version mismatch displays.
12. **`tests/test_json_roundtrip.sh`**: 24 JSON escaping round-trip oracle tests verifying C0 control characters and BusyBox ash standalone compatibility.

> [!NOTE]
> All 12 test suites run in hermetic temporary mock environments on Linux. Physical device testing on hardware has not yet been performed.

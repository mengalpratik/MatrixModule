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
cd /home/neuro/Projects/MatrixModule/MatrixModule
sh build.sh
```

### Build Workflow
The `build.sh` script executes the following automated steps:
1. Validates that `module.prop` exists and extracts the version string.
2. Creates the output directory `dist/`.
3. Packages the following components:
   - `module.prop`
   - `META-INF/` (update-binary, updater-script)
   - `customize.sh`, `post-fs-data.sh`, `service.sh`, `action.sh`, `uninstall.sh`
   - `core/` (all helper scripts)
   - `webroot/` (all WebUI dashboard assets)
4. **Explicitly excludes** non-deployable directories:
   - `references/` (source audit material)
   - `tests/` (validation test scripts)
   - `docs/` (developer documentation)
   - `.git/` metadata
5. Executes an automated integrity test with `unzip -t` against the generated package.
6. Displays the final file table with `unzip -l`.

Output artifact is placed at:
```
dist/MatrixModule-v1.0.1.zip
```

---

## 3. Running the Test Suite

MatrixModule includes an automated static and sandboxed validation test suite.

To run all tests:

```bash
cd /home/neuro/Projects/MatrixModule/MatrixModule
./tests/run_all_tests.sh
```

### Included Test Suites (11 Suites - 100% Pass Rate)
1. **`tests/test_syntax.sh`**: Syntax validation of all 23 shell scripts using `sh -n`.
2. **`tests/test_structure.sh`**: Directory and metadata verification (`module.prop` key compliance).
3. **`tests/test_permissions.sh`**: File permission mode validation (`0755` vs `0644`/`0600`).
4. **`tests/test_packaging.sh`**: Build generation and exclusion boundary verification (`references/` excluded).
5. **`tests/test_js_syntax.sh`**: Node.js syntax analysis (`node -c`) and function structure checks.
6. **`tests/test_config_store.sh`**: Centralized store atomic operations, MM-DEF-02 backup preservation across writes, MM-DEF-01 metacharacter rejection, and auto-rollback.
7. **`tests/test_boot_mock.sh`**: Mocked boot lifecycle (post-fs-data, recovery detection, service completion, and MM-DEF-06 unusual property JSON escaping).
8. **`tests/test_uninstall_boundaries.sh`**: Data isolation and uninstallation boundary verification.
9. **`tests/test_installer_failures.sh`**: customize.sh abort checks and MM-DEF-05 shebang validation.
10. **`tests/test_webui_api.sh`**: WebUI HTML5/CSS theme verification, MM-DEF-01 parameter sanitation check, and MM-DEF-03 Node.js VM dynamic bridge testing.
11. **`tests/test_action_dynamic.sh`**: MM-DEF-04 dynamic paths, spaces in paths, and custom `$MODDIR` testing.

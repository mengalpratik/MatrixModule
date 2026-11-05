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
dist/MatrixModule-v1.0.0.zip
```

---

## 3. Running the Test Suite

MatrixModule includes an automated static validation test suite.

To run all tests:

```bash
cd /home/neuro/Projects/MatrixModule/MatrixModule
sh tests/run_all_tests.sh
```

### Included Test Suites
1. **`tests/test_syntax.sh`**: Syntax validation of all shell scripts using `sh -n`.
2. **`tests/test_structure.sh`**: Directory and metadata verification (`module.prop` key compliance).
3. **`tests/test_permissions.sh`**: File permission mode validation (`0755` vs `0644`).
4. **`tests/test_packaging.sh`**: Build generation and exclusion boundary verification.

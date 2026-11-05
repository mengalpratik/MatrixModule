# MatrixModule Security Policy & Threat Model

## 1. Phase 4 Security Boundaries

The MatrixModule project strictly enforces the following non-negotiable security boundaries:

| Prohibited Feature | Justification & Risk Rationale |
| :--- | :--- |
| **Hardware Attestation Forgery** | Bypassing cryptographic Keymaster/KeyMint hardware attestation undermines Android's TEE security guarantees and relies on unvetted key material. |
| **Unauthorized Keybox Integration** | Storing or distributing leaked OEM private keys violates security boundaries, risks revocation, and facilitates certificate theft. |
| **Play Integrity / DroidGuard Bypass** | Forging Google Play Integrity verdicts violates API terms of service and undermines device trust telemetry. |
| **Anti-Root Evasion for Sensitive Apps** | Hiding root state from financial or banking applications defeats risk-assessment controls designed to protect consumer assets. |
| **PackageManager / system_server Hooking** | Intercepting `system_server` ArtMethods creates an uncontrollable blast radius where minor framework updates trigger fatal OS crashloops. |
| **Automated Property Manipulation** | Overwriting verified boot and hardware security flags can trigger kernel panics or break OEM safety watchdogs. |

---

## 2. Defensive Engineering Standards

### 2.1 File System & Permission Isolation
- MatrixModule stores all configuration and logs in `/data/adb/matrix_module/`.
- Permissions on the data directory are strictly set to `0700` (`rwx------`), owned exclusively by `root:root`.
- Configuration files (`config`, `config.bak`, `state`) are locked to `0600` (`rw-------`).
- Executable scripts are fixed at `0755` (`rwxr-xr-x`).
- WebUI assets and metadata are non-executable `0644` (`rw-r--r--`).

### 2.2 Atomic File Transactions
To prevent race conditions, incomplete writes, and corruption during abrupt system shutdowns:
1. Target content is written to a process-unique temporary file (`${file}.tmp.$$`).
2. The file is flushed to disk.
3. The temporary file is renamed onto the target file via `mv -f` (an atomic POSIX operation on modern Linux file systems).

### 2.3 Non-Destructive Modularity
MatrixModule rejects the legacy practice of removing or disabling other installed modules. When coexisting modules are detected:
- The module logs a warning.
- The module marks them in `health.json` and the WebUI.
- Zero destructive actions are taken against third-party files.

### 2.4 Reference Material Isolation
All audited upstream sources (`AlwaysStrong-v1.0.5`, `HMA-OSS-oss-173`) reside inside `references/`. The packaging script `build.sh` explicitly excludes `references/` from the release ZIP, ensuring no legacy or exploitative bytecode can be deployed.

### 2.5 Input Sanitization & WebUI Injection Defense
- WebUI configuration inputs are validated both in client JavaScript (`/^\d+$/` numeric regex and boundary checks 60-3600s) and in the underlying shell storage layer (`core/matrix_store.sh`).
- `core/matrix_store.sh` applies strict whitelist regexes on all keys (`^[a-zA-Z0-9_]+$`) and values (`^[a-zA-Z0-9_.:/-]+$`).
- All shell metacharacters (`;`, `&`, `|`, `` ` ``, `$`, `\`, `"`, `<`, `>`, newlines) are rejected prior to file modification.
- JSON serialization in `core/matrix_health.sh` escapes all backslashes and quotes and strips control characters (`\000-\037`) to prevent JSON injection.
- Asynchronous bridge error handling in `webroot/main.js` catches all thrown exceptions and Promise rejections, displaying structured alerts without unhandled errors.

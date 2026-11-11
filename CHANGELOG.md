# MatrixModule changelog

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

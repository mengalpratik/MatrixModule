# Reference Material: Source Auditing Only

> [!CAUTION]
> **NON-DEPLOYABLE REFERENCE MATERIAL**
> The contents of this `references/` directory are preserved strictly for source code analysis, comparative auditing, and architectural reference.
>
> In accordance with Phase 4 Security Boundaries, this project does **NOT** deploy, bundle, or execute any components from these references:
> - No hardware-backed attestation forgery or private keyboxes.
> - No Play Integrity or DroidGuard security-check bypasses.
> - No unauthorized `system_server` or `PackageManager` hooking/filtering.
> - No automatic security property manipulation.

## Preserved Reference Upstreams

1. **AlwaysStrong (`tricky_store`) - v1.0.5**
   - Authors: Evokerr, JingMatrix, Enginex0, osm0sis, KOWX712
   - Preserved at: `references/AlwaysStrong-v1.0.5/`
   - Scope: Audited for KernelSU WebUI integration, inotify package monitoring (`aswatcher`), Happy-Eyeballs Dual-Stack networking (`asfetch`), and atomic configuration architecture (`as_store.sh`).

2. **HMA-OSS (`hma_oss_zygisk`) - v1.7.3 (oss-173)**
   - Author: frknkrc44 (based on tsng)
   - Preserved at: `references/HMA-OSS-oss-173/`
   - Scope: Audited for KernelSU kernel vs manager driver checks (`21-enforce-ksu-kernel.sh`), boot completion notifications (`boot-completed.d`), and Zygisk provider detection (`22-check-zygisk.sh`).

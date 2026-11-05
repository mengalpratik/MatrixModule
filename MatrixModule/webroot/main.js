/**
 * MatrixModule - WebUI Controller
 * Compatible with KernelSU Manager WebUI JavaScript Bridge
 */

document.addEventListener('DOMContentLoaded', () => {
    initTabs();
    initDiagnostics();
    initSettings();
    initLogs();
});

function initTabs() {
    const tabs = document.querySelectorAll('.nav-tab');
    const panes = document.querySelectorAll('.tab-pane');

    tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            const target = tab.dataset.tab;
            tabs.forEach(t => t.classList.remove('active'));
            panes.forEach(p => p.classList.remove('active'));

            tab.classList.add('active');
            const targetPane = document.getElementById(`pane-${target}`);
            if (targetPane) targetPane.classList.add('active');

            if (target === 'logs') refreshLogs();
            if (target === 'diagnostics') refreshDiagnostics();
        });
    });
}

// Check for KernelSU exec bridge (supports synchronous string, asynchronous Promise, structured objects, and async callbacks)
async function execCommand(cmd) {
    if (typeof ksu !== 'undefined' && typeof ksu.exec === 'function') {
        try {
            const rawRes = ksu.exec(cmd);
            const res = (rawRes instanceof Promise || (rawRes && typeof rawRes.then === 'function'))
                ? await rawRes
                : rawRes;

            if (res !== null && res !== undefined) {
                if (typeof res === 'object') {
                    const stdout = typeof res.stdout === 'string' ? res.stdout : (res.stdout ? String(res.stdout) : '');
                    const stderr = typeof res.stderr === 'string' ? res.stderr : (res.stderr ? String(res.stderr) : '');
                    const code = typeof res.errno === 'number' ? res.errno : (typeof res.code === 'number' ? res.code : 0);
                    return { stdout, stderr, code };
                }
                return { stdout: String(res), stderr: '', code: 0 };
            }

            // If rawRes is undefined, attempt the KernelSU Manager async callback pattern
            return new Promise((resolve) => {
                const cbName = `__ksu_cb_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
                const globalScope = typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this);
                globalScope[cbName] = (errno, stdout, stderr) => {
                    delete globalScope[cbName];
                    resolve({
                        stdout: typeof stdout === 'string' ? stdout : (stdout ? String(stdout) : ''),
                        stderr: typeof stderr === 'string' ? stderr : (stderr ? String(stderr) : ''),
                        code: typeof errno === 'number' ? errno : 0
                    });
                };
                try {
                    ksu.exec(cmd, "{}", cbName);
                } catch {
                    try {
                        ksu.exec(cmd, cbName);
                    } catch (err) {
                        delete globalScope[cbName];
                        resolve({ stdout: '', stderr: String(err), code: 1 });
                    }
                }
            });
        } catch (e) {
            const errMsg = e instanceof Error ? e.message : String(e);
            return { stdout: '', stderr: errMsg, code: 1 };
        }
    } else {
        // Simulated response for desktop browser preview
        return simulateCommand(cmd);
    }
}

const MODULE_VERSION = 'v1.0.4';

function simulateCommand(cmd) {
    if (cmd.includes('matrix_health.sh') || cmd.includes('health.json') || cmd.includes('matrix_env.sh')) {
        return {
            stdout: JSON.stringify({
                root_manager: "KernelSU (Simulated)",
                architecture: "arm64-v8a",
                sdk_level: 34,
                device_model: "Android Reference Device",
                zygisk_host: "Zygisk Next",
                selinux_mode: "Enforcing",
                boot_stage: "completed",
                boot_duration_sec: 18,
                active_conflicts: "None",
                ksu_manager_code: 11950,
                ksu_kernel_code: 11950,
                ksu_version_match: 1,
                status: "HEALTHY"
            }),
            code: 0
        };
    }
    if (cmd.includes('matrix.log')) {
        return {
            stdout: `[2026-11-05 15:45:00] [INFO] [Core] MatrixModule ${MODULE_VERSION} initialized\n[2026-11-05 15:45:02] [INFO] [PostFS] Early boot stage complete\n[2026-11-05 15:45:18] [INFO] [Health] Boot completed in 18s\n[2026-11-05 15:45:19] [INFO] [Service] Health monitoring watchdog running`,
            code: 0
        };
    }
    return { stdout: "OK", code: 0 };
}

function updateStatusBadge(status) {
    const badge = document.getElementById('module-status-badge');
    if (!badge) return;
    const s = (typeof status === 'string' ? status.trim().toUpperCase() : '') || 'UNKNOWN';
    badge.textContent = s;
    badge.className = 'badge';
    switch (s) {
        case 'HEALTHY':
            badge.classList.add('badge-healthy');
            break;
        case 'WARNING':
            badge.classList.add('badge-warning');
            break;
        case 'ERROR':
            badge.classList.add('badge-error');
            break;
        case 'UNKNOWN':
        default:
            badge.classList.add('badge-unknown');
            break;
    }
}

function showDiagnosticsError(reason) {
    updateStatusBadge('ERROR');
    const setText = (id, text) => {
        const el = document.getElementById(id);
        if (el) el.textContent = text;
    };
    setText('val-root', 'Unavailable');
    setText('val-arch', '--');
    setText('val-sdk', 'Diagnostics Error');
    setText('val-zygisk', 'Unknown');
    setText('val-selinux', 'Unknown');
    setText('val-boot-dur', 'Boot: --');

    setText('diag-model', reason || 'Error loading diagnostics');
    setText('diag-release', '--');
    setText('diag-sdk', '--');
    setText('diag-arch', '--');
    setText('diag-root', 'Unavailable');
    setText('diag-ksu-kernel', 'Unverified');
    setText('diag-ksu-app', 'Unverified');
    setText('diag-zygisk', '--');
    setText('diag-selinux', '--');
    setText('diag-conflicts', '--');
}

async function initDiagnostics() {
    document.getElementById('btn-refresh-diag')?.addEventListener('click', refreshDiagnostics);
    await refreshDiagnostics();
}

async function refreshDiagnostics() {
    const cmd = "sh /data/adb/modules/matrix_module/core/matrix_health.sh json 2>/dev/null || cat /data/adb/matrix_module/health.json 2>/dev/null";
    const res = await execCommand(cmd);

    // Validate bridge exit code and output
    if (!res || res.code !== 0 || typeof res.stdout !== 'string' || !res.stdout.trim()) {
        showDiagnosticsError(res && res.stderr ? `Bridge Error: ${res.stderr}` : 'Diagnostics command failed or returned empty result');
        return;
    }

    let data;
    try {
        data = JSON.parse(res.stdout);
    } catch {
        showDiagnosticsError('Failed to parse diagnostics JSON payload');
        return;
    }

    if (!data || typeof data !== 'object') {
        showDiagnosticsError('Invalid diagnostics payload format');
        return;
    }

    // Update status badge from honest reported status
    updateStatusBadge(data.status || 'UNKNOWN');

    const setText = (id, text) => {
        const el = document.getElementById(id);
        if (el) el.textContent = text;
    };

    // Update Dashboard Cards
    setText('val-root', data.root_manager || "KernelSU");
    setText('val-arch', data.architecture || "Unknown");
    setText('val-sdk', typeof data.sdk_level === 'number' && data.sdk_level > 0 ? `Android SDK ${data.sdk_level}` : "SDK Unknown");
    setText('val-zygisk', data.zygisk_host || "None");
    setText('val-selinux', data.selinux_mode || "Unknown");
    setText('val-boot-dur', `Boot: ${typeof data.boot_duration_sec === 'number' ? data.boot_duration_sec : 0}s`);

    // Update Diagnostics Table
    setText('diag-model', data.device_model || "Android Device");
    if (typeof data.sdk_level === 'number' && data.sdk_level >= 34) {
        setText('diag-release', 'Android 14+');
    } else if (typeof data.sdk_level === 'number' && data.sdk_level >= 29) {
        setText('diag-release', 'Android 10-13');
    } else {
        setText('diag-release', 'Unknown');
    }
    setText('diag-sdk', data.sdk_level ? String(data.sdk_level) : "--");
    setText('diag-arch', data.architecture || "--");
    setText('diag-root', data.root_manager || "Unknown");

    // KernelSU Kernel Driver & Manager Status
    let ksuKernelText = "N/A";
    let ksuAppText = "N/A";
    if (data.root_manager && data.root_manager.includes("KernelSU")) {
        if (data.ksu_version_match === 1 && data.ksu_manager_code > 0) {
            ksuKernelText = `Synchronized (v${data.ksu_kernel_code})`;
            ksuAppText = `Synchronized (v${data.ksu_manager_code})`;
        } else if (data.ksu_version_match === 0) {
            ksuKernelText = data.ksu_kernel_code > 0 ? `Driver v${data.ksu_kernel_code} (Mismatch)` : "Driver Unmatched";
            ksuAppText = data.ksu_manager_code > 0 ? `Manager v${data.ksu_manager_code} (Mismatch)` : "Manager Unmatched";
        } else if (data.ksu_kernel_code > 0 || data.ksu_manager_code > 0) {
            ksuKernelText = data.ksu_kernel_code > 0 ? `Driver v${data.ksu_kernel_code}` : "Driver Detected";
            ksuAppText = data.ksu_manager_code > 0 ? `Manager v${data.ksu_manager_code}` : "Manager Detected";
        } else {
            ksuKernelText = "Unverified";
            ksuAppText = "Unverified";
        }
    }
    setText('diag-ksu-kernel', ksuKernelText);
    setText('diag-ksu-app', ksuAppText);

    setText('diag-zygisk', data.zygisk_host || "None");
    setText('diag-selinux', data.selinux_mode || "Unknown");
    setText('diag-conflicts', data.active_conflicts ? String(data.active_conflicts) : "None (Safe Coexistence)");
}

function initSettings() {
    document.getElementById('btn-save-cfg')?.addEventListener('click', async () => {
        // Enforce strict boolean casting ("1" or "0" only)
        const diag = document.getElementById('cfg-diag')?.checked ? "1" : "0";
        const watchdog = document.getElementById('cfg-watchdog')?.checked ? "1" : "0";
        const backup = document.getElementById('cfg-backup')?.checked ? "1" : "0";

        // Enforce strict numeric validation on watchdog interval
        const rawInterval = document.getElementById('cfg-interval')?.value;
        if (typeof rawInterval !== 'string' || !/^\d+$/.test(rawInterval.trim())) {
            alert("Validation Error: Watchdog interval must be a positive integer.");
            return;
        }

        const intervalNum = parseInt(rawInterval.trim(), 10);
        if (!Number.isInteger(intervalNum) || !Number.isFinite(intervalNum) || intervalNum < 60 || intervalNum > 3600) {
            alert("Validation Error: Watchdog interval must be between 60 and 3600 seconds.");
            return;
        }
        const safeInterval = String(intervalNum);

        // Execute via validated arguments with safe error handling
        const res = await execCommand(`. /data/adb/modules/matrix_module/core/matrix_store.sh && matrix_cfg_set diagnostics_enabled ${diag} && matrix_cfg_set health_watchdog_enabled ${watchdog} && matrix_cfg_set watchdog_interval_sec ${safeInterval} && matrix_cfg_set backup_on_boot ${backup}`);

        if (res.code === 0) {
            alert("Configuration applied successfully!");
        } else {
            alert(`Failed to apply configuration: ${res.stderr || "Execution error"}`);
        }
    });

    document.getElementById('btn-reset-cfg')?.addEventListener('click', async () => {
        if (confirm("Restore default configuration?")) {
            const res = await execCommand(". /data/adb/modules/matrix_module/core/matrix_store.sh && matrix_store_write_defaults");
            if (res.code === 0) {
                alert("Defaults restored!");
                // Reload UI inputs
                document.getElementById('cfg-diag').checked = true;
                document.getElementById('cfg-watchdog').checked = true;
                document.getElementById('cfg-interval').value = "300";
                document.getElementById('cfg-backup').checked = true;
            } else {
                alert(`Failed to restore defaults: ${res.stderr || "Execution error"}`);
            }
        }
    });
}

function initLogs() {
    document.getElementById('btn-refresh-log')?.addEventListener('click', refreshLogs);
    document.getElementById('btn-clear-log')?.addEventListener('click', async () => {
        if (confirm("Clear module logs?")) {
            const res = await execCommand(". /data/adb/modules/matrix_module/core/matrix_log.sh && matrix_log_clear");
            if (res.code === 0) {
                refreshLogs();
            } else {
                alert(`Failed to clear logs: ${res.stderr || "Execution error"}`);
            }
        }
    });
}

async function refreshLogs() {
    const logBox = document.getElementById('log-content');
    if (!logBox) return;

    logBox.textContent = "Fetching module logs...";
    const res = await execCommand("tail -n 100 /data/adb/matrix_module/logs/matrix.log 2>/dev/null || cat /data/adb/matrix_module/logs/matrix.log 2>/dev/null");
    if (res.stdout && res.stdout.trim().length > 0) {
        logBox.textContent = res.stdout;
    } else {
        logBox.textContent = "[INFO] No log entries recorded yet. System is operational.";
    }
}

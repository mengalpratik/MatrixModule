#!/system/bin/sh
##########################################################################################
# MatrixModule - Early Boot Lifecycle (post-fs-data)
##########################################################################################

MODDIR="${0%/*}"

# Source core infrastructure
[ -f "$MODDIR/core/matrix_log.sh" ] && . "$MODDIR/core/matrix_log.sh"
[ -f "$MODDIR/core/matrix_store.sh" ] && . "$MODDIR/core/matrix_store.sh"
[ -f "$MODDIR/core/matrix_health.sh" ] && . "$MODDIR/core/matrix_health.sh"

# Ensure storage is ready
if ! matrix_store_init; then
    matrix_health_mark_boot_failed "storage initialization failed during post-fs-data stage"
    exit 1
fi

if ! matrix_log_init; then
    matrix_health_mark_boot_failed "log subsystem initialization failed during post-fs-data stage"
    exit 1
fi

log_info "PostFS" "MatrixModule post-fs-data stage started"

# Check recovery / panic status
if matrix_health_check_recovery_mode; then
    log_warn "PostFS" "Recovery mode detected, skipping background initialization"
    matrix_health_mark_boot_aborted "recovery mode active during post-fs-data stage"
    exit 0
fi

# Register boot start marker
if ! matrix_health_mark_boot_start; then
    matrix_health_mark_boot_failed "failed to register boot start marker in post-fs-data stage"
    exit 1
fi

# Backup configuration if enabled
if [ "$(matrix_cfg_get backup_on_boot 1)" = "1" ]; then
    if ! matrix_cfg_backup; then
        log_warn "PostFS" "Configuration backup failed or config corrupt, attempting restore"
        if ! matrix_cfg_restore; then
            log_error "PostFS" "Configuration recovery failed during post-fs-data stage"
            matrix_health_mark_boot_failed "configuration recovery failed during post-fs-data stage"
            exit 1
        fi
    fi
fi

log_info "PostFS" "Early boot stage complete"
exit 0

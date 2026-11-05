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
matrix_store_init
matrix_log_init

log_info "PostFS" "MatrixModule post-fs-data stage started"

# Check recovery / panic status
if matrix_health_check_recovery_mode; then
    log_warn "PostFS" "Recovery mode detected, skipping background initialization"
    matrix_health_mark_boot_aborted "recovery mode active during post-fs-data stage"
    exit 0
fi

# Register boot start marker
matrix_health_mark_boot_start

# Backup configuration if enabled
if [ "$(matrix_cfg_get backup_on_boot 1)" = "1" ]; then
    matrix_cfg_backup
fi

log_info "PostFS" "Early boot stage complete"
exit 0

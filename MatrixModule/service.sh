#!/system/bin/sh
##########################################################################################
# MatrixModule - Late Boot & Background Service Lifecycle
##########################################################################################

MODDIR="${0%/*}"

# Source core infrastructure
[ -f "$MODDIR/core/matrix_log.sh" ] && . "$MODDIR/core/matrix_log.sh"
[ -f "$MODDIR/core/matrix_store.sh" ] && . "$MODDIR/core/matrix_store.sh"
[ -f "$MODDIR/core/matrix_health.sh" ] && . "$MODDIR/core/matrix_health.sh"
[ -f "$MODDIR/core/matrix_env.sh" ] && . "$MODDIR/core/matrix_env.sh"

matrix_store_init
matrix_log_init

log_info "Service" "MatrixModule service.sh launched"

# Wait for Android boot completion
_wait_ticks=0
_boot_completed=0
while [ "$_wait_ticks" -le 150 ]; do
    if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; then
        _boot_completed=1
        break
    fi
    sleep 2
    _wait_ticks=$((_wait_ticks + 1))
done

if [ "$_boot_completed" -eq 1 ]; then
    # Register boot completion metrics
    matrix_health_mark_boot_complete
else
    log_warn "Service" "Boot completion wait timeout (300s): sys.boot_completed was never set"
    matrix_health_mark_boot_timeout "sys.boot_completed was not set to 1 within 300s timeout"
fi

# Perform non-destructive conflict scan
_conflicts=$(matrix_scan_conflicts)
if [ -n "$_conflicts" ]; then
    log_warn "Service" "Detected active third-party modules with overlapping scopes: $_conflicts"
    log_warn "Service" "MatrixModule is operating in safe coexistence mode. No modules were removed."
else
    log_info "Service" "No conflicting modules detected"
fi

# Background Watchdog Loop (if enabled in config)
if [ "$(matrix_cfg_get health_watchdog_enabled 1)" = "1" ]; then
    log_info "Service" "Starting health monitoring watchdog"
    (
        while true; do
            _interval=$(matrix_cfg_get watchdog_interval_sec 300)
            [ "$_interval" -lt 60 ] && _interval=60
            sleep "$_interval"

            # Check if watchdog was turned off dynamically
            if [ "$(matrix_cfg_get health_watchdog_enabled 1)" != "1" ]; then
                log_info "Watchdog" "Watchdog disabled via configuration, stopping"
                break
            fi

            # Health update tick
            matrix_health_generate_report
        done
    ) &
fi

log_info "Service" "Service initialization finished"
exit 0

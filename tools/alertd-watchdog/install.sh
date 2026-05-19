#!/bin/bash
# install.sh — install the alertd_watchdog onto the host.
#
# Idempotent: re-running overwrites the script + cron + defaults file
# with the latest version from this repo. Existing state in
# /var/lib/alertd-watchdog/ is preserved.
#
# Requires root (writes to /usr/local/sbin, /etc/cron.d, /etc/default).
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root (uses /usr/local/sbin + /etc/cron.d)" >&2
    exit 1
fi

HERE=$(dirname "$(readlink -f "$0")")

SCRIPT_SRC="$HERE/alertd_watchdog.sh"
SCRIPT_DST=/usr/local/sbin/alertd_watchdog.sh
CRON_SRC="$HERE/alertd-watchdog.cron"
CRON_DST=/etc/cron.d/alertd-watchdog
DEFAULTS_DST=/etc/default/alertd-watchdog
LOG_DST=/var/log/alertd-watchdog.log
STATE_DIR=/var/lib/alertd-watchdog

echo "[1/5] Installing script -> $SCRIPT_DST"
install -m 0755 -o root -g root "$SCRIPT_SRC" "$SCRIPT_DST"

echo "[2/5] Installing cron entry -> $CRON_DST"
install -m 0644 -o root -g root "$CRON_SRC" "$CRON_DST"

echo "[3/5] Ensuring state dir -> $STATE_DIR"
mkdir -p "$STATE_DIR"
chown root:root "$STATE_DIR"
chmod 0755 "$STATE_DIR"

echo "[4/5] Touching log -> $LOG_DST"
touch "$LOG_DST"
chown root:root "$LOG_DST"
chmod 0640 "$LOG_DST"

echo "[5/5] Seeding defaults (only if missing) -> $DEFAULTS_DST"
if [ ! -f "$DEFAULTS_DST" ]; then
    cat > "$DEFAULTS_DST" <<'EOF'
# Operator overrides for alertd-watchdog.
# Uncomment + edit only what you want to change from script defaults.

# ALERTD_URL=http://localhost:5090/v1/health
# SMS_API=http://localhost:5080/api/sms/send
# SMS_TO=+40722296753           # bound to the alertd sms_main channel
# FAIL_THRESHOLD=2               # consecutive misses before alert (5 min each)
# RE_ALERT_MIN=30                # re-send window while still down
# TIMEOUT_S=5                    # alertd /v1/health max wait
# DRY_RUN=0                      # set 1 to log instead of sending SMS
# RECOVERY_SMS=0                 # set 1 to also notify on recovery
EOF
    chmod 0644 "$DEFAULTS_DST"
    echo "    (wrote new defaults file with all values commented)"
else
    echo "    (already exists, left untouched)"
fi

# Reload cron — most distros pick up /etc/cron.d/ automatically but
# explicit reload is safer for older sysvinit hosts.
if command -v systemctl > /dev/null 2>&1; then
    systemctl reload cron 2>/dev/null || \
    systemctl reload crond 2>/dev/null || \
    systemctl restart cron 2>/dev/null || true
fi

echo ""
echo "Installed. Sanity check:"
echo "  sudo DRY_RUN=1 $SCRIPT_DST    # one-shot dry run"
echo "  tail -f $LOG_DST              # observe cron output"
echo "  cat /etc/cron.d/alertd-watchdog"

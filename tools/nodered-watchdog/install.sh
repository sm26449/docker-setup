#!/bin/bash
# install.sh — install the nodered_watchdog onto the host.
#
# Idempotent: re-running overwrites the script + cron + defaults file
# with the latest version from this repo. Existing state in
# /var/lib/nodered-watchdog/ is preserved.
#
# Requires root (writes to /usr/local/sbin, /etc/cron.d, /etc/default).
#
# First-run note: the defaults file is seeded with DRY_RUN=1 and a
# placeholder NODERED_PASS. You must edit /etc/default/nodered-watchdog
# and uncomment the credential lines (or set DRY_RUN=0) before the
# watchdog will actually probe + alert.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root (uses /usr/local/sbin + /etc/cron.d)" >&2
    exit 1
fi

HERE=$(dirname "$(readlink -f "$0")")

SCRIPT_SRC="$HERE/nodered_watchdog.sh"
SCRIPT_DST=/usr/local/sbin/nodered_watchdog.sh
CRON_SRC="$HERE/nodered-watchdog.cron"
CRON_DST=/etc/cron.d/nodered-watchdog
DEFAULTS_DST=/etc/default/nodered-watchdog
LOG_DST=/var/log/nodered-watchdog.log
STATE_DIR=/var/lib/nodered-watchdog

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
# Operator overrides for nodered-watchdog.
# Uncomment + edit before the watchdog can probe + alert.

# --- Required --------------------------------------------------------
# NODERED_URL=https://192.168.88.235:1881/api/status
# NODERED_USER=admin
# NODERED_PASS=changeme

# --- Optional --------------------------------------------------------
# JSON_MARKER='"battery"'        # string that MUST appear in body
#                                # (defends against nginx placeholder)
# SMS_API=http://localhost:5080/api/sms/send
# SMS_TO=+40722296753            # same number as alertd sms_main
# FAIL_THRESHOLD=2               # consecutive misses before SMS (5 min each)
# RE_ALERT_MIN=30                # re-send window while still down
# TIMEOUT_S=8                    # probe timeout (NR can be slow on Ekrano)
# DRY_RUN=1                      # log instead of sending SMS (default ON
#                                # until creds are filled in)
# RECOVERY_SMS=0                 # set 1 to also notify on recovery

# Default-on dry run until creds are set.
DRY_RUN=1
EOF
    chmod 0600 "$DEFAULTS_DST"   # tighter than alertd-watchdog because
                                  # this file holds NODERED_PASS once edited
    echo "    (wrote new defaults file; EDIT IT before DRY_RUN=0 takes effect)"
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
echo "Installed. Next steps:"
echo "  1. sudo nano $DEFAULTS_DST              # set NODERED_USER/PASS, unset DRY_RUN"
echo "  2. sudo DRY_RUN=1 $SCRIPT_DST          # smoke test"
echo "  3. tail -f $LOG_DST                    # watch cron output"
echo "  4. sudo cat /etc/cron.d/nodered-watchdog"

#!/bin/bash
# alertd_watchdog.sh — host-side liveness check for the alertd dispatcher.
#
# Why this exists
# ---------------
# alertd is the SMS/Telegram dispatcher for the pv-stack. The 9
# container_down_* rules + the slope-based ac_cooling_failure rule
# (and ~50 others) all depend on alertd being alive. If alertd
# itself crashes or hangs, NONE of those rules can fire — including
# the one that's supposed to watch alertd's own container.
#
# This script is the external out-of-band check that breaks the
# recursive loop. It runs from cron on the host (NOT in a container),
# probes alertd's /v1/health, and on sustained failure POSTs directly
# to the sms-gateway, bypassing alertd entirely.
#
# Failure semantics
# -----------------
# - One miss is tolerated (network blip, GC pause, restart). FAIL_THRESHOLD
#   defaults to 2 → ~10 min worst-case detection latency at 5-min cron
#   cadence. Trade-off: tolerate ~5 min of true downtime to avoid daily
#   false-positive SMSes.
# - After FAIL_THRESHOLD misses in a row, sends one SMS, records
#   timestamp in STATE_FILE.
# - While still down, re-alerts at most every RE_ALERT_MIN minutes
#   (default 30). Avoids spam when alertd is dead for an hour during
#   a longer outage.
# - When alertd recovers, the counter is reset. Recovery notification
#   off by default (set RECOVERY_SMS=1 in /etc/default/alertd-watchdog
#   to opt in).
#
# Defense in depth
# ----------------
# - SMS uses priority=critical → bypasses sms-gateway rate-limit and
#   dedup so the alert always reaches us.
# - If the sms-gateway is ALSO down (worst case), we log and exit;
#   nothing more we can do without an out-of-band channel like a
#   second carrier.
# - Script never `set -e` because cron should still write the state
#   file even if curl fails. Use `set -u` only.
#
# Operator config
# ---------------
# Defaults live below; override via env vars in
# /etc/default/alertd-watchdog (loaded by the systemd timer or cron
# entry). Useful overrides:
#   ALERTD_URL=http://localhost:5090/v1/health
#   SMS_API=http://localhost:5080/api/sms/send
#   SMS_TO=+40722296753
#   FAIL_THRESHOLD=2
#   RE_ALERT_MIN=30
#   DRY_RUN=1                 # log instead of sending — for testing
#   RECOVERY_SMS=1            # also notify on recovery
#
# Manual test
# -----------
#   sudo DRY_RUN=1 /usr/local/sbin/alertd_watchdog.sh
#   sudo cat /var/log/alertd-watchdog.log
#
# Forced-fail test (does NOT touch the real alertd):
#   sudo ALERTD_URL=http://localhost:1/nope DRY_RUN=1 \
#       /usr/local/sbin/alertd_watchdog.sh  # repeat twice to clear threshold
set -u

# Load env overrides (idempotent — file may not exist on first run)
[ -r /etc/default/alertd-watchdog ] && . /etc/default/alertd-watchdog

ALERTD_URL=${ALERTD_URL:-http://localhost:5090/v1/health}
SMS_API=${SMS_API:-http://localhost:5080/api/sms/send}
SMS_TO=${SMS_TO:-+40722296753}
STATE_DIR=${STATE_DIR:-/var/lib/alertd-watchdog}
LOG_FILE=${LOG_FILE:-/var/log/alertd-watchdog.log}
RE_ALERT_MIN=${RE_ALERT_MIN:-30}
FAIL_THRESHOLD=${FAIL_THRESHOLD:-2}
TIMEOUT_S=${TIMEOUT_S:-5}
DRY_RUN=${DRY_RUN:-0}
RECOVERY_SMS=${RECOVERY_SMS:-0}

STATE_FILE="$STATE_DIR/last_alert_ts"
COUNTER_FILE="$STATE_DIR/fail_count"

mkdir -p "$STATE_DIR" 2>/dev/null || {
    echo "cannot create $STATE_DIR" >&2
    exit 1
}

log() {
    local ts
    ts=$(date -Iseconds)
    echo "$ts $*" >> "$LOG_FILE" 2>/dev/null || true
}

# Send SMS via sms-gateway, return 0 on HTTP 200, 1 otherwise.
# SMS_API_KEY is optional — when set (via /etc/default/alertd-watchdog
# matching sms-gateway's SMS_API_KEY env), the watchdog authenticates
# every call. Empty key keeps backwards-compat with legacy deployments.
send_sms() {
    local body="$1"
    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN: would send to $SMS_TO: $body"
        return 0
    fi
    # Build JSON safely (escape any double-quotes in the body)
    local escaped="${body//\"/\\\"}"
    local payload="{\"number\":\"$SMS_TO\",\"message\":\"$escaped\",\"priority\":\"critical\"}"
    local resp http_code
    local auth_args=()
    if [ -n "${SMS_API_KEY:-}" ]; then
        auth_args=(-H "X-API-Key: $SMS_API_KEY")
    fi
    resp=$(curl -sS -m 10 -o /tmp/alertd_wd_resp.$$ -w "%{http_code}" \
        -X POST "$SMS_API" \
        -H 'Content-Type: application/json' \
        "${auth_args[@]}" \
        -d "$payload" 2>>"$LOG_FILE")
    http_code="$resp"
    rm -f /tmp/alertd_wd_resp.$$
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        log "SMS sent OK ($http_code): $body"
        return 0
    fi
    log "SMS send FAILED (HTTP $http_code) to $SMS_TO"
    return 1
}

# ── Probe alertd ────────────────────────────────────────────────────
if curl -sf -m "$TIMEOUT_S" "$ALERTD_URL" > /dev/null 2>&1; then
    # Healthy path
    if [ -s "$STATE_FILE" ]; then
        # Was previously down → now recovered
        log "alertd RECOVERED"
        if [ "$RECOVERY_SMS" = "1" ]; then
            send_sms "OK pv-stack: ALERTD RECOVERED, /v1/health responding."
        fi
        : > "$STATE_FILE"
    fi
    : > "$COUNTER_FILE"
    exit 0
fi

# ── Failure path ────────────────────────────────────────────────────
fc=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
fc=$((fc + 1))
echo "$fc" > "$COUNTER_FILE"
log "alertd unreachable — failure $fc/$FAIL_THRESHOLD ($ALERTD_URL)"

if [ "$fc" -lt "$FAIL_THRESHOLD" ]; then
    exit 1
fi

# Above threshold — check re-alert window
now=$(date +%s)
last=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
if [ -n "$last" ] && [ "$last" -gt 0 ]; then
    since_min=$(( (now - last) / 60 ))
    if [ "$since_min" -lt "$RE_ALERT_MIN" ]; then
        log "alertd still down — last SMS ${since_min} min ago, suppressed"
        exit 1
    fi
fi

# Send the SMS. Message kept under 100 chars to fit one GSM-7 segment
# with room for the gateway prefix.
body="ALERTD DOWN ${fc}x. Container/AC/OV alerts not firing. Check: docker logs pv-stack-alerts"
if send_sms "$body"; then
    echo "$now" > "$STATE_FILE"
fi
exit 0

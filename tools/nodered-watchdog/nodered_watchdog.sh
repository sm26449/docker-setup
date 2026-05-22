#!/bin/bash
# nodered_watchdog.sh — host-side liveness check for Node-RED HTTP API.
#
# Why this exists
# ---------------
# On 2026-05-20 the Ekrano Node-RED HTTP listener died while the
# runtime kept publishing MQTT. policy_engine continued making
# decisions, MQTT status topics stayed fresh, BUT every UI override,
# every /api/deploy from pv-stack-ui, every /api/thermal /control call
# returned HTTP 000 / nginx "Node-RED unreachable" placeholder.
#
# Because the container-level health probes (alertd container_down_*)
# only see "container running", they couldn't catch this. The HTTP
# API was effectively offline for 4+ hours before the operator
# discovered it manually.
#
# This script closes that gap by probing the HTTP /api/status endpoint
# every 5 minutes from cron, validating the response is JSON with the
# expected shape, and on sustained failure POSTing an SMS via the
# sms-gateway. Mirrors alertd-watchdog.sh in structure and runs on the
# same host.
#
# Failure semantics
# -----------------
# Same model as alertd-watchdog: FAIL_THRESHOLD consecutive misses
# before alert, RE_ALERT_MIN minutes between repeat alerts while still
# down. Defaults to 2 misses + 30-min re-alert.
#
# Probe is intentionally stricter than HTTP-200: nginx on Ekrano
# returns 200 with an "unreachable" placeholder HTML when the NR
# upstream is down. We therefore require:
#   - HTTP 200-399
#   - response body is valid JSON
#   - body contains the marker JSON_MARKER (default: '"battery"')
# Customizable per deployment via /etc/default/nodered-watchdog.
#
# Operator config
# ---------------
# Defaults live below; override via /etc/default/nodered-watchdog.
# Mandatory: NODERED_URL, NODERED_USER, NODERED_PASS (no useful defaults
# — placeholder values cause every probe to fail until set).
#
# Manual test
# -----------
#   sudo DRY_RUN=1 /usr/local/sbin/nodered_watchdog.sh
#   sudo cat /var/log/nodered-watchdog.log
#
# Forced-fail test (does NOT touch the real NR):
#   sudo NODERED_URL=https://localhost:1/nope DRY_RUN=1 \
#       /usr/local/sbin/nodered_watchdog.sh
set -u

# Load env overrides (idempotent — file may not exist on first run)
[ -r /etc/default/nodered-watchdog ] && . /etc/default/nodered-watchdog

NODERED_URL=${NODERED_URL:-https://192.168.88.235:1881/api/status}
NODERED_USER=${NODERED_USER:-}
NODERED_PASS=${NODERED_PASS:-}
# Marker that must appear in the JSON body — defends against nginx
# placeholders that return 200 OK with HTML content.
JSON_MARKER=${JSON_MARKER:-\"battery\"}
SMS_API=${SMS_API:-http://localhost:5080/api/sms/send}
SMS_TO=${SMS_TO:-+40722296753}
STATE_DIR=${STATE_DIR:-/var/lib/nodered-watchdog}
LOG_FILE=${LOG_FILE:-/var/log/nodered-watchdog.log}
RE_ALERT_MIN=${RE_ALERT_MIN:-30}
FAIL_THRESHOLD=${FAIL_THRESHOLD:-2}
TIMEOUT_S=${TIMEOUT_S:-8}
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

send_sms() {
    local body="$1"
    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN: would send to $SMS_TO: $body"
        return 0
    fi
    local escaped="${body//\"/\\\"}"
    local payload="{\"number\":\"$SMS_TO\",\"message\":\"$escaped\",\"priority\":\"critical\"}"
    local resp http_code
    resp=$(curl -sS -m 10 -o /tmp/nr_wd_resp.$$ -w "%{http_code}" \
        -X POST "$SMS_API" \
        -H 'Content-Type: application/json' \
        -d "$payload" 2>>"$LOG_FILE")
    http_code="$resp"
    rm -f /tmp/nr_wd_resp.$$
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        log "SMS sent OK ($http_code): $body"
        return 0
    fi
    log "SMS send FAILED (HTTP $http_code) to $SMS_TO"
    return 1
}

# ── Probe Node-RED ──────────────────────────────────────────────────
# Three-stage check:
#   1. HTTP returns 2xx/3xx
#   2. Body is non-empty
#   3. Body contains JSON_MARKER (defends against nginx placeholder)
probe_failed_reason=""
auth_args=()
if [ -n "$NODERED_USER" ] && [ -n "$NODERED_PASS" ]; then
    auth_args=(-u "$NODERED_USER:$NODERED_PASS")
fi

resp_body=$(mktemp /tmp/nr_wd_body.XXXXXX)
http_code=$(curl -sk -m "$TIMEOUT_S" "${auth_args[@]}" \
    -o "$resp_body" -w "%{http_code}" \
    "$NODERED_URL" 2>>"$LOG_FILE") || http_code=000

if [ "$http_code" = "000" ]; then
    probe_failed_reason="timeout/network ($TIMEOUT_S s)"
elif [ "$http_code" -lt 200 ] || [ "$http_code" -ge 400 ]; then
    probe_failed_reason="HTTP $http_code"
elif [ ! -s "$resp_body" ]; then
    probe_failed_reason="empty body"
elif ! grep -q "$JSON_MARKER" "$resp_body"; then
    # Truncate body preview to keep log tidy
    body_preview=$(head -c 120 "$resp_body" | tr -d '\n')
    probe_failed_reason="no marker '$JSON_MARKER' (got: $body_preview)"
fi
rm -f "$resp_body"

if [ -z "$probe_failed_reason" ]; then
    # Healthy
    if [ -s "$STATE_FILE" ]; then
        log "Node-RED RECOVERED"
        if [ "$RECOVERY_SMS" = "1" ]; then
            send_sms "OK pv-stack: NODE-RED HTTP API RECOVERED."
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
log "Node-RED unreachable — failure $fc/$FAIL_THRESHOLD ($probe_failed_reason)"

if [ "$fc" -lt "$FAIL_THRESHOLD" ]; then
    exit 1
fi

# Above threshold — check re-alert window
now=$(date +%s)
last=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
if [ -n "$last" ] && [ "$last" -gt 0 ]; then
    since_min=$(( (now - last) / 60 ))
    if [ "$since_min" -lt "$RE_ALERT_MIN" ]; then
        log "Node-RED still down — last SMS ${since_min} min ago, suppressed"
        exit 1
    fi
fi

body="NR HTTP DOWN ${fc}x ($probe_failed_reason). Overrides + deploys broken. Check Ekrano NR."
if send_sms "$body"; then
    echo "$now" > "$STATE_FILE"
fi
exit 0

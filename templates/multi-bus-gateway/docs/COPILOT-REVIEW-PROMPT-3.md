# Copilot review prompt — round 3 (write envelope, lease, alerts)

Paste into GitHub Copilot Chat (Agent / `@workspace` mode) at the repo root, on
commit `edea918`. Rounds 1–2 covered the earlier security batch and the write
path; this pass targets the code added since: the **write safety envelope +
write-lease dead-man**, the two **self-review fixes**, and the **alerts
test-fire**. Verify claims, re-check the prior fixes didn't regress, and hunt
fresh defects. Cite `file:line`; don't be generic or flattering.

## Context
Self-hosted Modbus-TCP/RTU + HTTP → MQTT/InfluxDB gateway (FastAPI in `janitza/`,
split vanilla-JS SPA in `ui/js/app-*.js`, pytest in `tests/`). It now has a gated
Modbus WRITE path with a declarative safety envelope, driven from Node-RED (L3
policy) or the UI. ~251 tests. Writes are off by default (`security.allow_writes`).

## Review HARD (newest, most dangerous code)

1. **Write safety envelope** — declarative per-register in the device template:
   `writable` + `write_min` + `write_max` + `write_safe`
   (`janitza/device_template.py`). The write endpoint (`POST /api/devices/{id}/write`
   in `janitza/api.py`, `write_device_register`) must enforce:
   - allowlist: a register absent from the template or not `writable` is refused;
   - bounds: holding writes outside `[write_min, write_max]` rejected;
   - **encoding is template-controlled** — `data_type`/`scale` come from the
     template register (`rule`), NOT the payload, so a caller can't write the
     wrong word-count. Confirm the payload can't override type/scale.
   Try to bypass: write an undeclared address; write out of bounds; smuggle a
   different `data_type`; write a coil with a string value; write via any path
   that skips `_write_rule`.

2. **Write-lease dead-man** (`janitza/write_lease.py`, `WriteLeaseManager`) —
   a `lease_ms` write auto-reverts to `write_safe` if not renewed. Verify the
   `_sweep` logic hard:
   - on revert **failure** it must RETRY (not drop the lease) until the safe
     value lands, is renewed, or is cleared;
   - a renewal arriving *during* a revert must not be clobbered;
   - concurrency: `_sweep` fires a Modbus write from the lease thread while the
     poller reads and the API may write — is the shared socket lock correct? any
     deadlock or lost-update between renew/clear/expire?
   - does a stuck/permanently-down device cause a hot retry loop or unbounded
     growth? is `armed_ts`/`monotonic` used consistently?

3. **Auth on writes** — writes require `auth_state.enabled or _api_key`
   (`api.py`). Confirm an unauthenticated LAN caller can't write when auth is off
   and no API key is set. Can the primary device be written via ANY path?

4. **Alerts test-fire** (`janitza/alerts.py` `test()` / `_post_webhook_sync`;
   `POST /api/alerts/test`) — it bypasses `enabled` + rate-limit and POSTs to the
   admin-configured `webhook_url`. Concerns: can a caller influence the target URL
   (SSRF) or only the message? Is it rate-limited (webhook/SMS spam)? Does
   `_post_webhook_sync` follow redirects to an unintended host? Body-template
   injection via `{placeholders}`?

## Re-verify (no regressions from rounds 1–2)
WS auth **+ IP allowlist**; admin/admin guard; stored-XSS escaping across
status/dashboard/registers; HTTP header masking; SSRF incl. redirect
re-validation; the app.js split (no method lost/dup, load order, no
`for..in`/`Object.keys(this)`); EN/RO i18n parity.

## Deliver
- Verification table (Fixed / Partial / Regressed) with `file:line`.
- New findings Critical/High/Med/Low: `file:line`, concrete failure scenario, fix
  — correctness/security first.
- Ratings 1–10 per dimension + overall, and whether it's shippable into a
  trusted-LAN, control-adjacent deployment. Top 3 things still in the way.

Be concrete, cite code, and say what you'd still be uncomfortable shipping —
especially anything in the write path or the lease dead-man.

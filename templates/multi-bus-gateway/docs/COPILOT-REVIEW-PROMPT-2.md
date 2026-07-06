# Copilot review prompt — round 2 (post-remediation)

Paste the block below into GitHub Copilot Chat (Agent / `@workspace` mode) at the
repo root. Round 1's prompt is in `COPILOT-REVIEW-PROMPT.md`; this one asks
Copilot to **verify the fixes we made in response to round 1** and give a fresh,
honest opinion on the current state.

---

You are a senior staff engineer and application-security reviewer doing a
**second-pass audit** of this repository. You (or a peer) already reviewed it once;
we then made a batch of changes in response. Your job now is to **verify those
changes actually fix what they claim, check nothing regressed, review the NEW
code for fresh defects, and give an updated honest opinion**. Open files as
needed; cite `file:line`. Do not be generic or flattering.

## What this project is

A self-hosted **general Modbus-TCP/RTU + HTTP → MQTT/InfluxDB gateway** with a
web UI (FastAPI backend in `janitza/`, vanilla-JS SPA in `ui/`, pytest in
`tests/`). It began as a single-device Janitza UMG 512-PRO monitor and is now a
multi-device gateway with a device register-map catalog, CSV import, a
virtual-meter (Modbus-slave) subsystem, and a Template Manager. Runs as a Docker
container in a larger home-energy system. ~240 tests.

## Changes made since the first review — VERIFY EACH

1. **WebSocket auth bypass** — `/ws` now validates the session before streaming
   (`janitza/api.py`, `websocket_endpoint`). Confirm an unauthenticated client is
   actually rejected when `ui.auth.enabled`, and that the authenticated UI still
   connects.
2. **admin/admin trap** — enabling login is refused unless the stored admin
   password is a real PBKDF2 hash (`auth.is_hashed`, the guard in
   `update_ui_security`). Confirm the default plaintext `admin` can no longer be
   left active when auth is turned on.
3. **Stored XSS** — poll-group name/description are escaped in `renderPollGroups`
   (`ui/js/app-status.js`). Sweep for any *other* unescaped `innerHTML` of
   user/device-controlled data (device names, template fields, MQTT values).
4. **HTTP-source credential leak** — `/api/devices` masks header values; the
   update path preserves stored headers against a masked round-trip
   (`janitza/api.py`). Confirm tokens can't be read back or wiped.
5. **SSRF** — HTTP/JSON device URLs must resolve to a private LAN address, both at
   config time and per-fetch (`janitza/http_client.py` `lan_url_error`,
   `HttpClient._fetch`; gate `security.allow_nonlan_http_devices`). Try to defeat
   it (DNS rebinding, IPv6, redirects, decimal/octal IP, `0.0.0.0`, CGNAT
   100.64/8, `metadata.google.internal`).
6. **Config/correctness** — `string` removed from readable device-template types;
   `read_registers_batch` capped at 125; duplicate register addresses rejected in
   template validation; selected/device register saves are atomic
   (`config.py`, `device_template.py`, `modbus_client.py`).
7. **Modbus WRITE path + coils (NEW, review hard)** — `POST /api/devices/{id}/write`
   performs FC5/FC6/FC16 writes; FC1/FC2 coil/discrete reads added.
   (`ModbusConnection.write` / `read_bits`, `ModbusClient.write_value`,
   `RegisterEncoder`). Gating claims: refused unless `security.allow_writes`;
   primary device always read-only; HTTP + input/discrete rejected; admin-only;
   audit-logged; read-back verify; `raw = value*scale` with range clamp.
   **Attack it**: can a viewer/unauth caller write? Can the primary be written via
   any path? Encoder overflow/precision bugs? Idempotency/retry double-write?
   Concurrency between a write and the polling thread on the shared socket?
8. **`app.js` was split** into domain files that augment `JanitzaMonitor.prototype`
   via `Object.assign`, loaded as ordered `<script>` tags (`ui/js/app-*.js`,
   core first, `app-boot.js` last). Verify: no method lost/duplicated, load-order
   correctness, the enumerable-prototype-method change is harmless (no
   `for..in`/`Object.keys(this)`), and the single `app` global + inline
   `onclick="app.foo()"` still resolve.
9. **i18n** — EN/RO now at parity (~626 keys); toasts, render labels, static HTML,
   tooltips, `confirm()` dialogs localized. Flag any remaining user-facing
   hardcoded English (excluding intended technical/proper nouns: MQTT, InfluxDB,
   QoS, URL, data-type names).

## Also do a fresh pass for NEW defects

Especially in the code that changed most: the write path, the SSRF guard, the
split SPA, and the auth changes. Look for regressions the fixes may have
introduced.

## Deliver

- **Verification table**: for each of the 9 items above — Fixed / Partially /
  Not fixed / Regressed — with `file:line` evidence.
- **New findings** (Critical/High/Medium/Low): `file:line`, concrete failure
  scenario, fix. Put any correctness/security bug first.
- **Updated ratings 1–10** per dimension (architecture, protocol correctness,
  device catalog, security, reliability, UI/UX, testing, docs, performance) +
  overall, and say how each moved vs a typical first-pass score.
- **Honest verdict**: is this now shippable into a trusted-LAN, control-adjacent
  deployment? What are the top 3 things still standing between it and that bar?

Be concrete, cite code, and tell me what you'd still be uncomfortable shipping.

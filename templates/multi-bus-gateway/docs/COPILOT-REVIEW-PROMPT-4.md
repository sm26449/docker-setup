# Cross-model review prompt (Gemini / GPT via GitHub Copilot) — branch `main`

Run this in **GitHub Copilot against the repo `sm26449/janitza-umg512-modbus-mqtt-ui`,
branch `main`** (Copilot reads the code from GitHub, so it sees the latest push —
no local checkout). Select the Gemini or GPT model and paste the block below.

> **Context for why this prompt is strict:** four prior external reviews all
> graded a *stale* snapshot — they cited `ui/js/app.js` (long since split into
> `ui/js/app-*.js`), wrong line numbers, and reported as "defects" things that
> were already fixed and tested. This prompt exists to prevent that.

---

You are an adversarial security + correctness reviewer. Review the repository
`sm26449/janitza-umg512-modbus-mqtt-ui` at the **current tip of branch `main`**
on GitHub. Start your answer with the HEAD commit SHA + subject you actually
reviewed, so we can confirm it is the latest. Before you claim any symbol, file,
or guard "does not exist" or "is missing", search for it and cite the exact
`file:line`. If your evidence cites `ui/js/app.js` you are on a stale snapshot —
the SPA is split into `ui/js/app-*.js`; re-fetch `main` and start over.

**What this is:** a Modbus-TCP/RTU + HTTP→MQTT/InfluxDB gateway. FastAPI backend
in `janitza/`, a vanilla-JS SPA split across `ui/js/app-*.js` (prototype
augmentation, load order in `ui/templates/index.html`), pytest in `tests/`
(~264 pass in the container). It has a gated, secure-by-default Modbus **write**
path (allowlist + bounds + template-controlled encoding + a write-lease dead-man),
an alert manager (MQTT + webhook), and generic HTTP/JSON device polling.

**DO NOT re-report these — they are already implemented AND tested at HEAD.**
Spending output on them signals a stale review. Verify by reading the cited code:
- WebSocket `/ws` enforces IP-allowlist + session + Origin before streaming —
  `janitza/api.py` (`websocket_endpoint`, ~2742-2760).
- Secret export is credentialed: `GET /api/config/export?include_secrets` needs
  admin role OR a valid `X-API-Key` (the endpoint checks the key itself because
  the middleware only guards state-changing methods) — `janitza/api.py` export.
- SSRF LAN guard normalizes IPv4-mapped IPv6 + rejects unspecified/reserved, and
  the HTTP fetch PINS the resolved IP (no re-resolve; cross-host redirect refused)
  — `janitza/http_client.py` (`lan_url_error`, `resolve_lan_ip`, `_Pinned*Handler`,
  `_SameHostRedirect`).
- Enabling login with an unhashed/`admin` password is refused (`auth.is_hashed`).
- `string` is NOT a valid input data type (would decode as float) —
  `janitza/device_template.py` `VALID_DATA_TYPES`.
- `validate_template` rejects duplicate **addresses** (not just address+name).
- Batch reads cap at 125 registers in BOTH the poller and `read_registers_batch`.
- `modbus.max_gap` makes the batch gap-merge configurable (default 10; 0 = strict).
- 3 stored-XSS sinks fixed + `_esc` escapes `'`/backtick; poll-group names are
  `esc()`-wrapped in `ui/js/app-status.js`.
- Config saves are atomic (temp + `os.replace`) AND fsync'd; `stale_after_s`
  survives a save.
- Alert test-fire is credentialed + rate-limited; the webhook POST refuses redirects.
- Write-lease reverts fire concurrently with a fresh-clock backoff; a per-lease
  generation token aborts a stale revert on renewal.

**Instead, hunt for NEW defects — and specifically try to break the RECENT fixes
(a wrong fix is a fresh bug):**
1. **IP-pinning** (`http_client._fetch` / `_Pinned*Handler`): does pinning break
   TLS cert/hostname verification (server_hostname vs pinned IP)? Any exception
   path that silently falls back to an unpinned/re-resolving connection? Can a
   same-host redirect to a *different port* or a userinfo trick defeat the pin?
   Does `_SameHostRedirect` compare host correctly (case, trailing dot, IDN)?
2. **Export gate**: any other endpoint (backup/import/diagnostics) that emits
   secrets or the admin hash without the same credential bar? Does `include_*`
   leak through `manifest.json`, device sub-files, or templates?
3. **Write-lease concurrency**: with reverts now threaded + joined per sweep,
   any race on the `gen` token, double-revert, or lost renewal? Deadlock between
   the lease lock and the Modbus lock? Unbounded thread growth under flapping?
4. **Write path**: any code path reaching a Modbus write that skips
   `_write_rule`/bounds/lease? Envelope bypass via encoding, word count, coil
   coercion, or the `prefer_fc6` flag?
5. **Auth/CSRF**: any state-changing endpoint missing the auth/CSRF/origin bar?
   The same-origin check now compares host:port — any bypass?
6. **Then sweep everything else**: SSRF residuals, XSS (unescaped interpolation
   into innerHTML/attributes across ALL `app-*.js`), encode/decode round-trip
   correctness, config round-trip field drops, secret masking, i18n EN/RO parity
   (`ui/languages/en.json` vs `ro.json` — key-diff, don't guess).

**Output:**
- The commit hash you reviewed.
- A verification table: Area | Status (OK / Partial / Broken) | `file:line`.
- New findings ranked by severity, each with a CONCRETE failure scenario
  (inputs/state → wrong output/leak) and a minimal fix. Mark unproven suspicions
  as such.
- An explicit list of the bypasses you TRIED and could NOT achieve.
- Per-axis ratings (write-path, lease, auth, SSRF, frontend) + overall, and one
  line: would you ship this to a trusted-LAN, control-adjacent deployment?

# Sketch: Fronius export-limit control via the write API

How to drive a Fronius inverter's power limit through the gateway's **write safety
envelope**, with the **policy in Node-RED (L3)** and the gateway as a bulletproof
**L1 I/O layer**. This is a design sketch — the SunSpec addresses below are
**placeholders you must verify** against your inverter's actual map before use.

## The control register (SunSpec "Immediate Controls", model 123)

A SunSpec inverter (Fronius GEN24/Symo via Modbus TCP) exposes model **123** with:

| Field | Meaning | Type |
|---|---|---|
| `WMaxLimPct` | active-power limit as **% of WMax** | uint16, scaled by `WMaxLimPct_SF` |
| `WMaxLim_Ena` | enable the limit (0 = off, 1 = on) | enum16 |

The **Modbus address** is `SunSpec base (Fronius: 40000) + offset to model 123 +
field offset`. It is device-specific, so **read it off the inverter** rather than
guess. `tools/read_sunspec.py` decodes a *meter*; for the *inverter's* controls
use `tools/find_sunspec_control.py`, which walks the model chain to model 123 and
applies its fixed field offsets:

```
$ python tools/find_sunspec_control.py <inverter-ip> 502 1
  SunSpec map @ 40000 — model chain:
    model    1  header@40002  len 66
    model  123  header@40070  len 24  <-- controls
  WMaxLimPct      address 40075   (currently raw 5000 = 50 %)
  WMaxLim_Ena     address 40079   (currently 1)
  WMaxLimPct_SF   address 40093   value -2  ->  template scale 100
  Template registers (VERIFY, then set write_safe from your fuse math):
    {"address": 40075, "name": "WMaxLimPct", ... "scale": 100, "writable": true,
     "write_min": 0, "write_max": 100, "write_safe": 50}, ...
```

It's read-only and prints a ready-to-paste template snippet with the **real**
numbers for *your* unit. (The `_SF` scale factor becomes the template `scale`:
`scale = 10^(-SF)`, so `SF=-2` → 50 % is stored as raw 5000 → `scale: 100`;
`SF=0` → `scale: 1`.) Do **not** copy a number blindly — a wrong control-register
address is dangerous.

## 1. Declare it writable in a device template (the allowlist + bounds + safe)

Add the inverter as a device with a template that marks the limit register
`writable` with a safety envelope. Sketch (⚠ replace the two `address` values):

```json
{
  "device_template": {
    "schema_version": 1,
    "id": "fronius_gen24_control",
    "name": "Fronius GEN24 — power-limit control (VERIFY addresses)",
    "vendor": "Fronius", "model": "GEN24 (SunSpec model 123)",
    "protocol": { "byte_order": "big", "default_register_type": "holding" },
    "registers": [
      {
        "address": 40232, "name": "WMaxLimPct", "label": "Active power limit",
        "unit": "%", "data_type": "uint16", "register_type": "holding",
        "scale": 1,
        "writable": true,
        "write_min": 0, "write_max": 100,
        "write_safe": 50
      },
      {
        "address": 40236, "name": "WMaxLim_Ena", "label": "Limit enable",
        "data_type": "uint16", "register_type": "holding",
        "writable": true, "write_min": 0, "write_max": 1, "write_safe": 1
      }
    ]
  }
}
```

- **`write_min`/`write_max`** cap the controller: it can never ask for < 0 % or > 100 %.
- **`write_safe`** is the dead-man value the gateway reverts to if the lease
  lapses. **Pick it from your fuse math**, not by default: if the risk is
  over-export tripping the 80 A/phase fuse when the battery is full, `write_safe`
  should be a *conservative* limit (e.g. 50 %) that keeps you under the trip — the
  gateway then fails **safe**, not open.
- `WMaxLimPct_SF` (the SunSpec scale factor) tells you whether 50 % is `50` or
  `5000` on the wire — read it once and set `scale` accordingly.

Enable writes and require a credential (this is control-adjacent):

```yaml
# config.yaml
security:
  allow_writes: true          # off by default
# and either enable ui.auth, or set API_KEY in the environment for Node-RED
```

## 2. Node-RED write pattern (policy lives here — L3)

The gateway does **not** decide *when* or *how much* to curtail — Node-RED does,
using the Janitza per-phase current as truth, and writes with a **short lease as
a heartbeat**.

```
[inject every 10s] → [function: compute limit%] → [http request: POST /write] → [debug]
```

**function — compute the limit (your policy):**
```js
// Janitza per-phase current comes from MQTT (janitza/*). Example guard: if any
// phase nears the 80 A fuse, curtail; otherwise open up. This is illustrative —
// your real policy can be price-aware, SoC-aware, etc.
const iMax = Math.max(flow.get('I_L1')||0, flow.get('I_L2')||0, flow.get('I_L3')||0);
let pct = 100;
if (iMax > 72) pct = 50;          // approaching the fuse → hard curtail
else if (iMax > 65) pct = 80;
msg.payload = {
  register_type: 'holding',
  address: 40232,                 // WMaxLimPct — VERIFY
  data_type: 'uint16',
  value: pct,
  scale: 1,                       // set from WMaxLimPct_SF
  lease_ms: 30000                 // dead-man: revert to write_safe if we go silent
};
msg.headers = { 'X-API-Key': env.get('GATEWAY_API_KEY') };
msg.url = 'http://janitza-monitor:8080/api/devices/fronius-inv/write';
return msg;
```

**http request node:** method `POST`, "Use msg.url", "Use msg.headers",
`Content-Type: application/json`, return "parsed JSON object".

Set `WMaxLim_Ena = 1` **once** at startup (or every N cycles) the same way. On the
first control write, arm it; then the 10 s heartbeat keeps the 30 s lease alive.

## 3. Why this is safe

- **Node-RED crashes / hangs** → the heartbeat stops → after ≤ 30 s the gateway
  **auto-reverts `WMaxLimPct` to `write_safe` (50 %)** — no fuse trip from a stuck
  wide-open limit. Watch it on `GET /api/writes/leases`.
- **Controller bug asks for 500 %** → rejected by `write_max` (422), nothing sent.
- **Bug targets the wrong register** → rejected by the allowlist (403); only
  `WMaxLimPct`/`WMaxLim_Ena` are writable.
- **Every write is** authenticated (API key), audit-logged, and read-back-verified.

The same envelope + lease pattern applies to a Victron ESS grid setpoint, a coil
(FC5) relay, or any other actuator — declare it writable with bounds + a safe
value, and drive it from L3 with a lease.

## 4. Manual writes from the UI

The **Write** modal (Devices → device → registers → Write) does the same call, but
**every write requires an explicit review-and-confirm** — it shows the device,
address, function code, value and lease, and fires only on a second deliberate
click. Use it for one-off changes / commissioning; use Node-RED for continuous
control. Changing an id or other configuration register is exactly the case where
that confirmation matters — treat it deliberately.

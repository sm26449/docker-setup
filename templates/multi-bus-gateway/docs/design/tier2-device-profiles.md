# Tier 2 design — Device profiles: any meter, one coherent UI

Status: **ALL PHASES (A–D) SHIPPED INTERNALLY** (2026-07-02; deployed to
production). Publishing freeze until the release is cut.

- **A** — multi-device core; migration verified live: 65/65 MQTT topics
  identical, Influx tags identical.
- **B** — devices CRUD API + test probes + template library API; Devices card +
  3-step Add Device wizard + device-aware Registers page; i18n EN/RO; verified
  live (create→verify→delete round-trip on production, Playwright smoke).
- **C** — template editor (metadata + inline register table w/ search, capped
  at 150 rendered rows for 4k-register maps), upload w/ 409-overwrite flow,
  export/download, delete guarded while in use, duplicate-builtin flow.
- **D** — Playwright functional suite (15 checks incl. full wizard + editor
  flows, i18n switch) and **axe-core WCAG 2A/AA audit: 0 violations across all
  7 pages + wizard modal, BOTH themes** (fixes: per-theme --accent-text/
  --success-text/--danger-text/--warning-text/--purple-text split so accents
  used as text differ from accents used as white-text surfaces; --text-tertiary
  contrast bump; aria-labels on every unlabeled control; pagination div→ul;
  scrollable regions focusable; wizard steps de-ARIA'd; energy totals use a
  colored dot + primary-text instead of colored values). Responsive audit on
  iPhone SE/14 + iPad portrait/landscape: zero horizontal overflow on all
  pages, wizard fits all viewports; visually inspected via screenshots.
  This puts the UI ahead of the Moxa/JUG25 consoles on every UI gap in
  docs/vendor/GAP-ANALYSIS-2026-07.md §3 (they have no a11y story at all).

83/83 tests. Final live check: 0 failed reads, vmeters serving GX+DataManager,
buffer empty, MQTT topic set still byte-identical.

Phase A implementation notes (deltas vs the plan below):
- Device #1 is **synthesized at load time** from the legacy flat config —
  `config.yaml` is NOT rewritten (safer: rollback = just run the old image).
  Writing a native `devices:` list becomes the job of the Phase B UI; extra
  devices can already be declared in yaml (`devices:` list) today.
- Device #1 passes `None` routing to the publishers (fall back to live global
  config) so Config→Settings edits keep applying without restart; only
  non-primary devices carry explicit routing.
- Built-in templates live in the package (`janitza/device_templates/`) because
  production bind-mounts hide `config/` and `docs/`; user templates go to
  `config/device_templates/`. Converter: `tools/catalog_to_template.py`
  (4126 registers, 29 categories, 58 curated defaults from the live selection).
- WS broadcast + `current_values` stay primary-only until the frontend gets a
  device dimension (Phase B); other devices publish to MQTT/InfluxDB only.
- Replay-buffer entries now carry their destination bucket, and recovered
  failed batches keep their original bucket (per-device buckets survive
  outages too).
Owner decisions this implements: see `docs/ROADMAP.md` → "Competitive gap
analysis" and the decisions log.

## 1. Goals & hard constraints

1. Support **any Modbus meter**: the register map becomes a **device template**
   (select from library / create in UI / upload / export).
2. Config "Modbus TCP" becomes **"Add Device"**: protocol Modbus RTU | TCP
   (form morphs), connection specifics, **device name/id**.
3. **Per-device northbound routing**: each device declares its MQTT topic
   prefix and its InfluxDB bucket — no single global sink.
4. **Migration is invisible**: the existing UMG512 becomes **device #1** with
   its current template, topics, bucket and tags — **data collection must not
   change by one byte** (Node-RED, alertd, Grafana, virtual meters untouched).
5. UI bar: modern, clean, optimized, functional, **accessible to novices**
   (wizard, defaults, inline validation, no docs needed).
6. RTU appears in the data model and UI from day one; the serial transport
   itself lands in Tier 3 (option visible, marked "coming soon" until then).

Non-goals here: RTU transport implementation, RTU-slave virtual meters,
multi-host fleet management.

## 2. Device template schema (the register map artifact)

One JSON file per equipment type. Canonical location
`config/device_templates/<id>.json` (rw bind-mount → uploads survive restarts);
built-ins ship in the image and are seeded on first boot. JSON is canonical
(the existing `docs/modbus_data.json` converts 1:1); the loader also accepts
YAML for hand-written community files.

```jsonc
{
  "device_template": {
    "schema_version": 1,                    // template format version (loader compat)
    "id": "janitza_umg512_pro",             // slug [a-z0-9_], unique, referenced by devices
    "name": "Janitza UMG 512-PRO",
    "vendor": "Janitza electronics GmbH",
    "model": "UMG 512-PRO",
    "version": "1.0.0",                     // template content version (community updates)
    "author": "janitza-monitor built-in",
    "description": "Full Modbus address list, generated from the vendor PDF.",
    "source_document": "Janitza Modbus Address List UMG 512-PRO",

    "protocol": {
      "transports": ["tcp", "rtu"],         // what the equipment supports
      "default_unit_id": 1,
      "functions": [3],                     // FCs the device answers (3=holding, 4=input)
      "byte_order": "big",                  // default word/byte order
      "max_registers_per_read": 125         // batch-read planner cap
    },

    // Suggested poll groups — copied to the device on creation, then owned by
    // the device (same three-group model as today; fully editable).
    "poll_groups": {
      "realtime": { "interval": 1,  "description": "Real-time values" },
      "normal":   { "interval": 5,  "description": "Standard measurements" },
      "slow":     { "interval": 60, "description": "Energy counters, statistics" }
    },

    // Picker structure for the Registers page (order = display order).
    "categories": {
      "voltage":   { "label": "Voltage",   "order": 1 },
      "current":   { "label": "Current",   "order": 2 },
      "power":     { "label": "Power",     "order": 3 },
      "energy":    { "label": "Energy",    "order": 4 },
      "frequency": { "label": "Frequency", "order": 5 },
      "other":     { "label": "Other",     "order": 99 }
    },

    "registers": [
      {
        "address": 19000,
        "name": "_G_ULN[0]",                // stable key (MQTT cache, Influx 'name' tag)
        "label": "Voltage L1-N",            // default display label (editable per device)
        "unit": "V",
        "data_type": "float",               // existing RegisterParser vocabulary
        "access": "RD",                     // RD | RD/WR (from vendor doc; informative)
        "category": "voltage",
        "description": "Voltage L1 to N, 200ms mean",
        "scale": 1,                         // multiplier applied after decode (default 1)
        "poll_group": "realtime",           // suggested group when selected

        // Optional presets applied when the register is SELECTED on a device —
        // exactly the per-register fields the UI edits today. The device's own
        // selected_registers file remains the source of truth after selection.
        "defaults": {
          "mqtt":     { "topic": "voltage/l1_n" },
          "influxdb": { "measurement": "voltage",
                        "tags": { "phase": "L1", "type": "line_neutral" } },
          "ui":       { "widget": "gauge", "min": 0, "max": 300 },
          "thresholds": { "enabled": true, "dangerLow": 200, "warningLow": 210,
                          "warningHigh": 245, "dangerHigh": 253 }
        }
      }
      // ... hundreds more
    ]
  }
}
```

Notes:
- **`docs/modbus_data.json` → built-in template**: `measurements.<cat>.entries[]`
  ({address, data_type, access, name, unit, description, page}) maps field-for-
  field; categories come from the measurement groups; `defaults` for the ~60
  currently-selected registers are lifted from today's `selected_registers.json`
  so the out-of-box experience for Janitza users stays curated.
- Validation on upload/save: unique id, addresses within 0–65535, data types in
  parser vocabulary, no duplicate (address, name) pairs, categories referenced
  by registers must exist. Errors shown **in-table, red rows** (Moxa pattern).
- Export = the same JSON (round-trips through the editor, like vmeter templates).

## 3. Devices configuration schema (`config.yaml`)

```yaml
devices:
  - id: umg512                       # slug; STABLE routing key (MQTT/Influx/API)
    name: "Janitza UMG 512-PRO"      # display name
    template: janitza_umg512_pro
    enabled: true
    connection:
      protocol: tcp                  # tcp | rtu
      host: 192.168.88.207           # tcp fields
      port: 502
      unit_id: 1
      timeout: 3
      retry_attempts: 3
      retry_delay: 1.0
      # --- rtu fields (Tier 3 transport; schema reserved now) ---
      # serial_port: /dev/ttyUSB0
      # baudrate: 9600
      # parity: N                    # N | E | O
      # stopbits: 1
      # bytesize: 8
    mqtt:
      topic_prefix: "janitza/umg512" # PER-DEVICE prefix (device #1 keeps today's)
    influxdb:
      bucket: "janitza"              # PER-DEVICE bucket
      device_tag: "janitza_umg512"   # value of the 'device' tag (compat for #1)
```

- **Global stays global:** broker host/credentials, InfluxDB URL/org/token, UI,
  HA discovery prefix. **Routing (prefix/bucket/tags) moves per device.**
- Per-device register selection: `config/devices/<id>/selected_registers.json`
  (today's schema unchanged, incl. its poll_groups section).
- Runtime: one `ModbusClient` (+ pollers) per enabled device; publishers keyed
  by device id; `/api/status` grows a `devices[]` array (per-device health,
  reads, buffer stats); data_health aggregates worst-of.
- Topic building: `{device.mqtt.topic_prefix}/{register.topic|safe_name}`; the
  prefix may reference `${device_id}` (e.g. `meters/${device_id}`) — evaluated
  once at load.

## 4. Migration — UMG512 becomes device #1, nothing else moves

On first boot after upgrade, if `config.yaml` has a legacy `modbus:` section
and no `devices:` list:

| Today (global) | Becomes (device #1) |
|---|---|
| `modbus.host/port/unit_id/timeout/…` | `devices[0].connection.*` (protocol: tcp) |
| `mqtt.topic_prefix: janitza/umg512` | `devices[0].mqtt.topic_prefix` (same value) |
| `influxdb.bucket: janitza` | `devices[0].influxdb.bucket` (same value) |
| hardcoded `device: janitza_umg512` Influx tag | `devices[0].influxdb.device_tag` (same value) |
| `config/selected_registers.json` | `config/devices/umg512/selected_registers.json` (moved; symlink/fallback kept one release) |
| `docs/modbus_data.json` catalog | built-in template `janitza_umg512_pro` |

Guarantees (add a migration test asserting each):
- **MQTT topics byte-identical** (`janitza/umg512/voltage/l1_n`, `…/status`,
  `…/vmeter/<id>/state`, `…/data_health`).
- **Influx lines byte-identical** (bucket, measurement, tags incl. `device` and
  `name`, fields) — dashboards and backfill keep matching.
- HA discovery: device #1 keeps identifier `janitza_umg512` and its
  `unique_id`s (no duplicate entities in HA).
- Virtual meters keep reading the same live-value cache keys (register `name`
  is the key — unchanged). vmeter source names gain an optional `device:`
  qualifier for multi-device setups later (`umg512:_G_P_SUM3`), defaulting to
  device #1 for bare names (back-compat).
- Legacy env overrides (`MODBUS_HOST` etc.) keep applying to device #1 only.
- Rollback-safe: the legacy keys are preserved (not deleted) in `config.yaml`
  for one release; the old binary can still boot the same file.

## 5. Wireframes

Design language: existing UI (cards, pills, i18n, per-section Save & Apply).
Accessibility: every control labeled, keyboard-navigable, color never the only
signal (icons + text), novice-first copy.

### 5.1 Config → Devices (replaces the "Modbus TCP" card)

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Devices                                              [ + Add Device ]    │
├──────────────────────────────────────────────────────────────────────────┤
│ ● Janitza UMG 512-PRO   umg512          Modbus TCP   192.168.88.207:502  │
│   Template: Janitza UMG 512-PRO (built-in)      60 registers selected    │
│   ● connected · 4.0 reads/s · last read 0.2s ago                         │
│   MQTT → janitza/umg512/…        InfluxDB → bucket "janitza"             │
│   [ Edit ] [ Registers ] [ Test read ] [ Disable ] [ ⋮ ]                 │
├──────────────────────────────────────────────────────────────────────────┤
│ ○ Warehouse EM24        em24-hala       Modbus RTU   /dev/ttyUSB0 · id 5 │
│   Template: Carlo Gavazzi EM24 (uploaded)       12 registers selected    │
│   ⚠ RTU transport arrives in the next release — device saved, idle       │
│   MQTT → meters/em24-hala/…      InfluxDB → bucket "warehouse"           │
│   [ Edit ] [ Registers ] [ Test read ] [ Enable ] [ ⋮ ]                  │
└──────────────────────────────────────────────────────────────────────────┘
  ⋮ menu: Duplicate · Export device config · Delete (with both-branches confirm)
```

One card per device: identity, transport, template, selection count, live
health line (status dot + reads/s + freshness), northbound routing summary.
Everything the operator needs to answer "is it collecting, where does it go".

### 5.2 Add Device — 3-step wizard (modal or page, same component)

Step header: `Connection ─── Template ─── Data routing` (progress, clickable
back, ✓ on completed steps).

**Step 1 — Connection**

```
┌ Add Device — 1/3 Connection ─────────────────────────────────────────────┐
│ Protocol   (•) Modbus TCP    ( ) Modbus RTU  [serial — next release]     │
│                                                                          │
│ ── Modbus TCP ─────────────────────────────────────────────────────────  │
│ Host/IP      [ 192.168.88.42        ]                                    │
│ Port         [ 502   ]  (1–65535, default 502)                           │
│ Unit ID      [ 1     ]  (1–247)                                          │
│ Timeout      [ 3 s   ]  (1–30, default 3)                                │
│ ▸ Advanced: retries (3), retry delay (1.0 s)                             │
│                                                                          │
│ [ Test connection ]   → "✓ Device answered in 18 ms (unit 1, FC3)"       │
│                          or "✗ timeout — check IP/firewall" inline       │
│                                                          [ Next → ]      │
└──────────────────────────────────────────────────────────────────────────┘
   RTU selected → form swaps to: Serial port (dropdown of /dev/tty*),
   Baudrate (9600), Parity (N/E/O), Stop bits, Unit ID, Timeout.
```

**Step 2 — Template (the register map)**

```
┌ Add Device — 2/3 Template ───────────────────────────────────────────────┐
│ How do you want to define the registers?                                 │
│                                                                          │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                  │
│  │ 📚 Choose    │   │ ⬆ Upload     │   │ ✏ Create     │                  │
│  │ from library │   │ template     │   │ new template │                  │
│  └──────────────┘   └──────────────┘   └──────────────┘                  │
│                                                                          │
│ Library: [ search…            ]  filter: vendor ▾                        │
│  ● Janitza UMG 512-PRO      built-in   512 registers   v1.0.0            │
│  ○ Janitza UMG 96-RM        built-in   210 registers   v1.0.0            │
│  ○ Carlo Gavazzi EM24       community  38 registers    v0.9              │
│                                                                          │
│ Selected: Janitza UMG 512-PRO — 512 registers in 8 categories            │
│ Preview ▾ (register table, read-only)                                    │
│                                                       [ ← ] [ Next → ]   │
└──────────────────────────────────────────────────────────────────────────┘
   Upload → drag-and-drop .json/.yaml, validated immediately; errors listed
   per-row ("addr 70012 exceeds 65535", red) BEFORE anything is saved.
   Create → opens the Template Editor (5.4) pre-linked to this wizard; on
   save you return here with the new template selected.
```

**Step 3 — Data routing (identity + northbound)**

```
┌ Add Device — 3/3 Data routing ───────────────────────────────────────────┐
│ Device name   [ Warehouse EM24        ]   (shown in UI)                  │
│ Device id     [ em24-hala             ]   (a–z 0–9 - _ ; fixed after     │
│                auto-suggested from name    creation — used in topics)    │
│                                                                          │
│ MQTT topic prefix   [ meters/em24-hala      ]  (default: meters/${id})   │
│   → values will publish to  meters/em24-hala/voltage/l1_n  (live preview)│
│ InfluxDB bucket     [ warehouse ▾ ]  (existing buckets + "create new")   │
│   device tag        [ em24-hala   ]  (default = id)                      │
│                                                                          │
│ Poll groups (from template, editable):                                   │
│   realtime [ 1 s ]   normal [ 5 s ]   slow [ 60 s ]                      │
│                                                                          │
│ ☑ Open Registers page after creation to pick what to collect             │
│                                          [ ← ] [ Create device ]         │
└──────────────────────────────────────────────────────────────────────────┘
   Review strip above the button: "TCP 192.168.88.42:502 · EM24 template ·
   → MQTT meters/em24-hala/… · → bucket warehouse". Create = save + hot
   apply (pollers start immediately if enabled + reachable).
```

### 5.3 Registers page — device-aware

```
┌ Registers ───────────────────────────────────────────────────────────────┐
│ Device: [ Janitza UMG 512-PRO (umg512) ▾ ]     60 of 512 selected        │
│ [search…]  Categories: | Voltage | Current | Power | Energy | … |        │
│  (everything below identical to today — the catalog now comes from the   │
│   device's template; selection saves to that device's file)              │
└──────────────────────────────────────────────────────────────────────────┘
```

### 5.4 Config → Device Templates (library; mirrors vmeter Templates tab)

```
┌ Device Templates ────────────────────────────────────────────────────────┐
│ [ ⬆ Upload ] [ + New template ]                        [search…]         │
├──────────────────────────────────────────────────────────────────────────┤
│ Janitza UMG 512-PRO   built-in   512 reg   v1.0.0   used by: umg512      │
│                                     [ View ] [ Duplicate ] [ Export ]    │
│ Carlo Gavazzi EM24    community    38 reg   v0.9    used by: em24-hala   │
│                       [ Edit ] [ Duplicate ] [ Export ] [ Delete ]       │
├──────────────────────────────────────────────────────────────────────────┤
│ Editor (Edit/New): metadata card (id, name, vendor, model, byte order,   │
│ unit id, max regs/read) + registers table with inline editing:           │
│   Addr | Name | Label | Unit | Type ▾ | Category ▾ | Poll group ▾ | ⋮    │
│ [+ Add register] [+ Add category] — invalid cells red with message;      │
│ [ Test read ] per row when a live device uses this template.             │
│ Built-ins are read-only → "Duplicate to edit" (JUG25 'Assigned' lock,    │
│ improved). Templates in use show which devices — deleting is blocked     │
│ until unassigned (both-branches dialog explains).                        │
└──────────────────────────────────────────────────────────────────────────┘
```

### 5.5 Dashboard/Monitor/History with N devices

Device filter chips appear only when >1 device exists (zero UI change for
single-device users): `[ All ] [ UMG 512 ] [ EM24 ]`. History register picker
groups by device. Status pills in the title bar aggregate (worst-of) with a
per-device breakdown on click.

## 6. API surface (sketch)

- `GET/POST /api/devices` · `GET/PUT/DELETE /api/devices/{id}` ·
  `POST /api/devices/{id}/test` (test connection / test read)
- `GET/POST /api/device-templates` · `GET/PUT/DELETE /api/device-templates/{id}`
  · `POST /api/device-templates/upload` · `GET /api/device-templates/{id}/export`
- Existing endpoints gain an optional `?device=` param, defaulting to device #1
  (back-compat for current UI/scripts).

## 7. Implementation phases (internal, freeze active)

- **A — core (no UI):** schema + loaders + validation · converter
  `tools/catalog_to_template.py` (modbus_data.json + selected_registers.json →
  `janitza_umg512_pro.json`) · multi-device runtime (ModbusClient per device,
  per-device routing in both publishers) · **migration + byte-identical
  topic/line tests** · `/api/status.devices[]`.
- **B — Devices UI:** list card + Add Device wizard + test buttons + Registers
  device selector.
- **C — Templates UI:** library + editor + upload/export (reuse vmeter
  template-editor patterns).
- **D — polish:** dashboard chips, docs (EN/RO), screenshots, full regression
  on the live UMG512 before the major release ends the freeze.

Each phase merges only with tests green and the live system verified (same
bar as v2.7.0).

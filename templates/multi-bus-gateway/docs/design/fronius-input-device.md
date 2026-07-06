# Fronius Smart Meter as an input device (Phase 5)

Read the Fronius Smart Meter (a **grid meter**) over Modbus TCP via the Fronius
DataManager and expose it as a normal input device in the gateway, using the
**Janitza canonical register names** so the existing EM24 / Fronius output
profiles re-serve it unchanged (to Victron, to a Fronius DataManager, …).

Template: `config/device_templates/fronius_smart_meter.json`
(id `fronius_smart_meter`, protocol TCP, default unit **240**).

## Source: SunSpec meter model 203 (int + scale factor)

The Smart Meter answers on the DataManager's Modbus TCP at unit 240 with the
SunSpec **int+SF three-phase meter model (203)**. The model header is at
register 40070/40071; measurements start at 40072. This app's Modbus reader is
0-based, so **template address = SunSpec register number − 1** (the Fronius
collector uses the same `address − 1` convention).

## Canonical name mapping (Fronius SunSpec → Janitza)

| Fronius (SunSpec) | reg# | Janitza canonical | quantity |
|---|---|---|---|
| WphA/B/C, W | 40088–40091 | `_G_P_SUM3`, `_PLN[0..2]` | active power (total + per phase) |
| PhVphA/B/C | 40078–40080 | `_G_ULN[0..2]` | voltage L-N |
| PPVphAB/BC/CA | 40082–40084 | `_G_ULL[0..2]` | voltage L-L |
| AphA/B/C | 40073–40075 | `_ILN[0..2]` | current per phase |
| Hz | 40086 | `_G_FREQ` | frequency |
| VA | 40093 | `_G_S_SUM3` | apparent power |
| VAR | 40098 | `_G_Q_SUM3` | reactive power |
| PF | 40103 | `_G_PF_SUM3` | power factor |
| TotWhImp | 40116 | `_WH_V[4]` | imported energy (consumption) |
| TotWhExp | 40108 | `_WH_Z[4]` | exported energy (injection) |

The `_G_P_SUM3`, `_G_FREQ`, `_G_ULN[]`, `_ILN[]`, `_PLN[]`, `_WH_V[4]`, `_WH_Z[4]`
names are exactly what the `em24_av53` and `fronius_ts_native` output profiles
bind to — so once this device polls, either profile can re-serve it as a vmeter.

## Open items (need the live meter)

1. **Scale factors.** Model 203 measurements are raw int16 whose real scale comes
   from separate `*_SF` registers (`A_SF` 40076, `V_SF` 40085, `Hz_SF` 40087,
   `W_SF` 40092, `VA_SF` 40097, `VAR_SF` 40102, `PF_SF` 40107, `TotWh_SF` 40124).
   This app applies a **fixed per-register scale**, not dynamic SF. The template
   ships with `scale = 1.0` placeholders and includes the `*_SF` registers so
   they can be read once (device detail → Registers → Query) and the per-register
   scale baked. Alternative: add general SunSpec `sunssf` support to the reader.
2. **Endpoint.** The DataManager IP:port (the collector's production config; the
   example is `192.168.1.100:502`) + confirm meter unit = 240.
3. **Verify** the `− 1` addressing against the live meter (first read of a known
   quantity, e.g. frequency ≈ 50 Hz after scaling).

## Adding it (once the above are settled)

1. Config → Devices → Add device → **Modbus TCP**, host = DataManager IP, unit 240.
2. Template = **Fronius Smart Meter**.
3. Registers → Query the `*_SF` registers, bake the scales (Download map → edit →
   Upload map, or edit per register).
4. (Optional) Virtual Meters → Add instance with source device = the Fronius meter
   and an EM24/Fronius profile to re-serve it.

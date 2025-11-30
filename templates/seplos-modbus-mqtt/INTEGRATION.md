# Seplos Modbus MQTT - Docker Setup Integration

This template integrates the [seplos-modbus-mqtt](https://github.com/sm26449/seplos-modbus-mqtt) project into Docker Services Manager.

## Setup Instructions

### Option 1: Clone into templates folder (Recommended)

```bash
cd /opt/docker-setup/templates
rm -rf seplos-modbus-mqtt  # Remove empty template folder if exists
git clone https://github.com/sm26449/seplos-modbus-mqtt.git seplos-modbus-mqtt
```

### Option 2: Update existing clone

If you already have the repository cloned:

```bash
cd /opt/docker-setup/templates/seplos-modbus-mqtt
git pull origin main
```

## Hardware Requirements

- **RS485 to USB adapter** connected to your server
- **Seplos BMS V3** connected via RS485 (CAN-L/CAN-H or RS485-A/RS485-B)

Common RS485 adapters:
- FTDI FT232RL based adapters
- CH340/CH341 based adapters
- Waveshare USB to RS485

## Installation via Docker Services Manager

```bash
sudo ./install.sh
# Select: 2 - Add Services
# Choose: seplos-modbus-mqtt
```

The installer will prompt for:
- Serial device path (e.g., `/dev/ttyUSB0`)
- Baud rate (default: 19200)
- MQTT broker settings
- InfluxDB settings (optional)
- Home Assistant auto-discovery prefix

## File Structure

After cloning, the folder should contain:

```
templates/seplos-modbus-mqtt/
├── service.yaml              # Service template for docker-setup
├── Dockerfile                # Container build file
├── seplos_bms_mqtt.py        # Main application
├── healthcheck.py            # Docker healthcheck script
├── seplos/                   # Python modules
│   ├── serial_snooper.py     # RS485 passive listener
│   ├── mqtt_manager.py       # MQTT publishing
│   ├── influxdb_manager.py   # InfluxDB integration
│   ├── pack_aggregator.py    # Multi-battery aggregation
│   └── ...
├── seplos_bms_mqtt.ini.example
├── docs/                     # Protocol documentation
├── img/                      # Wiring diagrams
├── README.md                 # Original project documentation
└── INTEGRATION.md            # This file
```

## Dependencies

The service template declares dependencies on:
- `mosquitto` - MQTT broker
- `influxdb` - Time-series database (optional)

These will be auto-detected or installed when deploying the service.

## Serial Device Permissions

The container needs access to the serial device. Docker Services Manager handles this automatically, but for manual setup:

```bash
# Add user to dialout group
sudo usermod -aG dialout $USER

# Or set device permissions
sudo chmod 666 /dev/ttyUSB0
```

## Manual Docker Usage

If you prefer to run without Docker Services Manager:

```bash
cd templates/seplos-modbus-mqtt

# Create config file
cp seplos_bms_mqtt.ini.example seplos_bms_mqtt.ini
nano seplos_bms_mqtt.ini

# Run with docker-compose
docker-compose -f docker-compose.example.yml up -d
```

See the main [README.md](README.md) for detailed configuration options.

## Home Assistant Integration

The service automatically creates Home Assistant entities via MQTT auto-discovery:
- Battery sensors (voltage, current, SOC, SOH, temperature)
- Cell voltage sensors (1-16)
- Alarm binary sensors
- Pack aggregate sensors (totals across all batteries)

Entities appear under: **Settings → Devices & Services → MQTT**

## Updating

To update to the latest version:

```bash
cd /opt/docker-setup/templates/seplos-modbus-mqtt
git pull origin main
docker-compose build --no-cache
docker-compose up -d
```

## Troubleshooting

### No serial device found
```bash
# List USB devices
lsusb

# Check serial devices
ls -la /dev/ttyUSB*
dmesg | grep tty
```

### No data from BMS
- Verify RS485 wiring (A/B or CAN-L/CAN-H)
- Check baud rate matches BMS setting (usually 19200)
- Try swapping A/B wires if no communication
- Check logs: `docker logs seplos-modbus-mqtt`

### MQTT not publishing
- Verify MQTT broker is reachable
- Check MQTT credentials if authentication is enabled
- Enable DEBUG logging for more details

## Wiring Diagram

See `img/seplos_wiring.jpeg` or `img/seplosV4_wiring.png` in this folder for connection diagrams.

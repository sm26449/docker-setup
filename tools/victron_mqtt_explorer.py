#!/usr/bin/env python3
"""
Victron MQTT Explorer
Connects to Venus OS MQTT broker, discovers all topics and their structure,
then generates optimized Telegraf configuration recommendations.

Usage:
    python3 victron_mqtt_explorer.py [--duration SECONDS]
"""

import ssl
import json
import os
import sys
import argparse
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional

try:
    import paho.mqtt.client as mqtt
except ImportError:
    print("Error: paho-mqtt not installed. Run: pip install paho-mqtt")
    sys.exit(1)


@dataclass
class TopicData:
    """Stores information about a discovered topic."""
    topic: str
    values: list = field(default_factory=list)
    value_types: set = field(default_factory=set)
    first_seen: datetime = field(default_factory=datetime.now)
    last_seen: datetime = field(default_factory=datetime.now)
    count: int = 0

    def add_value(self, value):
        self.count += 1
        self.last_seen = datetime.now()
        self.values.append(value)
        if len(self.values) > 10:
            self.values.pop(0)
        self.value_types.add(type(value).__name__)


class VictronMQTTExplorer:
    """Explores Victron Venus OS MQTT broker and analyzes topic structure."""

    def __init__(self, server: str, port: int, portal_id: str,
                 username: str = None, password: str = None,
                 use_ssl: bool = True, insecure: bool = True):
        self.server = server
        self.port = port
        self.portal_id = portal_id
        self.username = username
        self.password = password
        self.use_ssl = use_ssl
        self.insecure = insecure

        self.topics: dict[str, TopicData] = {}
        self.device_types: dict[str, set] = defaultdict(set)
        self.measurements: dict[str, dict] = defaultdict(lambda: defaultdict(set))
        self.running = True
        self.connected = False
        self.message_count = 0

        self.client = mqtt.Client(client_id="victron-explorer", protocol=mqtt.MQTTv311)
        self._setup_client()

    def _setup_client(self):
        """Configure MQTT client."""
        if self.username:
            self.client.username_pw_set(self.username, self.password)

        if self.use_ssl:
            context = ssl.create_default_context()
            if self.insecure:
                context.check_hostname = False
                context.verify_mode = ssl.CERT_NONE
            self.client.tls_set_context(context)

        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message
        self.client.on_disconnect = self._on_disconnect

    def _on_connect(self, client, userdata, flags, rc):
        """Handle connection callback."""
        if rc == 0:
            self.connected = True
            print(f"✓ Connected to {self.server}:{self.port}")

            # Subscribe to all topics under our portal ID
            topic = f"N/{self.portal_id}/#"
            client.subscribe(topic, qos=0)
            print(f"✓ Subscribed to: {topic}")

            # Also subscribe to keepalive topic
            client.subscribe(f"R/{self.portal_id}/#", qos=0)
        else:
            print(f"✗ Connection failed with code: {rc}")
            self.running = False

    def _on_disconnect(self, client, userdata, rc):
        """Handle disconnection."""
        self.connected = False
        if rc != 0:
            print(f"! Unexpected disconnection (code: {rc})")

    def _on_message(self, client, userdata, msg):
        """Process incoming MQTT message."""
        self.message_count += 1
        topic = msg.topic

        try:
            payload = json.loads(msg.payload.decode('utf-8'))
            value = payload.get('value')
        except (json.JSONDecodeError, UnicodeDecodeError):
            value = msg.payload.decode('utf-8', errors='replace')

        # Store topic data
        if topic not in self.topics:
            self.topics[topic] = TopicData(topic=topic)
        self.topics[topic].add_value(value)

        # Parse topic structure: N/<portal_id>/<device_type>/<instance>/<path...>
        parts = topic.split('/')
        if len(parts) >= 4 and parts[0] == 'N':
            device_type = parts[2]
            instance = parts[3]
            path = '/'.join(parts[4:]) if len(parts) > 4 else ''

            self.device_types[device_type].add(instance)

            # Track fields per measurement
            value_type = type(value).__name__ if value is not None else 'NoneType'
            self.measurements[device_type][path].add(value_type)

        # Progress indicator
        if self.message_count % 100 == 0:
            print(f"\r  Received {self.message_count} messages, {len(self.topics)} unique topics...", end='', flush=True)

    def connect(self):
        """Connect to MQTT broker."""
        print(f"\n{'='*60}")
        print(f"Victron MQTT Explorer")
        print(f"{'='*60}")
        print(f"Server: {self.server}:{self.port}")
        print(f"Portal ID: {self.portal_id}")
        print(f"SSL: {self.use_ssl}, Insecure: {self.insecure}")
        print(f"{'='*60}\n")

        try:
            self.client.connect(self.server, self.port, keepalive=60)
        except Exception as e:
            print(f"✗ Connection error: {e}")
            return False
        return True

    def run(self, duration: int = 30):
        """Run the explorer for specified duration."""
        import time

        if not self.connect():
            return

        self.client.loop_start()

        print(f"\nCollecting data for {duration} seconds...")
        start_time = time.time()

        try:
            while time.time() - start_time < duration and self.running:
                time.sleep(0.5)
        except KeyboardInterrupt:
            print("\n\nStopped by user.")

        self.client.loop_stop()
        self.client.disconnect()
        print(f"\n\n✓ Collection complete: {self.message_count} messages, {len(self.topics)} topics")

    def print_report(self):
        """Print analysis report."""
        print(f"\n{'='*60}")
        print("DISCOVERY REPORT")
        print(f"{'='*60}\n")

        # Device types summary
        print("DEVICE TYPES FOUND:")
        print("-" * 40)
        for device_type, instances in sorted(self.device_types.items()):
            print(f"  {device_type}: {len(instances)} instance(s) - [{', '.join(sorted(instances))}]")

        # Detailed measurements per device type
        print(f"\n\nMEASUREMENTS STRUCTURE:")
        print("-" * 40)

        for device_type in sorted(self.measurements.keys()):
            paths = self.measurements[device_type]
            print(f"\n[{device_type}] - {len(paths)} unique paths")

            # Group by first path component
            grouped = defaultdict(list)
            for path in sorted(paths.keys()):
                first = path.split('/')[0] if path else '(root)'
                grouped[first].append((path, paths[path]))

            for group, items in sorted(grouped.items()):
                if len(items) <= 5:
                    for path, types in items:
                        type_str = ', '.join(types)
                        print(f"    {path or '(value)'}: [{type_str}]")
                else:
                    print(f"    {group}/... ({len(items)} fields)")

        # Sample values
        print(f"\n\nSAMPLE VALUES (last received):")
        print("-" * 40)

        important_fields = ['Soc', 'Voltage', 'Current', 'Power', 'Temperature', 'State']
        for topic, data in sorted(self.topics.items()):
            path_parts = topic.split('/')
            if len(path_parts) > 4:
                field_name = path_parts[-1]
                if field_name in important_fields:
                    last_value = data.values[-1] if data.values else 'N/A'
                    print(f"  {topic}")
                    print(f"    → {last_value} (seen {data.count}x)")

    def generate_telegraf_config(self) -> str:
        """Generate optimized Telegraf configuration."""
        config_lines = []

        # Header
        config_lines.extend([
            "# Telegraf Configuration - Victron Energy",
            f"# Auto-generated by victron_mqtt_explorer.py",
            f"# Generated: {datetime.now().isoformat()}",
            f"# Portal ID: {self.portal_id}",
            "",
        ])

        # Determine max topic depth
        max_depth = 0
        for topic in self.topics.keys():
            depth = len(topic.split('/'))
            max_depth = max(max_depth, depth)

        # Generate topic patterns based on actual data
        topic_patterns = set()
        for topic in self.topics.keys():
            parts = topic.split('/')
            if len(parts) >= 4 and parts[0] == 'N':
                device_type = parts[2]
                # Create wildcard pattern for this device type
                topic_patterns.add(f"N/{self.portal_id}/{device_type}/#")

        # MQTT Consumer config
        config_lines.extend([
            "[[inputs.mqtt_consumer]]",
            f'  servers = ["{self._get_mqtt_url()}"]',
            "",
            '  client_id = "telegraf-victron"',
            "  qos = 0",
            '  connection_timeout = "30s"',
            "",
        ])

        if self.username:
            config_lines.extend([
                f'  username = "{self.username}"',
                f'  password = "{self.password}"',
                "",
            ])

        if self.use_ssl and self.insecure:
            config_lines.append("  insecure_skip_verify = true")
            config_lines.append("")

        # Topics
        config_lines.append("  topics = [")
        for pattern in sorted(topic_patterns):
            config_lines.append(f'    "{pattern}",')
        config_lines.append("  ]")
        config_lines.append("")

        # Data format
        config_lines.extend([
            '  data_format = "json_v2"',
            "",
            "  [[inputs.mqtt_consumer.json_v2]]",
            '    [[inputs.mqtt_consumer.json_v2.field]]',
            '      path = "value"',
            '      rename = "value"',
            "",
        ])

        # Topic parsing rules for different depths
        config_lines.extend([
            "  # Topic parsing - extracts device_type as measurement",
            "  [[inputs.mqtt_consumer.topic_parsing]]",
            '    topic = "N/+/+/+/+"',
            '    measurement = "_/_/measurement/_/_"',
            '    tags = "_/portal_id/_/instance/field"',
            "",
            "  [[inputs.mqtt_consumer.topic_parsing]]",
            '    topic = "N/+/+/+/+/+"',
            '    measurement = "_/_/measurement/_/_/_"',
            '    tags = "_/portal_id/_/instance/field/subfield"',
            "",
            "  [[inputs.mqtt_consumer.topic_parsing]]",
            '    topic = "N/+/+/+/+/+/+"',
            '    measurement = "_/_/measurement/_/_/_/_"',
            '    tags = "_/portal_id/_/instance/field/subfield/subfield2"',
            "",
        ])

        return '\n'.join(config_lines)

    def generate_optimized_config(self) -> str:
        """Generate a more optimized config with processors for better data organization."""

        lines = [
            "# Optimized Telegraf Configuration for Victron Energy",
            f"# Auto-generated: {datetime.now().isoformat()}",
            f"# Portal ID: {self.portal_id}",
            "#",
            "# This configuration:",
            "#   - Flattens nested paths into field names",
            "#   - Converts string values to appropriate types",
            "#   - Groups related metrics for easier querying",
            "",
            "[global_tags]",
            f'  portal_id = "{self.portal_id}"',
            "",
            "[agent]",
            '  interval = "10s"',
            "  round_interval = true",
            "  metric_batch_size = 1000",
            "  metric_buffer_limit = 10000",
            '  flush_interval = "10s"',
            "",
            "###############################################################################",
            "#                            OUTPUT PLUGINS                                   #",
            "###############################################################################",
            "",
            "[[outputs.influxdb_v2]]",
            '  urls = ["${TELEGRAF_INFLUXDB_URL}"]',
            '  token = "${TELEGRAF_INFLUXDB_TOKEN}"',
            '  organization = "${TELEGRAF_INFLUXDB_ORG}"',
            '  bucket = "${TELEGRAF_INFLUXDB_BUCKET}"',
            "",
            "###############################################################################",
            "#                            INPUT PLUGINS                                    #",
            "###############################################################################",
            "",
        ]

        # Generate separate input for each device type for better control
        for device_type in sorted(self.device_types.keys()):
            instances = sorted(self.device_types[device_type])
            paths = self.measurements[device_type]

            lines.extend([
                f"# {device_type.upper()} - instances: {', '.join(instances)}",
                "[[inputs.mqtt_consumer]]",
                f'  name_override = "{device_type}"',
                f'  servers = ["{self._get_mqtt_url()}"]',
                '  client_id = "telegraf-victron-' + device_type + '"',
                "  qos = 0",
                "",
            ])

            if self.username:
                lines.extend([
                    f'  username = "{self.username}"',
                    f'  password = "{self.password}"',
                    "",
                ])

            if self.use_ssl and self.insecure:
                lines.append("  insecure_skip_verify = true")
                lines.append("")

            lines.extend([
                "  topics = [",
                f'    "N/{self.portal_id}/{device_type}/#",',
                "  ]",
                "",
                '  data_format = "json_v2"',
                "",
                "  [[inputs.mqtt_consumer.json_v2]]",
                '    [[inputs.mqtt_consumer.json_v2.field]]',
                '      path = "value"',
                "",
                "  # Parse instance from topic",
                "  [[inputs.mqtt_consumer.topic_parsing]]",
                '    topic = "N/+/+/+/+"',
                '    tags = "_/_/_/instance/field"',
                "",
                "  [[inputs.mqtt_consumer.topic_parsing]]",
                '    topic = "N/+/+/+/+/+"',
                '    tags = "_/_/_/instance/field/subfield"',
                "",
            ])

        # Add string processor to convert known string fields
        lines.extend([
            "###############################################################################",
            "#                          PROCESSOR PLUGINS                                  #",
            "###############################################################################",
            "",
            "# Rename nested fields for easier querying",
            "[[processors.rename]]",
            "  [[processors.rename.replace]]",
            '    field = "value"',
            '    dest = "measurement_value"',
            "",
        ])

        return '\n'.join(lines)

    def _get_mqtt_url(self) -> str:
        """Get MQTT URL in correct format."""
        protocol = "ssl" if self.use_ssl else "tcp"
        return f"{protocol}://{self.server}:{self.port}"

    def save_report(self, output_dir: str = "."):
        """Save all reports and configs to files."""
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        # Save topic list
        topics_file = output_path / f"victron_topics_{timestamp}.txt"
        with open(topics_file, 'w') as f:
            f.write(f"# Victron MQTT Topics discovered at {datetime.now().isoformat()}\n")
            f.write(f"# Portal ID: {self.portal_id}\n")
            f.write(f"# Total: {len(self.topics)} topics\n\n")

            for topic in sorted(self.topics.keys()):
                data = self.topics[topic]
                last_val = data.values[-1] if data.values else 'N/A'
                f.write(f"{topic}\n")
                f.write(f"  last_value: {last_val}\n")
                f.write(f"  types: {', '.join(data.value_types)}\n")
                f.write(f"  count: {data.count}\n\n")

        print(f"✓ Topics saved to: {topics_file}")

        # Save basic telegraf config
        basic_config_file = output_path / f"telegraf_victron_{timestamp}.conf"
        with open(basic_config_file, 'w') as f:
            f.write(self.generate_telegraf_config())
        print(f"✓ Basic Telegraf config saved to: {basic_config_file}")

        # Save optimized config
        optimized_config_file = output_path / f"telegraf_victron_optimized_{timestamp}.conf"
        with open(optimized_config_file, 'w') as f:
            f.write(self.generate_optimized_config())
        print(f"✓ Optimized Telegraf config saved to: {optimized_config_file}")

        # Save JSON summary for further processing
        summary_file = output_path / f"victron_summary_{timestamp}.json"
        summary = {
            "portal_id": self.portal_id,
            "server": self.server,
            "port": self.port,
            "discovered_at": datetime.now().isoformat(),
            "total_messages": self.message_count,
            "total_topics": len(self.topics),
            "device_types": {k: list(v) for k, v in self.device_types.items()},
            "measurements": {
                device: {path: list(types) for path, types in paths.items()}
                for device, paths in self.measurements.items()
            },
        }
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        print(f"✓ JSON summary saved to: {summary_file}")


def load_env_file(env_path: str = ".env") -> dict:
    """Load environment variables from .env file."""
    env_vars = {}
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # Remove quotes
                    value = value.strip('"').strip("'")
                    env_vars[key] = value
    return env_vars


def main():
    parser = argparse.ArgumentParser(description="Explore Victron Venus OS MQTT topics")
    parser.add_argument("--duration", type=int, default=30,
                        help="Duration to collect data in seconds (default: 30)")
    parser.add_argument("--env", type=str, default=".env",
                        help="Path to .env file (default: .env)")
    parser.add_argument("--output", type=str, default="./victron_discovery",
                        help="Output directory for reports (default: ./victron_discovery)")
    parser.add_argument("--server", type=str, help="MQTT server (overrides .env)")
    parser.add_argument("--port", type=int, help="MQTT port (overrides .env)")
    parser.add_argument("--portal-id", type=str, help="Victron Portal ID (overrides .env)")

    args = parser.parse_args()

    # Load from .env
    env = load_env_file(args.env)

    # Parse MQTT server URL
    mqtt_url = args.server or env.get("TELEGRAF_MQTT_SERVER", "ssl://localhost:8883")

    # Parse URL components
    use_ssl = mqtt_url.startswith("ssl://")
    url_parts = mqtt_url.replace("ssl://", "").replace("tcp://", "").split(":")
    server = url_parts[0]
    port = args.port or int(url_parts[1]) if len(url_parts) > 1 else (8883 if use_ssl else 1883)

    portal_id = args.portal_id or env.get("VICTRON_PORTAL_ID", "")
    if not portal_id:
        print("Error: VICTRON_PORTAL_ID not found in .env or --portal-id not specified")
        sys.exit(1)

    username = env.get("TELEGRAF_MQTT_USERNAME") or env.get("MQTT_USERNAME")
    password = env.get("TELEGRAF_MQTT_PASSWORD") or env.get("MQTT_PASSWORD")
    insecure = env.get("TELEGRAF_MQTT_INSECURE", "true").lower() == "true"

    # Create and run explorer
    explorer = VictronMQTTExplorer(
        server=server,
        port=port,
        portal_id=portal_id,
        username=username,
        password=password,
        use_ssl=use_ssl,
        insecure=insecure
    )

    explorer.run(duration=args.duration)
    explorer.print_report()
    explorer.save_report(args.output)

    print(f"\n{'='*60}")
    print("DONE!")
    print(f"{'='*60}")
    print(f"\nNext steps:")
    print(f"  1. Review the generated configs in {args.output}/")
    print(f"  2. Copy the optimized config to your Telegraf container")
    print(f"  3. Restart Telegraf to apply changes")


if __name__ == "__main__":
    main()

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install --no-cache-dir paho-mqtt==2.1.0 docker==7.1.0

WORKDIR /app
COPY main.py /app/main.py

HEALTHCHECK --interval=60s --timeout=5s --start-period=15s --retries=3 \
  CMD python3 -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('${MQTT_BROKER:-pv-stack-mosquitto}', int('${MQTT_PORT:-1883}')))" \
    || exit 1

CMD ["python3", "/app/main.py"]

# Test tooling only; never used for the VPS deployment.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    python3 python3-yaml python3-venv ca-certificates openssl nginx curl logrotate iproute2 \
    && rm -rf /var/lib/apt/lists/*
COPY certbot-5.9.0-py3-none-any.whl /tmp/certbot-5.9.0-py3-none-any.whl
RUN echo 'b7adb889d4dc5ee81bc4b606de2576c564e701d6addef3b8685e90e2a4991299  /tmp/certbot-5.9.0-py3-none-any.whl' | sha256sum -c - \
    && python3 -m venv /opt/download-python \
    && /opt/download-python/bin/pip download --only-binary=:all: --dest /opt/certbot-wheels /tmp/certbot-5.9.0-py3-none-any.whl

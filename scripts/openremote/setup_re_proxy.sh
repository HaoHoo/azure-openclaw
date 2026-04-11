#!/bin/bash
# Placeholder: configure local proxy to expose OpenClaw remotely.

# Install Candy to configure local proxy for OpenClaw.
if ! command -v candy &>/dev/null; then
    echo "[openclaw] Installing Candy for local proxy setup..."
    curl -fsSL https://candyproxy.com/install.sh | sh
else
    echo "[openclaw] Candy already installed, skipping install step."
fi

echo 'To set up a local proxy for OpenClaw, use Candy to create a reverse proxy.'
echo 'Please follow the instructions below:'
echo '1. Run the following command to start a reverse proxy with Candy:'
echo '   candy reverse --name openclaw-proxy --target http://localhost:<openclaw_port> --port <proxy_port>'
echo '   Replace <openclaw_port> with the OpenClaw port (default: 8080).'
echo '   Replace <proxy_port> with your desired proxy port (for example: 9090).'
echo '2. Once the proxy is set up, access OpenClaw remotely by connecting'
echo '   to the proxy server IP and the proxy port you specified.'


#!/bin/bash
# configure-openclaw.sh
#
# Installed and configured by the Azure VM Custom Script Extension.
# The following environment variables must be exported before sourcing
# or running this script (injected by the Bicep template at deploy time):
#
#   AZURE_OPENAI_ENDPOINT  – Azure OpenAI service endpoint URL
#   AZURE_OPENAI_APIKEY    – Azure OpenAI API key
#
# Usage (standalone, for local testing):
#   export AZURE_OPENAI_ENDPOINT="https://<account>.openai.azure.com/"
#   export AZURE_OPENAI_APIKEY="<key>"
#   bash configure-openclaw.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Wait for cloud-init (pre-install of Node.js/Python/Git) to finish
# ---------------------------------------------------------------------------
if command -v cloud-init &>/dev/null; then
    cloud-init status --wait 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 2. Persist environment variables for all future sessions
# ---------------------------------------------------------------------------
{
    echo "AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}"
    echo "AZURE_OPENAI_APIKEY=${AZURE_OPENAI_APIKEY}"
} >> /etc/environment

echo "[openclaw] Environment variables written to /etc/environment"

# ---------------------------------------------------------------------------
# 3. Silent install of OpenClaw
# ---------------------------------------------------------------------------
if ! command -v openclaw &>/dev/null; then
    echo "[openclaw] Installing OpenClaw (silent, no onboarding)..."
    curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
else
    echo "[openclaw] OpenClaw already installed, skipping install step."
fi

# ---------------------------------------------------------------------------
# 4. Configure OpenClaw JSON with model endpoint and API key
# ---------------------------------------------------------------------------
if command -v openclaw &>/dev/null; then
    OPENCLAW_CONFIG_DIR="${HOME}/.openclaw"
    OPENCLAW_CONFIG="${OPENCLAW_CONFIG_DIR}/config.json"

    mkdir -p "${OPENCLAW_CONFIG_DIR}"

    if [ -f "${OPENCLAW_CONFIG}" ]; then
        echo "[openclaw] Patching ${OPENCLAW_CONFIG} with Azure OpenAI settings..."
        python3 - <<'PYEOF'
import json, os, sys

config_path = os.path.expanduser("~/.openclaw/config.json")
endpoint    = os.environ.get("AZURE_OPENAI_ENDPOINT", "")
api_key     = os.environ.get("AZURE_OPENAI_APIKEY", "")

try:
    with open(config_path, "r") as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}

config.setdefault("model", {})
config["model"]["endpoint"] = endpoint
config["model"]["apiKey"]   = api_key

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print("[openclaw] config.json updated successfully")
PYEOF
    else
        echo "[openclaw] config.json not found after install – creating minimal config..."
        python3 - <<'PYEOF'
import json, os

config_path = os.path.expanduser("~/.openclaw/config.json")
endpoint    = os.environ.get("AZURE_OPENAI_ENDPOINT", "")
api_key     = os.environ.get("AZURE_OPENAI_APIKEY", "")

os.makedirs(os.path.dirname(config_path), exist_ok=True)

config = {
    "model": {
        "endpoint": endpoint,
        "apiKey":   api_key
    }
}

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print("[openclaw] Minimal config.json created at", config_path)
PYEOF
    fi
else
    echo "[openclaw] WARNING: OpenClaw not found in PATH after install attempt."
    exit 1
fi

echo "[openclaw] Configuration complete."

# Install Copilot CLI
curl -fsSL https://aka.ms/get-copilotcli | bash

if command -v copilot &>/dev/null; then
    echo "[copilotcli] Copilot CLI installed successfully. Please login & initialize."
    copilot login
    copilot init
else
    echo "[copilotcli] Failed to install Copilot CLI."
fi

# Insert acp policy to OpenClaw config if it exists
if command -v openclaw &>/dev/null; then
    echo "[copilotcli] Adding acp policy to OpenClaw config."
    OPENCLAW_CONFIG_DIR="${ADMIN_HOME}/.openclaw"
    OPENCLAW_CONFIG="${OPENCLAW_CONFIG_DIR}/openclaw.json"
    if [ -f "${OPENCLAW_CONFIG}" ]; then
        python3 - <<'PYEOF'

import json
import os
from pathlib import Path
config_path = Path(os.environ['OPENCLAW_CONFIG'])
try:
    data = json.loads(config_path.read_text())
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

data["acp"] = {
    "allowedAgents": [
      "copilot"
    ]
  }
config_path.write_text(json.dumps(data, indent=2))
PYEOF

else
    echo "[copilotcli] OpenClaw config not found, skipping acp policy insertion."
fi


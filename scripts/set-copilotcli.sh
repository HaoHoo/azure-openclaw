# Install Copilot CLI
export PATH="$HOME/.local/bin:$PATH"
sudo chown $USER:$USER $HOME/.cache

if command -v copilot &>/dev/null; then
    echo "[copilotcli] Copilot CLI already installed, skipping installation."
else
    if curl -fsSL https://gh.io/copilot-install | bash; then
        if command -v copilot &>/dev/null; then
            source ~/.bash_profile
            echo "[copilotcli] Copilot CLI installed successfully. Please login & initialize in CLI."
        else
            echo "[copilotcli] Failed to install Copilot CLI."
        fi
    else
        echo "[copilotcli] Failed to get Copilot CLI."
    fi
fi


# Insert acp policy to OpenClaw config if it exists
if command -v openclaw &>/dev/null; then
    echo "[copilotcli] Adding acp policy to OpenClaw config."
    OPENCLAW_CONFIG_DIR="$HOME/.openclaw"
    OPENCLAW_CONFIG="${OPENCLAW_CONFIG_DIR}/openclaw.json"
    export OPENCLAW_CONFIG
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

fi


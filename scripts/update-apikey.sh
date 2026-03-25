#!/bin/bash
set -euo pipefail

# Determine paths relative to this script so cron jobs can find the right user directories.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_HOME="$(dirname "${SCRIPT_DIR}")"
OPENCLAW_CONFIG_DIR="${ADMIN_HOME}/.openclaw"
ENV_FILE="${OPENCLAW_CONFIG_DIR}/.azure.env"
CONFIG_FILE="${OPENCLAW_CONFIG_DIR}/openclaw.json"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[apikey] missing ${ENV_FILE}; please rerun set-openclaw.sh" >&2
  exit 1
fi

set -o allexport
source "${ENV_FILE}"
set +o allexport

resource_file="${AZURE_RESOURCE_JSON_PATH:-${ADMIN_HOME}/infra/resource.json}"

required=(AZURE_OPENAI_ACCOUNT_NAME AZURE_OPENAI_RESOURCE_GROUP AZURE_OPENAI_MODEL AZURE_OPENAI_ENDPOINT AZURE_OPENCLAW_PORT AZURE_RESOURCE_JSON_PATH)
for var in "${required[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "[apikey] ${var} is not defined in ${ENV_FILE}" >&2
    exit 1
  fi
done

echo "[apikey] refreshing API key for ${AZURE_OPENAI_ACCOUNT_NAME}"
key=$(az cognitiveservices account keys list \
  --name "${AZURE_OPENAI_ACCOUNT_NAME}" \
  --resource-group "${AZURE_OPENAI_RESOURCE_GROUP}" \
  --query key1 -o tsv)

export AZURE_OPENAI_APIKEY="${key}"

if [[ -f "${resource_file}" ]]; then
  export RESOURCE_METADATA_PATH="${resource_file}"
  python3 - <<'PYEOF'
import datetime
import json
import os
from pathlib import Path

path = Path(os.environ['RESOURCE_METADATA_PATH'])
try:
    data = json.loads(path.read_text())
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

models = data.setdefault('models', [])
updated = False
for model in models:
    if (model.get('accountName') == os.environ['AZURE_OPENAI_ACCOUNT_NAME'] and
            model.get('resourceGroup') == os.environ['AZURE_OPENAI_RESOURCE_GROUP']):
        model['endpoint'] = os.environ['AZURE_OPENAI_ENDPOINT']
        model['lastUpdated'] = datetime.datetime.utcnow().isoformat() + 'Z'
        updated = True
        break
if not updated:
    models.append({
        'deploymentName': os.environ.get('AZURE_MODEL_DEPLOYMENT_NAME', ''),
        'modelName': os.environ.get('AZURE_MODEL_NAME', ''),
        'accountName': os.environ['AZURE_OPENAI_ACCOUNT_NAME'],
        'resourceGroup': os.environ['AZURE_OPENAI_RESOURCE_GROUP'],
        'region': os.environ.get('AZURE_REGION', ''),
        'endpoint': os.environ['AZURE_OPENAI_ENDPOINT'],
        'lastUpdated': datetime.datetime.utcnow().isoformat() + 'Z',
        'adminUsername': os.environ.get('AZURE_ADMIN_USERNAME', ''),
        'openclawPort': os.environ['AZURE_OPENCLAW_PORT']
    })

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2))
print('[apikey] resource metadata updated at', path)
PYEOF
else
  echo "[apikey] resource metadata not found at ${resource_file}; skipping persistence" >&2
fi

WORKSPACE_DIR="${OPENCLAW_CONFIG_DIR}/workspace"
mkdir -p "${WORKSPACE_DIR}"

BASE_URL="${AZURE_OPENAI_ENDPOINT%/}/openai/v1"

cat <<EOF > "${CONFIG_FILE}"
{
  "meta": {
    "name": "Azure-OpenClaw",
    "version": "1.0.0"
  },
  "models": {
    "mode": "merge",
    "providers": {
      "azure-openai": {
        "baseUrl": "${BASE_URL}",
        "apiKey": "${AZURE_OPENAI_APIKEY}",
        "auth": "api-key",
        "models": [
          {
            "id": "${AZURE_OPENAI_MODEL}",
            "name": "${AZURE_OPENAI_MODEL}(Azure)",
            "api": "openai-completions"
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": "azure-openai/${AZURE_OPENAI_MODEL}",
      "workspace": "${WORKSPACE_DIR}"
    }
  },
  "gateway": {
    "port": ${AZURE_OPENCLAW_PORT},
    "host": "0.0.0.0",
    "mode": "local",
    "trustProxy": true
  }
}
EOF

echo "[apikey] OpenClaw config refreshed at ${CONFIG_FILE}"
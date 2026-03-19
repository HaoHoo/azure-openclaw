#!/bin/bash
# set-openclaw.sh
#
# Installed and configured by the Azure VM Custom Script Extension.
# Variables exported by the Bicep template:
#   AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_APIKEY, AZURE_OPENAI_ACCOUNT_NAME,
#   AZURE_RESOURCE_GROUP_NAME, AZURE_REGION, AZURE_MODEL_NAME,
#   AZURE_MODEL_DEPLOYMENT_NAME, AZURE_OPENAI_RESOURCE_GROUP, AZURE_OPENCLAW_PORT,
#   AZURE_INFRA_DIR, AZURE_RESOURCE_JSON_PATH, AZURE_DNS_JSON_PATH,
#   AZURE_DYNAMIC_IP, AZURE_ADMIN_USERNAME,
#   AZURE_SCRIPTS_REPO_URL, AZURE_SCRIPTS_REPO_REF

set -euo pipefail

AZURE_ADMIN_USERNAME=${AZURE_ADMIN_USERNAME:-${SUDO_USER:-${USER:-$(whoami)}}}

if command -v cloud-init &>/dev/null; then
    cloud-init status --wait 2>/dev/null || true
fi

ADMIN_HOME="${HOME:-/home/${AZURE_ADMIN_USERNAME}}"
SCRIPTS_DIR="${ADMIN_HOME}/scripts"
TMP_SCRIPTS_REPO="/tmp/azure-openclaw-scripts"
REPO_URL="${AZURE_SCRIPTS_REPO_URL:-https://github.com/HaoHoo/azure-opencalw.git}"
REPO_REF="${AZURE_SCRIPTS_REPO_REF:-main}"
DYNAMIC_IP_ENABLED="${AZURE_DYNAMIC_IP:-false}"

mkdir -p "${SCRIPTS_DIR}"

clone_scripts() {
    if ! command -v git &>/dev/null; then
        echo "[openclaw] git is unavailable; skipping helper script sync"
        return
    fi

    rm -rf "${TMP_SCRIPTS_REPO}"
    if git clone --depth 1 --branch "${REPO_REF}" "${REPO_URL}" "${TMP_SCRIPTS_REPO}" >/tmp/openclaw-clone.log 2>&1; then
        rm -rf "${SCRIPTS_DIR}"
        mkdir -p "${SCRIPTS_DIR}"
        if [[ -d "${TMP_SCRIPTS_REPO}/scripts" ]]; then
            cp -R "${TMP_SCRIPTS_REPO}/scripts/." "${SCRIPTS_DIR}/"
        fi
        chown -R "${AZURE_ADMIN_USERNAME}:${AZURE_ADMIN_USERNAME}" "${SCRIPTS_DIR}"
        find "${SCRIPTS_DIR}" -type f -name '*.sh' -exec chmod +x {} +
    else
        echo "[openclaw] Failed to clone ${REPO_URL}@${REPO_REF}; keeping existing helpers if any" >&2
    fi
    rm -rf "${TMP_SCRIPTS_REPO}"
}

clone_scripts

python3 - <<'PYEOF'
import datetime
import json
import os
import pathlib

resource_path = os.path.expanduser(os.environ.get('AZURE_RESOURCE_JSON_PATH', ''))
if not resource_path:
    raise SystemExit('AZURE_RESOURCE_JSON_PATH is not set')

os.makedirs(os.path.dirname(resource_path), exist_ok=True)

entry = {
    'deploymentName': os.environ.get('AZURE_MODEL_DEPLOYMENT_NAME', ''),
    'modelName': os.environ.get('AZURE_MODEL_NAME', ''),
    'accountName': os.environ.get('AZURE_OPENAI_ACCOUNT_NAME', ''),
    'resourceGroup': os.environ.get('AZURE_OPENAI_RESOURCE_GROUP', os.environ.get('AZURE_RESOURCE_GROUP_NAME', '')),
    'region': os.environ.get('AZURE_REGION', ''),
    'endpoint': os.environ.get('AZURE_OPENAI_ENDPOINT', ''),
    'lastUpdated': datetime.datetime.utcnow().isoformat() + 'Z',
    'adminUsername': os.environ.get('AZURE_ADMIN_USERNAME', ''),
    'openclawPort': os.environ.get('AZURE_OPENCLAW_PORT', ''),
    'modelDeploymentName': os.environ.get('AZURE_MODEL_DEPLOYMENT_NAME', ''),
    'dynamicIp': os.environ.get('AZURE_DYNAMIC_IP', 'false').lower() == 'true',
    'scriptsRepoUrl': os.environ.get('AZURE_SCRIPTS_REPO_URL', ''),
    'scriptsRepoRef': os.environ.get('AZURE_SCRIPTS_REPO_REF', '')
}

try:
    data = json.loads(pathlib.Path(resource_path).read_text())
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

models = data.setdefault('models', [])
for idx, model in enumerate(models):
    if (model.get('deploymentName') == entry['deploymentName'] and
            model.get('accountName') == entry['accountName']):
        models[idx] = {**model, **entry}
        break
else:
    models.append(entry)

pathlib.Path(resource_path).write_text(json.dumps(data, indent=2))
print('[openclaw] Resource metadata persisted to', resource_path)
PYEOF

if ! command -v openclaw &>/dev/null; then
    echo "[openclaw] Installing OpenClaw (silent, no onboarding)..."
    curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
else
    echo "[openclaw] OpenClaw already installed, skipping install step."
fi

OPENCLAW_CONFIG_DIR="${ADMIN_HOME}/.openclaw"
OPENCLAW_ENV_FILE="${OPENCLAW_CONFIG_DIR}/.env"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG_DIR}/openclaw.json"
BASE_URL="${AZURE_OPENAI_ENDPOINT%/}/openai/v1"
WORKSPACE_DIR="${OPENCLAW_CONFIG_DIR}/workspace"

mkdir -p "${OPENCLAW_CONFIG_DIR}"
cat <<EOF > "${OPENCLAW_ENV_FILE}"
AZURE_OPENAI_MODEL=${AZURE_OPENAI_MODEL:-${AZURE_MODEL_NAME}}
AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}
AZURE_OPENAI_ACCOUNT_NAME=${AZURE_OPENAI_ACCOUNT_NAME}
AZURE_OPENAI_RESOURCE_GROUP=${AZURE_OPENAI_RESOURCE_GROUP}
AZURE_MODEL_NAME=${AZURE_MODEL_NAME}
AZURE_MODEL_DEPLOYMENT_NAME=${AZURE_MODEL_DEPLOYMENT_NAME}
AZURE_RESOURCE_JSON_PATH=${AZURE_RESOURCE_JSON_PATH}
AZURE_ADMIN_USERNAME=${AZURE_ADMIN_USERNAME}
AZURE_OPENCLAW_PORT=${AZURE_OPENCLAW_PORT}
AZURE_DYNAMIC_IP=${AZURE_DYNAMIC_IP:-false}
AZURE_DNS_JSON_PATH=${AZURE_DNS_JSON_PATH:-${SCRIPTS_DIR}/update-dns/ddns.json}
AZURE_SCRIPTS_REPO_URL=${REPO_URL}
AZURE_SCRIPTS_REPO_REF=${REPO_REF}
EOF

mkdir -p "${WORKSPACE_DIR}"
export OPENCLAW_CONFIG BASE_URL WORKSPACE_DIR AZURE_OPENCLAW_PORT OPENCLAW_ENV_FILE
python3 - <<'PYEOF'
import json
import os
from pathlib import Path

config_path = Path(os.environ['OPENCLAW_CONFIG'])
try:
    data = json.loads(config_path.read_text())
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

data.setdefault('meta', {})
data['meta'].update({'name': 'Azure-OpenClaw', 'version': '1.0.0'})

models = data.setdefault('models', {})
models['mode'] = 'merge'
providers = models.setdefault('providers', {})
azure_provider = providers.setdefault('azure-openai', {})
azure_provider.update({
    'baseUrl': os.environ['BASE_URL'],
    'apiKey': os.environ['AZURE_OPENAI_APIKEY'],
    'auth': 'api-key'
})

model_id = os.environ.get('AZURE_OPENAI_MODEL', os.environ.get('AZURE_MODEL_NAME', ''))
if model_id:
    model_entry = {
        'id': model_id,
        'name': f"{model_id}(Azure)",
        'api': 'openai-completions'
    }
    models_list = azure_provider.setdefault('models', [])
    for idx, model in enumerate(models_list):
        if model.get('id') == model_id:
            models_list[idx].update(model_entry)
            break
    else:
        models_list.append(model_entry)

agents = data.setdefault('agents', {})
defaults = agents.setdefault('defaults', {})
defaults.update({
    'model': f"azure-openai/{model_id}",
    'workspace': os.environ['WORKSPACE_DIR']
})

gateway = data.setdefault('gateway', {})
gateway.update({
    'port': int(os.environ['AZURE_OPENCLAW_PORT']),
    'host': '0.0.0.0',
    'mode': 'local',
    'trustProxy': True
})

config_path.write_text(json.dumps(data, indent=2))
print(f"[openclaw] Configuration persisted to {config_path} and {os.environ['OPENCLAW_ENV_FILE']}")
PYEOF

echo "[openclaw] Configuration complete."

run_set_dync_dns() {
    if [[ "${DYNAMIC_IP_ENABLED}" == "true" ]] && [[ -x "${SCRIPTS_DIR}/set-dync-dns.sh" ]]; then
        /bin/bash "${SCRIPTS_DIR}/set-dync-dns.sh"
        if [[ -x "${SCRIPTS_DIR}/update-ddns-a.sh" ]]; then
            /bin/bash "${SCRIPTS_DIR}/update-ddns-a.sh" || true
        fi
    fi
}

run_set_dync_dns

ensure_cron_entry() {
    local entry="$1"
    local marker="$2"
    local current
    current=$(crontab -l 2>/dev/null || true)
    if printf '%s' "$current" | grep -Fq "$marker"; then
        return
    fi
    if [[ -n "$current" ]]; then
        printf '%s\n%s\n' "$current" "$entry" | crontab -
    else
        printf '%s\n' "$entry" | crontab -
    fi
}

if [[ "${DYNAMIC_IP_ENABLED}" == "true" ]]; then
    ensure_cron_entry "@reboot /bin/bash ${SCRIPTS_DIR}/update-ddns-a.sh >> /var/log/update-ddns-a.log 2>&1" "update-ddns-a.sh"
fi
ensure_cron_entry "@reboot /bin/bash ${SCRIPTS_DIR}/update-apikey.sh >> /var/log/update-apikey.log 2>&1" "update-apikey.sh"

if [[ -x "${SCRIPTS_DIR}/update-apikey.sh" ]]; then
    /bin/bash "${SCRIPTS_DIR}/update-apikey.sh" || true
else
    echo "[openclaw] update-apikey.sh not found in ${SCRIPTS_DIR}" >&2
fi

echo "[openclaw] set-openclaw.sh completed"

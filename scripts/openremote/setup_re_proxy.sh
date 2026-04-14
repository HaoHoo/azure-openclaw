#!/bin/bash
# Placeholder: configure local proxy to expose OpenClaw remotely.

azure_env_file="${HOME}/.openclaw/.azure.env"

if [ ! -f "${azure_env_file}" ]; then
    echo "[openclaw] ${azure_env_file} not found." >&2
    exit 1
fi

read_env_var() {
    local key="$1"
    local value
    value="$(awk -F= -v k="${key}" '$1==k {print substr($0, index($0, "=")+1); exit}' "${azure_env_file}")"
    value="${value#\"}"
    value="${value%\"}"
    printf '%s' "${value}"
}

openclaw_dns_name="$(read_env_var 'AZURE_OPENCLAW_DNSNAME')"

if [ -z "${openclaw_dns_name}" ]; then
    echo "[openclaw] Missing AZURE_OPENCLAW_DNSNAME in ${azure_env_file}." >&2
    exit 1
fi

echo "[openclaw] Preparing Caddy installation dependencies..."
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list

# Install Caddy to configure local proxy for OpenClaw.
if ! command -v caddy &>/dev/null; then
    echo "[openclaw] Installing Caddy for local proxy setup..."
    sudo apt update && sudo apt install -y caddy
else
    echo "[openclaw] Caddy already installed, skipping install step."
fi

if command -v caddy &>/dev/null; then
    # insert caddy config to /etc/caddy/Caddyfile
    CADDYFILE="/etc/caddy/Caddyfile"
    if [ -f "${CADDYFILE}" ]; then
        sudo cp "${CADDYFILE}" "${CADDYFILE}.bak"
        if ! sudo grep -q "${openclaw_dns_name}" "${CADDYFILE}"; then
            echo "[openclaw] Adding OpenClaw proxy configuration to Caddyfile..."
            cat <<EOF | sudo tee -a "${CADDYFILE}" >/dev/null
    ${openclaw_dns_name} {
        handle /openclaw* {
            reverse_proxy localhost:18789
        }
        handle {
            root * /var/www/html
        file_server
        }
    }
EOF
        fi
    fi
    sudo systemctl restart caddy
fi


# Input the local port by prompt
read -rp 'Enter the local port you want to use for SSH tunnel (for example: 18790): ' local_port

# Prefer existing environment variables first.
openclaw_port="${AZURE_OPENCLAW_PORT:-}"
ssh_target_ip="${AZURE_OPENCLAW_PUBLICIP:-}"

# If either value is missing, fallback to ~/.openclaw/.azure.env.
if [ -z "${openclaw_port}" ] || [ -z "${ssh_target_ip}" ]; then
	echo '[sshtunnel] Missing AZURE_OPENCLAW_PORT or AZURE_OPENCLAW_PUBLICIP, read from .azure.env.'
	azure_env_file="${HOME}/.openclaw/.azure.env"

	if [ ! -f "${azure_env_file}" ]; then
		echo '[sshtunnel] ~/.openclaw/.azure.env not found.' >&2
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

	if [ -z "${openclaw_port}" ]; then
		openclaw_port="$(read_env_var 'AZURE_OPENCLAW_PORT')"
	fi
	if [ -z "${ssh_target_ip}" ]; then
		ssh_target_ip="$(read_env_var 'AZURE_OPENCLAW_PUBLICIP')"
	fi
fi

# add ssh tunnel port to "allowedOrigins" openclaw.json
if [ -f ~/.openclaw/openclaw.json ]; then
	jq --arg port "${local_port}" '
		.gateway |= (. // {}) |
		.gateway.controlUi |= (. // {}) |
		.gateway.controlUi.allowedOrigins |= ((. // []) + ["http://localhost:\($port)"] | unique)
	' ~/.openclaw/openclaw.json > ~/.openclaw/openclaw.tmp.json && mv ~/.openclaw/openclaw.tmp.json ~/.openclaw/openclaw.json
fi

echo 'Run this on your local machine to create an SSH tunnel:'
echo "ssh -L ${local_port}:localhost:${openclaw_port} $USER@${ssh_target_ip}"

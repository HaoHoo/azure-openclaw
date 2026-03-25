#!/bin/bash
set -euo pipefail

# provide 4 choices for the user to select how to access openclaw remotely,
# including disable device auth, tailscale tunnel, local proxy and ssh.
# every choice will skip to the shell file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

options=(
	"Disable Device Authentication (Not Recommended)"
	"Install Tailscale Tunnel"
	"Using revert proxy on VM"
	"Using SSH Tunnel on local"
)

print_header() {
	cat <<'EOF'
Select how you want to access OpenClaw remotely:
  1) Disable Device Authentication (Not Recommended)
  2) Install Tailscale Tunnel
  3) Using revert proxy on VM
  4) Using SSH Tunnel on local
EOF
}

run_option() {
	case "$1" in
		1)
			# choice 1: Disable Device Authentication (Not Recommended)
			echo 'This option allows you to disable device authentication for OpenClaw, which is not recommended due to security risks.'
			# run the shell file to disable device authentication
			bash "${SCRIPT_DIR}/disable_dev_auth.sh"
			;;
		2)
			# choice 2: Tailscale Tunnel
			echo 'This option sets up a Tailscale tunnel to securely access OpenClaw remotely. But only Tailscale clients can access OpenClaw with this option.'
			# run the shell file to set up Tailscale tunnel
			bash "${SCRIPT_DIR}/setup_tailscale.sh"
			;;
		3)
			# choice 3: Local Proxy
			echo 'This option configures OpenClaw to be accessed through a local proxy. This allows you to access OpenClaw remotely by connecting to the proxy server.'
			# run the shell file to set up local proxy
			bash "${SCRIPT_DIR}/setup_re_proxy.sh"
			;;
		4)
			# choice 4: SSH Tunnel
			echo 'This option sets up an SSH tunnel to securely access OpenClaw remotely. This allows you to access OpenClaw remotely by connecting to the SSH server.'
			echo 'Run the following command on your local machine to create an SSH tunnel: ssh -L <local_port>:localhost:<openclaw_port> <username>@<server_ip>'
			;;
		*)
			echo 'Invalid option. Please select 1-4.'
			return 1
			;;
	esac
}

print_header
read -rp 'Enter option [1-4]: ' selection
run_option "$selection"
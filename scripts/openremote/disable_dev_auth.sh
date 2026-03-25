#!/bin/bash
# Placeholder: disable device authentication for OpenClaw remote access.

echo 'Disable device authentication for OpenClaw is dangerous. If you just want to 
skip HTTPS or Local access warning, suggested you to reopen it after testing.'

run_option() {
	case "$1" in
		1)
			echo 'Disable disable device authentication for OpenClaw'
            openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true
			;;
		2)
			echo 'Enable device authentication for OpenClaw'
            openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth false
			;;
		*)
			echo 'Invalid option. Please select 1-2.'
			return 1
			;;
	esac
}

print_header
read -rp 'Enter option [1-2]: ' selection
run_option "$selection"

openclaw gateway restart
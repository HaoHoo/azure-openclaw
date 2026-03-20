#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -t 0 ]]; then
    echo "[set-dync-dns] Non-interactive mode, skipping dynamic DNS configuration"
    exit 0
fi

options=("Aliyun DNS" "Skip")
PS3="Please select the DNS service to configure (enter the number and press Enter): "

enabled=false
select choice in "${options[@]}"; do
    case "${choice}" in
        "Aliyun DNS")
            helper="${script_dir}/update-dns/set-dns-ali.sh"
            if [[ -f "${helper}" ]]; then
                chmod +x "${helper}"
                sudo /bin/bash "${helper}"
                enabled=true
            else
                echo "[set-dync-dns] Helper script not found: ${helper}" >&2
            fi
            break
            ;;
        "Skip")
            echo "[set-dync-dns] Skipping DNS configuration as per user choice"
            break
            ;;
        *)
            echo "Invalid choice, please enter 1 or 2."
            ;;
    esac
done

if [[ "${enabled}" != true ]]; then
    echo "[set-dync-dns] DNS configuration is not completed"
fi

#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="${script_dir}/set-dync-dns.sh"

if [[ -x "${helper}" ]]; then
    echo "[ddns] 再次运行 set-dync-dns.sh 以完成 ddns.json 配置，然后 rerun update-ddns-a.sh"
else
    echo "[ddns] 请运行 set-dync-dns.sh 以配置动态公网 IP" >&2
fi

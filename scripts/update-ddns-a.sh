#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /etc/environment >/dev/null 2>&1 || true

infra_dir="${AZURE_INFRA_DIR:-${script_dir}/../infra}"
ddns_file="${AZURE_DNS_JSON_PATH:-${infra_dir}/ddns.json}"

if [[ ! -f "${ddns_file}" ]]; then
    echo "[ddns] ${ddns_file} 缺失，请先运行 set-dync-dns.sh 配置" >&2
    exit 0
fi

mapfile -t ddns_values < <(python3 - <<PY
import json, pathlib

path = pathlib.Path("${ddns_file}")
data = json.loads(path.read_text())
aliyun = data.get('aliyun', {})
print(data.get('provider', ''))
print(aliyun.get('accessKeyId', ''))
print(aliyun.get('accessKeySecret', ''))
print(aliyun.get('regionId', ''))
print(aliyun.get('domain', ''))
print(aliyun.get('subdomain', ''))
print(aliyun.get('recordId', ''))
PY
)

if [[ ${#ddns_values[@]} -lt 7 ]]; then
    echo "[ddns] ${ddns_file} 内容不完整" >&2
    exit 1
fi

provider="${ddns_values[0]:-}"
access_key_id="${ddns_values[1]:-}"
access_key_secret="${ddns_values[2]:-}"
region_id="${ddns_values[3]:-}"
domain="${ddns_values[4]:-}"
subdomain="${ddns_values[5]:-}"
record_id="${AZURE_DNS_RECORD_ID:-${ddns_values[6]:-}}"

if [[ "${provider}" != "aliyun" ]]; then
    echo "[ddns] 目前仅支持 aliyun；配置为 ${provider:-'未知'}" >&2
    exit 1
fi

for var in access_key_id access_key_secret region_id domain subdomain record_id; do
    if [[ -z "${!var}" ]]; then
        echo "[ddns] ${var} 缺失，无法更新" >&2
        exit 1
    fi
done

if ! command -v aliyun &>/dev/null; then
    echo "[ddns] aliyun CLI 缺失，请先运行 set-dns-ali.sh 重新配置" >&2
    exit 1
fi

export PATH="${HOME}/.aliyun/bin:${PATH}"

public_ip_source="${AZURE_PUBLIC_IP_ENDPOINT:-https://ipv4.icanhazip.com}"
if [[ -n "${AZURE_PUBLIC_IP_ENDPOINT:-}" ]]; then
    echo "[ddns] 公网 IP 通过 ${AZURE_PUBLIC_IP_ENDPOINT} 获取" >&2
fi

current_ip=$(curl -fsS "${public_ip_source}" | tr -d '[:space:]')
if [[ -z "${current_ip}" ]]; then
    echo "[ddns] 无法获取当前 IPv4 地址" >&2
    exit 1
fi

if ! aliyun alidns UpdateDomainRecord \
    --RegionId "${region_id}" \
    --AccessKeyId "${access_key_id}" \
    --AccessKeySecret "${access_key_secret}" \
    --RecordId "${record_id}" \
    --RR "${subdomain}" \
    --Type A \
    --Value "${current_ip}" >/tmp/update-ddns.log 2>&1; then
    echo "[ddns] 更新失败，查看 /tmp/update-ddns.log" >&2
    cat /tmp/update-ddns.log >&2
    rm -f /tmp/update-ddns.log
    exit 1
fi

python3 - <<PY
import datetime, json, pathlib

path = pathlib.Path("${ddns_file}")
data = json.loads(path.read_text())
data['currentIp'] = "${current_ip}"
data['lastUpdated'] = datetime.datetime.utcnow().isoformat() + 'Z'
path.write_text(json.dumps(data, indent=2))
PY

rm -f /tmp/update-ddns.log

echo "[ddns] ${subdomain}.${domain} 更新为 ${current_ip}"
#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /etc/environment >/dev/null 2>&1 || true
infra_dir="${AZURE_INFRA_DIR:-${script_dir}/../infra}"
ddns_file="${AZURE_DNS_JSON_PATH:-${infra_dir}/ddns.json}"

mkdir -p "${infra_dir}"

install_aliyun() {
    if command -v aliyun &>/dev/null; then
        return
    fi

    echo "[dns] Installing Alibaba Cloud CLI..."
    curl -fsSL https://aliyuncli.alicdn.com/install.sh | bash
    export PATH="${HOME}/.aliyun/bin:${PATH}"
}

configure_aliyun_cli() {
    local profile="${1:-default}"
    if printf '%s\n' "${access_key_id}" "${access_key_secret}" "${region_id:-cn-hangzhou}" json | aliyun configure >/dev/null 2>&1; then
        echo "[dns] aliyun (profile: ${profile}, region: ${region_id:-cn-hangzhou}) configured."
        return
    fi

    aliyun configure set --profile "${profile}" \
        --access-key-id "${access_key_id}" \
        --access-key-secret "${access_key_secret}" \
        --region-id "${region_id:-cn-hangzhou}" \
        --output json >/dev/null
    echo "[dns] aliyun configure set applied: ${profile} (${region_id:-cn-hangzhou})"
}

fetch_record_id() {
    local domain="$1"
    local rr="$2"
    local region="$3"

    aliyun alidns DescribeDomainRecords \
        --RegionId "${region:-cn-hangzhou}" \
        --DomainName "${domain}" \
        --RRKeyWord "${rr}" \
        --Type A \
        --PageSize 20 \
        --Output json | \
        TARGET_RR="${rr}" python3 - <<'PY'
import json
import os
import sys

records = json.load(sys.stdin).get('DomainRecords', {}).get('Record', [])
target_rr = os.environ.get('TARGET_RR', '')
for record in records:
    if record.get('RR') == target_rr and record.get('Type') == 'A':
        print(record.get('RecordId', ''))
        break
PY
}

prompt_value() {
    local label="$1"
    local current_value="$2"
    local hint="$3"
    if [[ -n "${current_value}" ]]; then
        read -rp "[dns] ${label} [${current_value}]: " value
        echo "${value:-${current_value}}"
    else
        read -rp "[dns] ${label}${hint:+ (${hint})}: " value
        echo "${value}"
    fi
}

read_saved() {
    local key="$1"
    if [[ -f "${ddns_file}" ]]; then
        python3 - <<PY
import json, pathlib, sys
path = pathlib.Path("${ddns_file}")
if not path.exists():
    sys.exit(0)
data = json.loads(path.read_text())
value = data.get('aliyun', {}).get('${key}', '')
print(value)
PY
    else
        echo ""
    fi
}

install_aliyun

saved_access_id="$(read_saved 'accessKeyId')"
saved_access_secret="$(read_saved 'accessKeySecret')"
saved_region="$(read_saved 'regionId')"
saved_domain="$(read_saved 'domain')"
saved_subdomain="$(read_saved 'subdomain')"

access_key_id="$(prompt_value 'Aliyun AccessKey ID' "${saved_access_id}" '')"
access_key_secret="$(prompt_value 'Aliyun AccessKey Secret' "${saved_access_secret}" '')"
region_id="$(prompt_value 'Region ID' "${saved_region}" 'default: cn-hangzhou')"
# Domain & Subdomain use aliyun DNS, not Azure DNS
domain="$(prompt_value 'Domain Name' "${saved_domain}" 'example: example.com')"
subdomain="$(prompt_value 'Sub-Domain (RR)' "${saved_subdomain}" 'example: www')"

configure_aliyun_cli
record_id="$(fetch_record_id "${domain}" "${subdomain}" "${region_id}")"
if [[ -z "${record_id}" ]]; then
    echo "[dns] Can not query ${subdomain}.${domain} for A record's RecordId, please ensure the domain/subdomain exists" >&2
    exit 1
fi

ip_source="${AZURE_PUBLIC_IP_ENDPOINT:-https://ipv4.icanhazip.com}"
if [[ -n "${AZURE_PUBLIC_IP_ENDPOINT:-}" ]]; then
    echo "[dns] Public IP is obtained via ${AZURE_PUBLIC_IP_ENDPOINT}" >&2
fi
current_ip="$(curl -fsS "${ip_source}" | tr -d '[:space:]')"
if [[ -z "${current_ip}" ]]; then
    echo "[dns] Unable to obtain the current IPv4 address" >&2
    exit 1
fi

echo "[dns] Preparing to update ${subdomain}.${domain} (RecordId=${record_id}) to ${current_ip}"
if ! aliyun alidns UpdateDomainRecord \
    --RegionId "${region_id:-cn-hangzhou}" \
    --RecordId "${record_id}" \
    --RR "${subdomain}" \
    --Type A \
    --Value "${current_ip}" >/tmp/update-ddns.log 2>&1; then
    echo "[dns] Update failed, see /tmp/update-ddns.log for details" >&2
    cat /tmp/update-ddns.log >&2
    rm -f /tmp/update-ddns.log
    exit 1
fi
rm -f /tmp/update-ddns.log

cat <<EOF > "${ddns_file}"
{
    "dynamicIpEnabled": true,
    "currentIp": "${current_ip}",
    "aliyun": {
        "accessKeyId": "${access_key_id}",
        "accessKeySecret": "${access_key_secret}",
        "regionId": "${region_id}",
        "domain": "${domain}",
        "subdomain": "${subdomain}",
        "recordId": "${record_id}"
    },
  "lastConfigured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastUpdated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "[dns] Aliyun DDNS configuration has been saved to ${ddns_file}"

update_script_path="${script_dir}/../update-ddns-a.sh"
cat <<'EOF' > "${update_script_path}"
#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /etc/environment >/dev/null 2>&1 || true

infra_dir="${AZURE_INFRA_DIR:-${script_dir}/../infra}"
ddns_file="${AZURE_DNS_JSON_PATH:-${infra_dir}/ddns.json}"

if [[ ! -f "${ddns_file}" ]]; then
    echo "[ddns] ${ddns_file} missing, please rerun set-dns-ali.sh" >&2
    exit 0
fi

mapfile -t ddns_values < <(python3 - <<PY
import json, pathlib

path = pathlib.Path("${ddns_file}")
data = json.loads(path.read_text())
aliyun = data.get('aliyun', {})
print(aliyun.get('accessKeyId', ''))
print(aliyun.get('accessKeySecret', ''))
print(aliyun.get('regionId', ''))
print(aliyun.get('domain', ''))
print(aliyun.get('subdomain', ''))
print(aliyun.get('recordId', ''))
PY
)

if [[ ${#ddns_values[@]} -lt 6 ]]; then
    echo "[ddns] ${ddns_file} content incomplete" >&2
    exit 1
fi

access_key_id="${ddns_values[0]:-}"
access_key_secret="${ddns_values[1]:-}"
region_id="${ddns_values[2]:-}"
domain="${ddns_values[3]:-}"
subdomain="${ddns_values[4]:-}"
record_id="${ddns_values[5]:-}"

if ! command -v aliyun &>/dev/null; then
    echo "[ddns] aliyun CLI is missing, please rerun set-dns-ali.sh" >&2
    exit 1
fi

export PATH="${HOME}/.aliyun/bin:${PATH}"

public_ip_source="${AZURE_PUBLIC_IP_ENDPOINT:-https://ipv4.icanhazip.com}"
if [[ -n "${AZURE_PUBLIC_IP_ENDPOINT:-}" ]]; then
    echo "[ddns] Public IP is obtained via ${AZURE_PUBLIC_IP_ENDPOINT}" >&2
fi

current_ip=$(curl -fsS "${public_ip_source}" | tr -d '[:space:]')
if [[ -z "${current_ip}" ]]; then
    echo "[ddns] Unable to obtain the current IPv4 address" >&2
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
    echo "[ddns] Update failed, see /tmp/update-ddns.log for details" >&2
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

echo "[ddns] ${subdomain}.${domain} has been updated to ${current_ip}"
EOF

chmod +x "${update_script_path}"

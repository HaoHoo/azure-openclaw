#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /etc/environment >/dev/null 2>&1 || true

ddns_file="${AZURE_DNS_JSON_PATH:-${script_dir}/ddns.json}"

mkdir -p "${infra_dir}"

install_aliyun() {
    if command -v aliyun &>/dev/null; then
        return
    fi

    echo "[dns] Installing Alibaba Cloud CLI..."
    curl -fsSL https://aliyuncli.alicdn.com/install.sh | bash
    export PATH="${HOME}/.aliyun/bin:${PATH}"
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
saved_record="$(read_saved 'recordId')"

access_key_id="$(prompt_value 'Aliyun AccessKey ID' "${saved_access_id}" '')"
access_key_secret="$(prompt_value 'Aliyun AccessKey Secret' "${saved_access_secret}" '')"
region_id="$(prompt_value 'Region ID' "${saved_region}" 'cn-hangzhou')"
domain="$(prompt_value '域名' "${saved_domain}" 'example.com')"
subdomain="$(prompt_value '子域名（RR）' "${saved_subdomain}" 'www')"
record_id="$(prompt_value 'Record ID (留空自动查询)' "${saved_record}" '')"

if [[ -z "${record_id}" ]]; then
    echo "[dns] 尝试自动查询 ${subdomain}.${domain} 的记录"
    record_id=$(aliyun alidns DescribeDomainRecords \
        --RegionId "${region_id}" \
        --DomainName "${domain}" \
        --RR "${subdomain}" \
        --Type A \
        --AccessKeyId "${access_key_id}" \
        --AccessKeySecret "${access_key_secret}" \
        --PageSize 10 \
        --Output text \
        --Query "DomainRecords.Record[?RR=='${subdomain}' && Type=='A'].RecordId" | head -n1)
fi

if [[ -z "${record_id}" ]]; then
    echo "[dns] 无法定位 ${subdomain}.${domain} 的 RecordId，请手动登录阿里云控制台确认" >&2
    exit 1
fi

cat <<EOF > "${ddns_file}"
{
  "provider": "aliyun",
  "dynamicIpEnabled": true,
  "aliyun": {
    "accessKeyId": "${access_key_id}",
    "accessKeySecret": "${access_key_secret}",
    "regionId": "${region_id}",
    "domain": "${domain}",
    "subdomain": "${subdomain}",
    "recordId": "${record_id}"
  },
  "lastConfigured": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "[dns] Aliyun DDNS 配置已保存到 ${ddns_file}"

if [[ -x "${script_dir}/../update-ddns-a.sh" ]]; then
    chmod +x "${script_dir}/../update-ddns-a.sh"
fi

update_script_path="${script_dir}/../update-ddns-a.sh"
cat <<'EOF' > "${update_script_path}"
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_HOME="$(dirname "${SCRIPT_DIR}")"
source /etc/environment >/dev/null 2>&1 || true

infra_dir="${AZURE_INFRA_DIR:-${ADMIN_HOME}/infra}"
ddns_file="${AZURE_DNS_JSON_PATH:-${infra_dir}/ddns.json}"

if [[ ! -f "${ddns_file}" ]]; then
    echo "[ddns] ${ddns_file} 缺失，请先运行 set-dync-dns.sh 配置"
    exit 0
fi

mapfile -t ddns_values < <(python3 - <<'PY'
import json
import pathlib

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
record_id="${ddns_values[6]:-}"

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

current_ip=$(curl -fsS https://ipv4.icanhazip.com | tr -d '[:space:]')
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
import datetime
import json
import pathlib

path = pathlib.Path("${ddns_file}")
data = json.loads(path.read_text())
data['currentIp'] = "${current_ip}"
data['lastUpdated'] = datetime.datetime.utcnow().isoformat() + 'Z'
path.write_text(json.dumps(data, indent=2))
PY

rm -f /tmp/update-ddns.log

echo "[ddns] ${subdomain}.${domain} 更新为 ${current_ip}"
EOF

chmod +x "${update_script_path}"

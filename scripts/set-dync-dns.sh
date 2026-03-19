#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -t 0 ]]; then
    echo "[set-dync-dns] 非交互模式，跳过动态 DNS 配置"
    exit 0
fi

options=("Aliyun DNS" "跳过")
PS3="请选择要配置的 DNS 服务 (输入数字并回车): "

enabled=false
select choice in "${options[@]}"; do
    case "${choice}" in
        "Aliyun DNS")
            helper="${script_dir}/update-dns/set-dns-ali.sh"
            if [[ -f "${helper}" ]]; then
                chmod +x "${helper}"
                /bin/bash "${helper}"
                enabled=true
            else
                echo "[set-dync-dns] 未找到辅助脚本 ${helper}" >&2
            fi
            break
            ;;
        "跳过")
            echo "[set-dync-dns] 按用户选择跳过 DNS 配置"
            break
            ;;
        *)
            echo "无效选择，请输入 1 或 2。"
            ;;
    esac
done

if [[ "${enabled}" != true ]]; then
    echo "[set-dync-dns] DNS 配置尚未完成"
fi

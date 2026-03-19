# azure-opencalw
Deploy OpenClaw on an Azure VM with an AI Foundry backend and keep your runtime helpers versioned in the same repo.

[![Deploy with azd](https://aka.ms/deploytoazurebutton)](https://aka.ms/azd-deploy)

## Overview (English)
- **Infrastructure-first** – Two Bicep modules wire up networking, a Linux VM, Azure OpenAI, and AI Foundry. `infra/main.bicep` exposes all the knobs (`modelName`, `openclawPort`, `dynaIP`, `scriptsRepoUrl`, etc.) and forwards them into the resource module, while `infra/resources.bicep` injects the cloud-init bootstrap and the Custom Script Extension payload.
- **Setup script workflow** – The Custom Script Extension runs `scripts/set-openclaw.sh`, which clones this repository, copies the complete `scripts/` directory into the administrator home, records the environment metadata (including whether dynamic IP is enabled), installs OpenClaw, merges `openclaw.json`, and wires cron jobs for `update-apikey.sh` and `update-ddns-a.sh`.
- **Dynamic DNS ready** – When dynamic public IP is enabled, `set-openclaw.sh` runs `set-dync-dns.sh`; the helper prompts you to pick a provider (currently Aliyun), saves your credentials/domain/record info to `scripts/update-dns/ddns.json`, and rewrites `update-ddns-a.sh` into an Aliyun-specific updater that reads that JSON and refreshes the A record using the Aliyun CLI.
- **Secure metadata refresh** – `update-apikey.sh` sources the generated `.env`, hits Azure to refresh the OpenAI key, writes the latest metadata to `resource.json`, and rewrites `~/.openclaw/openclaw.json` so OpenClaw always uses the newest endpoint/key.
- **Reusable helpers** – Because the scripts directory is replaced wholesale via git clone, you can add new helpers (or new DDNS providers) and publish them in this repo; `set-openclaw.sh` will pull them down automatically on every deployment.

## 部署说明（中文）
- **一键部署** – `azd up` 或 `az deployment group create` 会先创建资源组、VM、AI Foundry、OpenAI 账号和模型部署，再通过 Custom Script 自动运行 `scripts/set-openclaw.sh`。
- **脚本如何加载** – `set-openclaw.sh` 会 clone 指定的 `scriptsRepoUrl`/`scriptsRepoRef`，把全部 `scripts/` 复制到 `/home/<admin>/scripts`、赋予执行权限，并向 `.env`、`resource.json`、`openclaw.json` 写入最新的环境参数；同时动态公网 IP 启用时会调用 `set-dync-dns.sh`。该脚本也会注册 cron 任务让 `update-apikey.sh` 和 `update-ddns-a.sh` 在每次重启后执行。
- **动态域名更新** – 运行 `set-dync-dns.sh` 后选择 Aliyun DNS，脚本会安装 Aliyun CLI、让你输入 Access Key ID/Secret、域名、子域名和 RecordId 并保存到 `scripts/update-dns/ddns.json`，之后 `update-ddns-a.sh` 会被重写为从该 JSON 读取配置并刷新 A 记录。后续如果新增其他 DDNS 服务，只需对应服务重写 `update-ddns-a.sh` 接口即可。
- **安全更新流水线** – `update-apikey.sh` 从 `.env` 中读取凭据后调用 `az cognitiveservices account keys list`、更新 `resource.json` 元数据、以及重写 OpenClaw 配置，从而避免将 API Key 写入持久存储任何其它位置。
- **目录结构说明** –
  - `azure.yaml`：定义 AZD 服务和运行信息。
  - `infra/`：Bicep 模板用于资源部署。
  - `scripts/`：启动后被复制到 `/home/<admin>/scripts`，包含 `set-openclaw.sh`、`set-dync-dns.sh`、`set-dns-ali.sh`、`update-ddns-a.sh`、`update-apikey.sh` 等 helper。

请在部署前确保 `vmAdminPassword` 等必填参数已经设置，并通过 `scripts/set-dync-dns.sh` 填写阿里云 DNS 信息以启用动态公网 IP 更新。
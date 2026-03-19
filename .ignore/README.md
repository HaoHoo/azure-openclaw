# azure-opencalw
Deploy OpenClaw to Azure VM and use models on Foundry by 1-click.

目录文件

- `azure.yaml`：定义服务和部署元数据。
- `infra/`：存放 Bicep 模板，用于创建 VM 和 AI Foundry。
- `scripts/`：存放用于初始化 VM 和配置 OpenClaw 的 Shell 脚本。

定义规范

- VM型号：默认 **Standard_B1ms** （2 vCP U，2G RAM），或让用户输入。可选 **Standard_B2s**（2 vCPU, 4GB RAM）。
- 资源组名称：默认  `azure-openclaw-rg`，用户可输入修改。
- VM 名称: 默认 `azure-openclaw-vm`，用户可输入修改。
- 虚拟网络：默认 `azure-openclaw-vnet`，用户可输入修改。
- 公用IP名称：默认 azure-openclaw-publicip，用户可输入修改。
- AI Foundry 名称: 默认 `azure-openclaw-foundry`， 用户可输入修改。
- 模型默认选择 gpt-5.2-chat，用户可输入修改。
- nsg或vm的ip上开启openclaw的端口。
- 创建的模型输出到VM的 `Custom Script Extension` 启动加载脚本，由脚本输出模型的url和api key到环境变量。
- 在 Bicep 模板中通过 `osProfile.customData` 预装 node.js 22，python，git。
- 使用 shell 自动静默安装 openclaw，如果成功修改 openclaw 的 json，将模型的 url 和环境变量的 api key 加入。

部署参数友好提示

- `location` 保留 `eastus` 默认，但没有硬性限制，部署时可以直接输入任意 Azure 区域名称。
- `vmSize` 可直接按默认 `Standard_B1ms`，或选择 `Standard_B2s` 以换取更多内存/CPU。
- `useSpot` 默认为 `false`，需要 Spot 实例时设置为 `true`，并提供 `spotMaxPrice`（默认 `-1` 表示按市场最高价出价）以控制竞价成本；模板会自动设置 Spot 优先级、驱逐策略和账单配置。要修改 `spotMaxPrice` 可在 `az deployment`/`azd deploy` 时传入覆盖值，比如 `--parameters spotMaxPrice=0.75`，也可以通过放在 `.parameters.json` 里引用该模板。
- `modelName` 默认 `gpt-5.2-chat`，也可以改成 `gpt-5.1-chat` 或 `gpt-4o-mini`，模板会将选定模型、OpenAI 终结点和密钥通过 Custom Script Extension 传给 `scripts/set-openclaw.sh`，脚本会把这些值写入 `~/.openclaw/config.json` 供 OpenClaw 使用。
- `vmAdminUser` 仍默认 `azureuser`；`vmAdminPassword` 变为必填 Secure 参数（没有默认值），部署时务必传入强密码，例如通过 `--parameters vmAdminPassword="$(az keyvault secret show …)"`。

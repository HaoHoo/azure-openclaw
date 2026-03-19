targetScope = 'resourceGroup'

// ============================================================
// Parameters – every value has an AZD-friendly default that
// the user can override in main.parameters.json or via
// `azd env set <VAR> <VALUE>` before running `azd up`.
// ============================================================

@description('Azure region for all resources.')
param location string = 'eastus'

@description('Prefix for all resource names (VM, VNet, NSG, etc.).')
param openclawName string = 'azure-openclaw'


@description('Virtual machine name.')
param vmName string = toLower('${openclawName}-vm')

@description('VM size. Standard_B1ms = 2 vCPU / 2 GB RAM (default). Standard_B2s = 2 vCPU / 4 GB RAM.')
@allowed([
  'Standard_B1ms'
  'Standard_B2s'
])
param vmSize string = 'Standard_B1ms'

@description('Virtual network name.')
param vnetName string = toLower('${openclawName}-vnet')

@description('Public IP address resource name.')
param publicIpName string = toLower('${openclawName}-publicip')

@description('Azure AI Foundry Hub name.')
param foundryName string = toLower('${openclawName}-foundry')

@description('Azure OpenAI model name (must be available in the target region).')
param modelName string = 'gpt-4o'

@description('TCP port that OpenClaw listens on. Opened in the VM Network Security Group.')
param openclawPort int = 18789

@description('VM administrator username.')
param adminUsername string = 'azureuser'

@description('VM administrator password (if not using SSH key authentication). Must meet Azure complexity requirements.')
@secure()
param adminPassword string

@description('是否在部署时使用 Spot 虚拟机（默认 false）。')
param spotVM bool = false

@description('Spot VM 的最大价格（美元）。-1 表示使用市场默认价。')
param spotMaxPrice int = -1

@description('是否为 Public IP 使用动态分配（默认 false）。')
param dynaIP bool = false
@description('Git URL containing the helper scripts deployed to the VM.')
param scriptsRepoUrl string = 'https://github.com/HaoHoo/azure-openclaw.git'
@description('Git ref or branch to check out when cloning the helper scripts repo.')
param scriptsRepoRef string = 'main'


// ============================================================
// All Azure Resources (network, VM, AI Foundry, OpenAI)
// ============================================================

module resources './resources.bicep' = {
  name: 'openclaw-resources'
  params: {
    location: location
    vmName: vmName
    vmSize: vmSize
    vnetName: vnetName
    publicIpName: publicIpName
    foundryName: foundryName
    modelName: modelName
    openclawPort: openclawPort
    adminUsername: adminUsername
    adminPassword: adminPassword
    openclawName: openclawName
    spotVM: spotVM
    spotMaxPrice: spotMaxPrice
    dynaIP: dynaIP
    scriptsRepoUrl: scriptsRepoUrl
    scriptsRepoRef: scriptsRepoRef
  }
}

// ============================================================
// Outputs – consumed by AZD and passed to application config
// ============================================================

output AZURE_OPENCLAW_PUBLICIP string = resources.outputs.publicIpAddress
output AZURE_OPENCLAW_PORT int = resources.outputs.openclawPort
output AZURE_OPENAI_MODEL string = resources.outputs.modelName
output AZURE_OPENAI_ENDPOINT string = resources.outputs.openaiEndpoint
@secure()
output AZURE_OPENAI_APIKEY string = resources.outputs.openaiApiKey

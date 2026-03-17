targetScope = 'subscription'

// ============================================================
// Parameters – every value has an AZD-friendly default that
// the user can override in main.parameters.json or via
// `azd env set <VAR> <VALUE>` before running `azd up`.
// ============================================================

@description('Azure region for all resources.')
param location string = 'eastus'

@description('Resource group name.')
param resourceGroupName string = 'azure-openclaw-rg'

@description('Virtual machine name.')
param vmName string = 'azure-openclaw-vm'

@description('VM size. Standard_B1ms = 2 vCPU / 2 GB RAM (default). Standard_B2s = 2 vCPU / 4 GB RAM.')
@allowed([
  'Standard_B1ms'
  'Standard_B2s'
])
param vmSize string = 'Standard_B1ms'

@description('Virtual network name.')
param vnetName string = 'azure-openclaw-vnet'

@description('Public IP address resource name.')
param publicIpName string = 'azure-openclaw-publicip'

@description('Azure AI Foundry Hub name.')
param foundryName string = 'azure-openclaw-foundry'

@description('Azure OpenAI model name (must be available in the target region).')
param modelName string = 'gpt-5.2-chat'

@description('Azure OpenAI deployment name (used as the model alias inside the service).')
param modelDeploymentName string = 'openclaw-model'

@description('TCP port that OpenClaw listens on. Opened in the VM Network Security Group.')
param openclawPort int = 11434

@description('VM administrator username.')
param adminUsername string = 'azureuser'

@description('SSH public key for the VM administrator account (RSA, base64-encoded).')
@secure()
param adminSshPublicKey string

// ============================================================
// Resource Group
// ============================================================

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

// ============================================================
// All Azure Resources (network, VM, AI Foundry, OpenAI)
// ============================================================

module resources './all-resources.bicep' = {
  scope: rg
  name: 'openclaw-resources'
  params: {
    location: location
    vmName: vmName
    vmSize: vmSize
    vnetName: vnetName
    publicIpName: publicIpName
    foundryName: foundryName
    modelName: modelName
    modelDeploymentName: modelDeploymentName
    openclawPort: openclawPort
    adminUsername: adminUsername
    adminSshPublicKey: adminSshPublicKey
  }
}

// ============================================================
// Outputs – consumed by AZD and passed to application config
// ============================================================

output AZURE_OPENCLAW_PUBLICIP string = resources.outputs.publicIpAddress
output AZURE_OPENAI_ENDPOINT string = resources.outputs.openaiEndpoint

@secure()
output AZURE_OPENAI_APIKEY string = resources.outputs.openaiApiKey

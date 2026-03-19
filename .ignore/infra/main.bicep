// 在订阅级别运行，以创建资源组等
targetScope = 'subscription'

// 主要参数定义
param location string = 'eastus'
param resourcesNamePrefix string = 'azure-openclaw'
param resourceGroupName string = '${resourcesNamePrefix}-rg'
@allowed([ 'Standard_B1ms', 'Standard_B2s' ])
param vmSize string = 'Standard_B1ms'
param aiFoundryName string = '${resourcesNamePrefix}-foundry'
@description('默认 gpt-5.2-chat, 可自行选择。')
param modelName string = 'gpt-5.2-chat'
param openclawPort int = 3000
param vmAdminUser string = 'azureuser'
@secure()
param vmAdminPassword string
param useSpot bool = false
param spotMaxPrice int = -1

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module resources './resource.bicep' = {
  name: 'openclaw-resources'
  scope: rg
  params: {
    location: location
    resourcesNamePrefix: resourcesNamePrefix
    vmSize: vmSize
    aiFoundryName: aiFoundryName
    modelName: modelName
    openclawPort: openclawPort
    vmAdminUser: vmAdminUser
    vmAdminPassword: vmAdminPassword
    useSpot: useSpot
    spotMaxPrice: spotMaxPrice
  }
}

output AZURE_OPENCLAW_PUBLICIP string = resources.outputs.publicIP
output AZURE_OPENAI_ENDPOINT string = resources.outputs.aiEndpoint
output AZURE_OPENAI_APIKEY string = resources.outputs.aiKey
output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_VM_NAME string = '${resourcesNamePrefix}-vm'
output AZURE_OPENAI_MODEL string = modelName
output AZURE_VM_ADMINUSER string = vmAdminUser
output AZURE_OPENCLAW_PORT int = openclawPort

using 'main.bicep'

param adminPassword = 'openclaw@AZURE!'

param adminUsername = 'azureuser'

param dynaIP = false

param foundryName = 'azure-openclaw-foundry'

param location = 'eastus'

param modelName = 'gpt-4o'

param openclawName = 'azure-openclaw'

param openclawPort = 18789

param publicIpName = 'azure-openclaw-publicip'

param scriptsRepoRef = 'main'

param scriptsRepoUrl = 'https://github.com/HaoHoo/azure-openclaw.git'

param spotMaxPrice = -1

param spotVM = false

param vmName = 'azure-openclaw-vm'

param vmSize = 'Standard_B1ms'

param vnetName = 'azure-openclaw-vnet'

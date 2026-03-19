// all-resources.bicep – resource-group scope
// Deploys: networking, VM (with cloud-init), AI Foundry Hub,
//          Azure OpenAI account, model deployment, and the
//          Custom Script Extension that installs/configures OpenClaw.

// ============================================================
// Parameters (forwarded from main.bicep)
// ============================================================

param location string
param vmName string
param vmSize string
param vnetName string
param publicIpName string
param foundryName string
param modelName string
param modelDeploymentName string
param openclawPort int
param adminUsername string

@secure()
param adminSshPublicKey string

// ============================================================
// Derived / local names
// ============================================================

var nsgName            = '${vmName}-nsg'
var subnetName         = 'default'
var nicName            = '${vmName}-nic'

// Storage account names: 3-24 chars, lowercase letters + numbers only
var storageAccountName = take('st${uniqueString(resourceGroup().id)}', 24)

// Key Vault names: 3-24 chars, alphanumeric + hyphens, must start with letter
var keyVaultName       = take('kv${uniqueString(resourceGroup().id)}', 24)

// Azure OpenAI account name and custom subdomain (globally unique, ≤ 24 chars)
var openAIName         = take('oai${uniqueString(resourceGroup().id, foundryName)}', 24)

// ============================================================
// NETWORKING
// ============================================================

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-ssh'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Allow inbound SSH for VM management'
        }
      }
      {
        name: 'allow-openclaw'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: string(openclawPort)
          description: 'Allow inbound traffic on the OpenClaw service port'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower(replace(vmName, '_', '-'))
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// ============================================================
// AI FOUNDRY SUPPORT RESOURCES
// ============================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================
// AI FOUNDRY HUB
// ============================================================

resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: foundryName
  location: location
  kind: 'Hub'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    friendlyName: foundryName
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    hbiWorkspace: false
  }
}

// ============================================================
// AZURE OPENAI ACCOUNT + MODEL DEPLOYMENT
// ============================================================

resource openAI 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAIName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    // customSubDomainName forms the service endpoint:
    // https://<customSubDomainName>.openai.azure.com/
    customSubDomainName: openAIName
    publicNetworkAccess: 'Enabled'
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAI
  name: modelDeploymentName
  sku: {
    // Standard throughput; capacity is in thousands of tokens per minute.
    // NOTE: update 'modelName' parameter to a model available in your region
    // (e.g. 'gpt-4o'). 'gpt-5.2-chat' is the requested default.
    name: 'Standard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
    }
  }
}

// Retrieve the OpenAI service key at deployment time (stays in protectedSettings)
var openaiEndpoint = 'https://${openAIName}.openai.azure.com/'
var openaiApiKey   = openAI.listKeys().key1

// ============================================================
// VIRTUAL MACHINE
// ============================================================

// The cloud-init YAML is base64-encoded and placed in customData.
// On first boot, the cloud agent installs Node.js 22, Python 3, and Git.
var cloudInitContent = loadTextContent('../scripts/cloud-init.yml')

// Build the Custom Script Extension payload:
// A header that exports the OpenAI credentials is prepended to the
// configure-openclaw.sh body so the script can read them as env vars.
// NOTE: \'  is used to produce a literal single quote inside the shell export statement.
var configScriptHeader = '#!/bin/bash\nset -euo pipefail\n\nexport AZURE_OPENAI_ENDPOINT=\'${openaiEndpoint}\'\nexport AZURE_OPENAI_APIKEY=\'${openaiApiKey}\'\n\n'
var configScriptBody   = loadTextContent('../scripts/configure-openclaw.sh')
var configScriptFull   = '${configScriptHeader}${configScriptBody}'

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      // Injects cloud-init instructions to pre-install Node.js 22, Python, Git
      customData: base64(cloudInitContent)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// ============================================================
// CUSTOM SCRIPT EXTENSION
// Runs after VM provisioning. Installs OpenClaw and writes the
// Azure OpenAI endpoint + API key to the runtime environment.
// protectedSettings keeps secrets out of the activity log.
// ============================================================

resource vmCustomScript 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: vm
  name: 'configure-openclaw'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      // base64-encoded full script (header with injected values + configure-openclaw.sh body)
      script: base64(configScriptFull)
    }
  }
}

// ============================================================
// OUTPUTS
// ============================================================

output publicIpAddress string = publicIp.properties.ipAddress
output openaiEndpoint  string = openaiEndpoint

@secure()
output openaiApiKey    string = openaiApiKey

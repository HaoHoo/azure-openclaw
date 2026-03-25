// all-resources.bicep – resource-group scope
// Deploys: networking, VM (with cloud-init), AI Foundry Hub,
//          Azure OpenAI account, model deployment, and the
//          Custom Script Extension that installs/configures OpenClaw.

// ============================================================
// Parameters (forwarded from main.bicep)
// ============================================================

param location string
param openclawName string
//param resourceGroupName string
param vmName string = '${openclawName}-vm'
param vmSize string
param vnetName string = '${openclawName}-vnet'
param publicIpName string = '${openclawName}-publicip'
param foundryName string = '${openclawName}-foundry'
param modelName string
param modelDeploymentName string = modelName
param openclawPort int
param adminUsername string
@secure()
param adminPassword string
param spotVM bool = false
param spotMaxPrice int = -1
param dynaIP bool = false
@description('Git URL containing the helper scripts deployed to the VM.')
param scriptsRepoUrl string = 'https://github.com/HaoHoo/azure-opencalw.git'
@description('Git ref or branch used when cloning the helper scripts repo.')
param scriptsRepoRef string = 'main'

// ============================================================
// Derived / local names
// ============================================================

var nsgName            = '${vmName}-nsg'
var subnetName         = 'default'
var nicName            = '${vmName}-nic'

// Names must follow openclawName + resource abbreviation, respecting service constraints.
var compactName        = replace(toLower(openclawName), '-', '')

var infraDir          = '/home/${adminUsername}/infra'
var resourceGroupName = resourceGroup().name

// Storage accounts (lowercase letters and digits only, 3-24 chars). Hyphens not allowed.
var storageAccountName = take('${compactName}st${uniqueString(resourceGroup().id, 'st')}', 24)

// Key Vault names allow hyphens and must begin with a letter.
var keyVaultName       = take('${compactName}-kv${uniqueString(resourceGroup().id, 'kv')}', 24)

// Azure OpenAI account names are globally unique (≤ 24 chars).
var openAIName         = take('${compactName}oai${uniqueString(resourceGroup().id, 'oai')}', 24)

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
    publicIPAllocationMethod: dynaIP ? 'Dynamic' : 'Static'
    dnsSettings: !dynaIP ? {
      domainNameLabel: toLower(replace(vmName, '_', '-'))
    } : null
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
var cloudInitTemplate = '''
#cloud-config
# Pre-install Node.js 22, Python 3, Azure CLI, and Git on first boot.
# This content is base64-encoded and passed via osProfile.customData.

package_update: true
package_upgrade: false

packages:
  - git
  - python3
  - python3-pip
  - curl
  - jq

runcmd:
  # Install Node.js 22 from the official NodeSource repository
  - curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  - apt-get install -y nodejs
  - node --version
  - npm --version
  - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  - az version
'''
var cloudInitContent = replace(cloudInitTemplate, '__ADMIN_USERNAME__', adminUsername)

// Build the Custom Script Extension payload:
// A header that exports the OpenAI credentials is prepended to the
// configure-openclaw.sh body so the script can read them as env vars.
// NOTE: \'  is used to produce a literal single quote inside the shell export statement.
var configScriptHeader = '''#!/bin/bash
set -euo pipefail

export HOME='/home/${adminUsername}'
export AZURE_OPENAI_ENDPOINT='${openaiEndpoint}'
export AZURE_OPENAI_APIKEY='${openaiApiKey}'
export AZURE_OPENAI_ACCOUNT_NAME='${openAIName}'
export AZURE_RESOURCE_GROUP_NAME='${resourceGroupName}'
export AZURE_REGION='${location}'
export AZURE_MODEL_NAME='${modelName}'
export AZURE_OPENAI_MODEL='${modelName}'
export AZURE_MODEL_DEPLOYMENT_NAME='${modelDeploymentName}'
export AZURE_OPENAI_RESOURCE_GROUP='${resourceGroupName}'
export AZURE_OPENCLAW_PORT='${openclawPort}'
export AZURE_INFRA_DIR='${infraDir}'
export AZURE_RESOURCE_JSON_PATH='${infraDir}/resource.json'
export AZURE_DNS_JSON_PATH='${infraDir}/dns.json'
export AZURE_DYNAMIC_IP='${dynaIP}'
export AZURE_ADMIN_USERNAME='${adminUsername}'
export AZURE_SCRIPTS_REPO_URL='${scriptsRepoUrl}'
export AZURE_SCRIPTS_REPO_REF='${scriptsRepoRef}'

'''
var configScriptBody        = loadTextContent('../scripts/set-openclaw.sh')
var configScriptTail   = ''
var configScriptFull   = '${configScriptHeader}${configScriptBody}${configScriptTail}'

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    priority: spotVM ? 'Spot' : 'Regular'
    evictionPolicy: spotVM ? 'Deallocate' : null
    billingProfile: spotVM ? {
      maxPrice: spotMaxPrice
    } : null
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
      adminPassword: adminPassword
      // Injects cloud-init instructions to pre-install Node.js 22, Python, Git
      customData: base64(cloudInitContent)
      linuxConfiguration: {
        disablePasswordAuthentication: false
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
  name: 'set-openclaw'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      // base64-encoded full script (header with injected values + set-openclaw.sh body)
      script: base64(configScriptFull)
    }
  }
}

// ============================================================
// OUTPUTS
// ============================================================

output publicIpAddress string = publicIp.properties.ipAddress
output openclawPort int = openclawPort
output modelName string = modelName
output openaiEndpoint  string = openaiEndpoint
@secure()
output openaiApiKey    string = openaiApiKey

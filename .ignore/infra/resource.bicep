param location string
param resourcesNamePrefix string
param vmSize string
param aiFoundryName string
param modelName string
param openclawPort int
param vmAdminUser string
@secure()
param vmAdminPassword string
param useSpot bool
param spotMaxPrice int

var vnetName = '${resourcesNamePrefix}-vnet'
var subnetName = 'default'
var nsgName = '${resourcesNamePrefix}-nsg'
var publicIpName = '${resourcesNamePrefix}-publicip'
var nicName = '${resourcesNamePrefix}-nic'
var subnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
var configureScriptBase64 = base64(loadTextContent('../scripts/set-openclaw.sh'))

var cloudInit = '''
#cloud-config
package_update: true
packages:
  - git
  - python3
  - python3-pip
  - curl
runcmd:
  - curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  - DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
  - curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
  - systemctl enable --now openclaw
'''

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: 22
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'SSH access for maintenance'
        }
      }
      {
        name: 'AllowOpenClaw'
        properties: {
          priority: 1010
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: openclawPort
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'OpenClaw web console'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.1.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
  dependsOn: [
    nsg
  ]
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-07-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: '${resourcesNamePrefix}-vm'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    priority: if (useSpot) 'Spot' else 'Regular'
    evictionPolicy: if (useSpot) 'Deallocate' else null
    billingProfile: if (useSpot) {
      maxPrice: spotMaxPrice
    } else null
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 64
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: '${resourcesNamePrefix}-vm'
      adminUsername: vmAdminUser
      adminPassword: vmAdminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
      customData: base64(cloudInit)
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
  dependsOn: [
    nic
  ]
}

resource aiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: aiFoundryName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

var aiEndpoint = aiAccount.properties.endpoint
var aiKey = listKeys(aiAccount.id, '2023-05-01').key1
var configureCommand = '''
bash -lc "echo ${configureScriptBase64} | base64 -d >/tmp/set-openclaw.sh && chmod +x /tmp/set-openclaw.sh && AZURE_OPENAI_ENDPOINT='${aiEndpoint}' AZURE_OPENAI_APIKEY='${aiKey}' AZURE_OPENAI_MODEL='${modelName}' bash /tmp/set-openclaw.sh"
'''

resource configureExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  name: '${resourcesNamePrefix}-vm/set-openclaw'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: configureCommand
    }
  }
  dependsOn: [
    vm
    aiAccount
  ]
}

output publicIP string = publicIp.properties.ipAddress
output aiEndpoint string = aiAccount.properties.endpoint
output aiKey string = aiKey

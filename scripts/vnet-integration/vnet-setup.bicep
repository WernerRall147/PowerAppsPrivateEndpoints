// Bicep template for deploying VNet and subnet for Power Platform VNet Integration
// This template creates:
// - Azure VNet
// - Subnet for Power Platform delegation
// - Network Security Group with appropriate rules
// - Optional peering with existing VNets

@description('Name of the virtual network for Power Platform integration')
param vnetName string

@description('Location for the resources')
param location string = resourceGroup().location

@description('Address space for the VNet (CIDR notation)')
param vnetAddressSpace string = '10.0.0.0/16'

@description('Name of the subnet for Power Platform delegation')
param powerPlatformSubnetName string = 'subnet-powerplatform'

@description('Address range for the Power Platform subnet (CIDR notation, at least /24 recommended)')
param powerPlatformSubnetAddressRange string = '10.0.0.0/24'

@description('Optional existing VNet to peer with (leave empty if not needed)')
param existingVnetToConnect string = ''

@description('Optional resource group of existing VNet (leave empty if not needed)')
param existingVnetResourceGroup string = resourceGroup().name

// Create Network Security Group for Power Platform subnet
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: '${powerPlatformSubnetName}-nsg'
  location: location
  properties: {
    securityRules: [
      // Allow outbound to Azure SQL
      {
        name: 'AllowSQLOutbound'
        properties: {
          direction: 'Outbound'
          access: 'Allow'
          priority: 100
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Sql'
          destinationPortRange: '1433'
        }
      }
      // Allow outbound to Azure Storage
      {
        name: 'AllowStorageOutbound'
        properties: {
          direction: 'Outbound'
          access: 'Allow'
          priority: 110
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Storage'
          destinationPortRange: '443'
        }
      }
      // Allow outbound to Azure KeyVault
      {
        name: 'AllowKeyVaultOutbound'
        properties: {
          direction: 'Outbound'
          access: 'Allow'
          priority: 120
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureKeyVault'
          destinationPortRange: '443'
        }
      }
      // Allow outbound to Azure Service Bus
      {
        name: 'AllowServiceBusOutbound'
        properties: {
          direction: 'Outbound'
          access: 'Allow'
          priority: 130
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'ServiceBus'
          destinationPortRange: '443'
        }
      }
      // Allow outbound to Azure AD
      {
        name: 'AllowAADOutbound'
        properties: {
          direction: 'Outbound'
          access: 'Allow'
          priority: 140
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureActiveDirectory'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

// Create the virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: powerPlatformSubnetName
        properties: {
          addressPrefix: powerPlatformSubnetAddressRange
          networkSecurityGroup: {
            id: nsg.id
          }
          delegations: [
            {
              name: 'PowerPlatformDelegation'
              properties: {
                serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
              }
            }
          ]
        }
      }
    ]
  }
}

// Create peering with existing VNet if specified
resource vnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = if (!empty(existingVnetToConnect)) {
  name: '${vnetName}/peering-to-${existingVnetToConnect}'
  dependsOn: [
    vnet
  ]
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: resourceId(existingVnetResourceGroup, 'Microsoft.Network/virtualNetworks', existingVnetToConnect)
    }
  }
}

// Output information
output vnetId string = vnet.id
output vnetName string = vnet.name
output powerPlatformSubnetId string = '${vnet.id}/subnets/${powerPlatformSubnetName}'
output powerPlatformSubnetName string = powerPlatformSubnetName

// Bicep template for deploying Azure SQL Server with private endpoint connectivity
// This template creates:
// - Azure SQL Server
// - Sample database
// - Private Endpoint
// - Private DNS Zone for SQL

@description('Name of the SQL Server')
param sqlServerName string

@description('Location for the SQL Server')
param location string = resourceGroup().location

@description('SQL Server administrator login name')
param administratorLogin string

@description('SQL Server administrator password')
@secure()
param administratorPassword string

@description('Virtual network name where private endpoint will be created')
param vnetName string

@description('Subnet name for private endpoint')
param subnetName string

@description('Resource group of the VNet')
param vnetResourceGroup string = resourceGroup().name

@description('Name of the sample database')
param databaseName string = 'SampleDB'

// Get reference to subnet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  name: '${vnetName}/${subnetName}'
  scope: resourceGroup(vnetResourceGroup)
}

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2021-08-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    publicNetworkAccess: 'Disabled'
    minimalTlsVersion: '1.2'
  }
}

// Sample database
resource database 'Microsoft.Sql/servers/databases@2021-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
}

// Private Endpoint
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-02-01' = {
  name: '${sqlServerName}-endpoint'
  location: location
  properties: {
    subnet: {
      id: subnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${sqlServerName}-connection'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.database.windows.net'
  location: 'global'
}

// Link Private DNS Zone to VNet
resource dnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: resourceId(vnetResourceGroup, 'Microsoft.Network/virtualNetworks', vnetName)
    }
  }
}

// DNS Zone Group for Private Endpoint
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-02-01' = {
  parent: privateEndpoint
  name: 'dnsgroupname'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// Output the SQL Server name and private endpoint information
output sqlServerName string = sqlServer.name
output sqlServerFQDN string = sqlServer.properties.fullyQualifiedDomainName
output privateEndpointName string = privateEndpoint.name
output privateEndpointId string = privateEndpoint.id
output databaseName string = database.name

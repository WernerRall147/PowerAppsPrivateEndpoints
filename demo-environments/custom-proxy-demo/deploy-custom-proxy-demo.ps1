# Main deployment script for Custom Proxy demo environment
# This script deploys all resources needed for the Custom Proxy approach

<#
.SYNOPSIS
    Deploys the complete Custom Proxy demo environment
.DESCRIPTION
    This script:
    1. Creates a resource group
    2. Deploys a VNet with subnet for Azure Functions
    3. Creates Azure resources with private endpoints (SQL, Blob)
    4. Deploys Azure Functions with VNet integration
    5. Deploys API Management to expose the Functions
    6. Configures everything for end-to-end testing
.PARAMETER ResourceGroupName
    Resource group for deployment
.PARAMETER Location
    Azure region for deployment
.PARAMETER FunctionAppName
    Name for the Azure Function App
.PARAMETER StorageAccountName
    Name for the Storage Account used by the Function App
.PARAMETER ApimName
    Name for the API Management instance
.PARAMETER PublisherName
    Publisher name for API Management
.PARAMETER PublisherEmail
    Publisher email for API Management
.PARAMETER AdminUsername
    Admin username for SQL Server
.PARAMETER AdminPassword
    Admin password for SQL Server (secure string)
.EXAMPLE
    $securePassword = ConvertTo-SecureString "ComplexP@ssw0rd!" -AsPlainText -Force
    .\deploy-custom-proxy-demo.ps1 -ResourceGroupName "rg-powerplatform-proxy-demo" -FunctionAppName "func-powerplatform-proxy" -StorageAccountName "stpowerplatformproxy" -ApimName "apim-powerplatform-proxy" -PublisherName "Contoso" -PublisherEmail "admin@contoso.com" -AdminUsername "sqladmin" -AdminPassword $securePassword
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$true)]
    [string]$FunctionAppName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$ApimName,
    
    [Parameter(Mandatory=$true)]
    [string]$PublisherName,
    
    [Parameter(Mandatory=$true)]
    [string]$PublisherEmail,
    
    [Parameter(Mandatory=$true)]
    [string]$AdminUsername,
    
    [Parameter(Mandatory=$true)]
    [SecureString]$AdminPassword
)

# Variables
$vnetName = "$ResourceGroupName-vnet"
$vnetAddressSpace = "10.0.0.0/16"
$functionsSubnetName = "FunctionsSubnet"
$functionsSubnetAddressSpace = "10.0.1.0/24"
$apimSubnetName = "ApiManagementSubnet"
$apimSubnetAddressSpace = "10.0.2.0/24"
$resourcesSubnetName = "ResourcesSubnet"
$resourcesSubnetAddressSpace = "10.0.3.0/24"
$sqlServerName = "$ResourceGroupName-sql".ToLower().Replace("-", "")
$databaseName = "DemoDatabase"
$blobStorageAccountName = "$ResourceGroupName-blob".ToLower().Replace("-", "").Substring(0, [System.Math]::Min(24, "$ResourceGroupName-blob".Length))
$containerName = "democontainer"

# Check if Azure PowerShell module is installed
if (!(Get-Module -ListAvailable Az.*)) {
    Write-Host "Azure PowerShell module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
}

# Connect to Azure (if not already connected)
try {
    $context = Get-AzContext
    if (!$context) {
        Connect-AzAccount
    }
}
catch {
    Connect-AzAccount
}

# Create resource group
Write-Host "Creating resource group $ResourceGroupName..." -ForegroundColor Green
$rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force

# Create VNet and subnets
Write-Host "Creating VNet and subnets..." -ForegroundColor Green
$functionsSubnet = New-AzVirtualNetworkSubnetConfig -Name $functionsSubnetName -AddressPrefix $functionsSubnetAddressSpace
$apimSubnet = New-AzVirtualNetworkSubnetConfig -Name $apimSubnetName -AddressPrefix $apimSubnetAddressSpace
$resourcesSubnet = New-AzVirtualNetworkSubnetConfig -Name $resourcesSubnetName -AddressPrefix $resourcesSubnetAddressSpace

$vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix $vnetAddressSpace -Subnet $functionsSubnet, $apimSubnet, $resourcesSubnet

# Deploy SQL Server with private endpoint
Write-Host "Deploying Azure SQL with private endpoint..." -ForegroundColor Green
$sqlAdminPasswordPlain = ConvertFrom-SecureString -SecureString $AdminPassword -AsPlainText

# Create SQL Server
$sqlServer = New-AzSqlServer -ResourceGroupName $ResourceGroupName `
    -ServerName $sqlServerName `
    -Location $Location `
    -SqlAdministratorCredentials (New-Object System.Management.Automation.PSCredential($AdminUsername, $AdminPassword))

# Create SQL Database
$sqlDb = New-AzSqlDatabase -ResourceGroupName $ResourceGroupName `
    -ServerName $sqlServerName `
    -DatabaseName $databaseName `
    -Edition "Basic" `
    -RequestedServiceObjectiveName "Basic"

# Disable public access to SQL Server
Set-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $sqlServerName -PublicNetworkAccess "Disabled"

# Create private endpoint for SQL Server
$resourcesSubnetObj = $vnet.Subnets | Where-Object { $_.Name -eq $resourcesSubnetName }

$privateEndpointName = "$sqlServerName-endpoint"
$privateLinkServiceConnection = New-AzPrivateLinkServiceConnection `
    -Name "$sqlServerName-connection" `
    -PrivateLinkServiceId $sqlServer.ResourceId `
    -GroupId "sqlServer"

New-AzPrivateEndpoint `
    -ResourceGroupName $ResourceGroupName `
    -Name $privateEndpointName `
    -Location $Location `
    -Subnet $resourcesSubnetObj `
    -PrivateLinkServiceConnection $privateLinkServiceConnection

# Create Private DNS Zone for SQL
$privateDnsZoneName = "privatelink.database.windows.net"
$privateDnsZone = New-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $privateDnsZoneName

# Link the private DNS zone to the VNet
$dnsVnetLink = New-AzPrivateDnsVirtualNetworkLink `
    -ResourceGroupName $ResourceGroupName `
    -ZoneName $privateDnsZoneName `
    -Name "$vnetName-link" `
    -VirtualNetworkId $vnet.Id `
    -EnableRegistration $false

# Create Storage Account with private endpoint for Blob storage demo
Write-Host "Deploying Azure Storage with private endpoint..." -ForegroundColor Green
$blobStorageAccount = New-AzStorageAccount `
    -ResourceGroupName $ResourceGroupName `
    -Name $blobStorageAccountName `
    -Location $Location `
    -SkuName "Standard_LRS" `
    -Kind "StorageV2"

# Create container
$storageContext = $blobStorageAccount.Context
New-AzStorageContainer -Name $containerName -Context $storageContext -Permission Off

# Disable public network access for storage account
$blobStorageAccount.PublicNetworkAccess = "Disabled"
$blobStorageAccount | Set-AzStorageAccount

# Create private endpoint for blob storage
$blobPrivateEndpointName = "$blobStorageAccountName-blob-endpoint"
$blobPrivateLinkServiceConnection = New-AzPrivateLinkServiceConnection `
    -Name "$blobStorageAccountName-blob-connection" `
    -PrivateLinkServiceId $blobStorageAccount.Id `
    -GroupId "blob"

New-AzPrivateEndpoint `
    -ResourceGroupName $ResourceGroupName `
    -Name $blobPrivateEndpointName `
    -Location $Location `
    -Subnet $resourcesSubnetObj `
    -PrivateLinkServiceConnection $blobPrivateLinkServiceConnection

# Create Private DNS Zone for Blob Storage
$blobPrivateDnsZoneName = "privatelink.blob.core.windows.net"
$blobPrivateDnsZone = New-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $blobPrivateDnsZoneName

# Link the private DNS zone to the VNet
$blobDnsVnetLink = New-AzPrivateDnsVirtualNetworkLink `
    -ResourceGroupName $ResourceGroupName `
    -ZoneName $blobPrivateDnsZoneName `
    -Name "$vnetName-blob-link" `
    -VirtualNetworkId $vnet.Id `
    -EnableRegistration $false

# Deploy the Custom Proxy infrastructure (Azure Functions and API Management)
Write-Host "Deploying custom proxy infrastructure..." -ForegroundColor Green
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentDir = Split-Path -Parent $scriptDir
$customProxyScriptFile = Join-Path $parentDir "..\scripts\custom-proxy\deploy-custom-proxy.ps1"

# Check if the deployment script exists
if (!(Test-Path $customProxyScriptFile)) {
    Write-Error "Custom proxy deployment script file not found at: $customProxyScriptFile"
    exit
}

# Execute the custom proxy deployment script
$customProxyParams = @{
    ResourceGroupName = $ResourceGroupName
    Location = $Location
    FunctionAppName = $FunctionAppName
    StorageAccountName = $StorageAccountName
    ApimName = $ApimName
    PublisherName = $PublisherName
    PublisherEmail = $PublisherEmail
    VNetName = $vnetName
    SubnetName = $functionsSubnetName
    SqlServerName = $sqlServerName
    DatabaseName = $databaseName
    BlobStorageAccountName = $blobStorageAccountName
}

& $customProxyScriptFile @customProxyParams

# Output information for next steps
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "Custom Proxy Demo Environment Deployed" -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "SQL Server: $sqlServerName.database.windows.net (private endpoint)" -ForegroundColor Yellow
Write-Host "Database: $databaseName" -ForegroundColor Yellow
Write-Host "Blob Storage: $blobStorageAccountName.blob.core.windows.net (private endpoint)" -ForegroundColor Yellow
Write-Host "Function App: $FunctionAppName.azurewebsites.net" -ForegroundColor Yellow
Write-Host "API Management: $ApimName.azure-api.net" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Green
Write-Host "1. Import the custom connector definition from the connector-definitions folder into Power Platform"
Write-Host "2. Configure authentication for the connector"
Write-Host "3. Create a connection to the proxy in Power Apps/Power Automate"
Write-Host "4. Test connectivity to private resources through the proxy"
Write-Host "==========================================================================" -ForegroundColor Cyan

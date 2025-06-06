# Main deployment script for VNet Integration demo environment
# This script deploys all resources needed for the Power Platform VNet Integration approach

<#
.SYNOPSIS
    Deploys the complete VNet Integration demo environment
.DESCRIPTION
    This script:
    1. Creates a resource group
    2. Deploys a VNet with subnet for Power Platform delegation
    3. Creates Azure resources with private endpoints (SQL, Blob)
    4. Configures DNS and networking
    5. Sets up Power Platform VNet Integration
.PARAMETER ResourceGroupName
    Resource group for deployment
.PARAMETER Location
    Azure region for deployment
.PARAMETER PowerPlatformEnvironmentId
    ID of your Power Platform environment (must be a Managed Environment)
.PARAMETER AdminUsername
    Admin username for SQL Server
.PARAMETER AdminPassword
    Admin password for SQL Server (secure string)
.EXAMPLE
    $securePassword = ConvertTo-SecureString "ComplexP@ssw0rd!" -AsPlainText -Force
    .\deploy-vnet-integration-demo.ps1 -ResourceGroupName "rg-powerplatform-vnet-demo" -PowerPlatformEnvironmentId "/providers/Microsoft.PowerPlatform/environments/12345678-1234-1234-1234-123456789012" -AdminUsername "sqladmin" -AdminPassword $securePassword
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$true)]
    [string]$PowerPlatformEnvironmentId,
    
    [Parameter(Mandatory=$true)]
    [string]$AdminUsername,
    
    [Parameter(Mandatory=$true)]
    [SecureString]$AdminPassword
)

# Variables
$vnetName = "$ResourceGroupName-vnet"
$subnetName = "PowerPlatformSubnet"
$sqlServerName = "$ResourceGroupName-sql".ToLower().Replace("-", "")
$databaseName = "DemoDatabase"
$storageAccountName = "$ResourceGroupName".ToLower().Replace("-", "").Substring(0, [System.Math]::Min(24, "$ResourceGroupName".Length))
$containerName = "democontainer"

# Check if Az PowerShell modules are installed
if (!(Get-Module -ListAvailable Az.*)) {
    Write-Host "Azure PowerShell module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force
}

# Check for Power Platform module
if (!(Get-Module -ListAvailable Az.PowerPlatform)) {
    Write-Host "Azure PowerShell PowerPlatform module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Az.PowerPlatform -AllowClobber -Scope CurrentUser -Force
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

# Deploy VNet and subnet for Power Platform
Write-Host "Deploying VNet for Power Platform integration..." -ForegroundColor Green
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentDir = Split-Path -Parent $scriptDir
$vnetTemplateFile = Join-Path $parentDir "..\scripts\vnet-integration\vnet-setup.bicep"

# Check if the VNet template exists
if (!(Test-Path $vnetTemplateFile)) {
    Write-Error "VNet template file not found at: $vnetTemplateFile"
    exit
}

# Deploy VNet with subnet delegation for Power Platform
$vnetParams = @{
    vnetName = $vnetName
    location = $Location
    powerPlatformSubnetName = $subnetName
}

$vnetDeployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $vnetTemplateFile -TemplateParameterObject $vnetParams

# Deploy SQL Server with private endpoint
Write-Host "Deploying Azure SQL with private endpoint..." -ForegroundColor Green
$sqlAdminPasswordPlain = ConvertFrom-SecureString -SecureString $AdminPassword -AsPlainText

# Create SQL Server with private endpoint
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
$vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName

$privateEndpointName = "$sqlServerName-endpoint"
$privateLinkServiceConnection = New-AzPrivateLinkServiceConnection `
    -Name "$sqlServerName-connection" `
    -PrivateLinkServiceId $sqlServer.ResourceId `
    -GroupId "sqlServer"

New-AzPrivateEndpoint `
    -ResourceGroupName $ResourceGroupName `
    -Name $privateEndpointName `
    -Location $Location `
    -Subnet $subnet `
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

# Create Storage Account with private endpoint
Write-Host "Deploying Azure Storage with private endpoint..." -ForegroundColor Green
$storageAccount = New-AzStorageAccount `
    -ResourceGroupName $ResourceGroupName `
    -Name $storageAccountName `
    -Location $Location `
    -SkuName "Standard_LRS" `
    -Kind "StorageV2"

# Create container
$storageContext = $storageAccount.Context
New-AzStorageContainer -Name $containerName -Context $storageContext -Permission Off

# Disable public network access for storage account
$storageAccount.PublicNetworkAccess = "Disabled"
$storageAccount | Set-AzStorageAccount

# Create private endpoint for blob storage
$blobPrivateEndpointName = "$storageAccountName-blob-endpoint"
$blobPrivateLinkServiceConnection = New-AzPrivateLinkServiceConnection `
    -Name "$storageAccountName-blob-connection" `
    -PrivateLinkServiceId $storageAccount.Id `
    -GroupId "blob"

New-AzPrivateEndpoint `
    -ResourceGroupName $ResourceGroupName `
    -Name $blobPrivateEndpointName `
    -Location $Location `
    -Subnet $subnet `
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

# Configure VNet integration for Power Platform
Write-Host "Configuring VNet integration for Power Platform..." -ForegroundColor Green
$configureVNetFile = Join-Path $parentDir "..\scripts\vnet-integration\configure-vnet-integration.ps1"

# Check if the configuration script exists
if (!(Test-Path $configureVNetFile)) {
    Write-Error "VNet integration configuration script file not found at: $configureVNetFile"
    exit
}

# Determine the subnet ID
$subnetId = $subnet.Id

# Execute the VNet integration configuration script
$vnetIntegrationParams = @{
    ResourceGroupName = $ResourceGroupName
    EnvironmentId = $PowerPlatformEnvironmentId
    VNetId = $vnet.Id
    SubnetId = $subnetId
}

& $configureVNetFile @vnetIntegrationParams

# Output information for next steps
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "VNet Integration Demo Environment Deployed" -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "SQL Server: $sqlServerName.database.windows.net (private endpoint)" -ForegroundColor Yellow
Write-Host "Database: $databaseName" -ForegroundColor Yellow
Write-Host "Storage Account: $storageAccountName (private endpoint)" -ForegroundColor Yellow
Write-Host "Container: $containerName" -ForegroundColor Yellow
Write-Host "VNet: $vnetName" -ForegroundColor Yellow
Write-Host "Subnet: $subnetName" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Green
Write-Host "1. Verify VNet integration in Power Platform admin center"
Write-Host "2. Create a connection in Power Apps/Power Automate directly to the resources"
Write-Host "   (No gateway is needed - traffic routes through VNet integration)"
Write-Host "3. Test connectivity to private endpoints through your Power Apps/Flows"
Write-Host "==========================================================================" -ForegroundColor Cyan

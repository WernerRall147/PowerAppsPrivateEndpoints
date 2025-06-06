# Main deployment script for Gateway demo environment
# This script deploys all resources needed for the On-Premises Data Gateway approach

<#
.SYNOPSIS
    Deploys the complete On-Premises Data Gateway demo environment
.DESCRIPTION
    This script:
    1. Creates a resource group
    2. Deploys an Azure SQL Database with private endpoint
    3. Creates a virtual network for resources
    4. Deploys a gateway VM in the same VNet
    5. Configures everything for end-to-end testing
.PARAMETER ResourceGroupName
    Resource group for deployment
.PARAMETER Location
    Azure region for deployment
.PARAMETER AdminUsername
    Admin username for the gateway VM
.PARAMETER AdminPassword
    Admin password for the gateway VM (secure string)
.EXAMPLE
    $securePassword = ConvertTo-SecureString "ComplexP@ssw0rd!" -AsPlainText -Force
    .\deploy-gateway-demo.ps1 -ResourceGroupName "rg-powerplatform-gateway-demo" -AdminUsername "vmadmin" -AdminPassword $securePassword
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$true)]
    [string]$AdminUsername,
    
    [Parameter(Mandatory=$true)]
    [SecureString]$AdminPassword
)

# Variables
$vnetName = "$ResourceGroupName-vnet"
$vnetAddressSpace = "10.0.0.0/16"
$subnetName = "GatewaySubnet"
$subnetAddressSpace = "10.0.1.0/24"
$sqlServerName = "$ResourceGroupName-sql".ToLower().Replace("-", "")
$databaseName = "DemoDatabase"
$vmName = "$ResourceGroupName-vm".ToLower().Replace("-", "")

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

# Create VNet and subnet for private endpoint and gateway
Write-Host "Creating VNet and subnet..." -ForegroundColor Green
$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressSpace
$vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix $vnetAddressSpace -Subnet $subnet

# Deploy Azure SQL with private endpoint
Write-Host "Deploying Azure SQL with private endpoint..." -ForegroundColor Green
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentDir = Split-Path -Parent $scriptDir
$sqlTemplateFile = Join-Path $parentDir "..\scripts\gateway-approach\sql-private-endpoint.bicep"

# Check if the SQL template exists
if (!(Test-Path $sqlTemplateFile)) {
    Write-Error "SQL template file not found at: $sqlTemplateFile"
    exit
}

# Deploy SQL with private endpoint
$sqlAdminPasswordPlain = ConvertFrom-SecureString -SecureString $AdminPassword -AsPlainText
$sqlParams = @{
    sqlServerName = $sqlServerName
    location = $Location
    administratorLogin = $AdminUsername
    administratorPassword = $sqlAdminPasswordPlain
    vnetName = $vnetName
    subnetName = $subnetName
    vnetResourceGroup = $ResourceGroupName
    databaseName = $databaseName
}

$sqlDeployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $sqlTemplateFile -TemplateParameterObject $sqlParams

# Deploy gateway VM
Write-Host "Deploying gateway VM..." -ForegroundColor Green
$gatewayScriptFile = Join-Path $parentDir "..\scripts\gateway-approach\deploy-gateway-vm.ps1"

# Check if the gateway script exists
if (!(Test-Path $gatewayScriptFile)) {
    Write-Error "Gateway script file not found at: $gatewayScriptFile"
    exit
}

# Execute the gateway VM deployment script
$gatewayParams = @{
    ResourceGroupName = $ResourceGroupName
    Location = $Location
    VNetName = $vnetName
    SubnetName = $subnetName
    VmName = $vmName
    AdminUsername = $AdminUsername
    AdminPassword = $AdminPassword
}

& $gatewayScriptFile @gatewayParams

# Configure gateway
Write-Host "Configuring on-premises data gateway..." -ForegroundColor Green
$configureGatewayFile = Join-Path $parentDir "..\scripts\gateway-approach\configure-gateway.ps1"

# Check if the configure script exists
if (!(Test-Path $configureGatewayFile)) {
    Write-Error "Configure gateway script file not found at: $configureGatewayFile"
    exit
}

# Output information for manual gateway registration
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "Gateway Demo Environment Deployed" -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "SQL Server: $sqlServerName.database.windows.net (available via private endpoint)" -ForegroundColor Yellow
Write-Host "Database: $databaseName" -ForegroundColor Yellow
Write-Host "Gateway VM: $vmName (RDP to this machine to install/configure gateway)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Green
Write-Host "1. RDP to the gateway VM using the credentials you provided"
Write-Host "2. Install the On-Premises Data Gateway using the configuration script:"
Write-Host "   & '$configureGatewayFile' -SqlServerName '$sqlServerName.database.windows.net' -DatabaseName '$databaseName'"
Write-Host "3. Register the gateway with your Power Platform environment"
Write-Host "4. Create a connection in Power Apps/Power Automate using the gateway"
Write-Host "==========================================================================" -ForegroundColor Cyan

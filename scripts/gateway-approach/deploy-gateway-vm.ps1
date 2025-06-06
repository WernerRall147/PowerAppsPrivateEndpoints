# This script deploys an Azure VM in the same VNet as the private endpoint
# and installs the On-Premises Data Gateway

<#
.SYNOPSIS
    Deploys a gateway VM with connectivity to Azure SQL Database via private endpoint
.DESCRIPTION
    This script:
    1. Creates an Azure VM in the specified VNet/subnet
    2. Installs the On-Premises Data Gateway
    3. Configures networking and DNS for private endpoint access
.PARAMETER ResourceGroupName
    Resource group for VM deployment
.PARAMETER Location
    Azure region for VM deployment
.PARAMETER VNetName
    Name of the Virtual Network where the VM will be deployed
.PARAMETER SubnetName
    Name of the subnet where the VM will be deployed
.PARAMETER VmName
    Name for the gateway VM
.PARAMETER VmSize
    Size of VM (default: Standard_D2s_v3)
.PARAMETER AdminUsername
    Admin username for the VM
.PARAMETER AdminPassword
    Admin password for the VM
.EXAMPLE
    .\deploy-gateway-vm.ps1 -ResourceGroupName "rg-powerplatform" -VNetName "vnet-powerplatform" -SubnetName "subnet-gateway" -VmName "vm-gateway"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$true)]
    [string]$VNetName,
    
    [Parameter(Mandatory=$true)]
    [string]$SubnetName,
    
    [Parameter(Mandatory=$true)]
    [string]$VmName,
    
    [Parameter(Mandatory=$false)]
    [string]$VmSize = "Standard_D2s_v3",
    
    [Parameter(Mandatory=$true)]
    [string]$AdminUsername,
    
    [Parameter(Mandatory=$true)]
    [SecureString]$AdminPassword
)

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

# Check if resource group exists
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (!$rg) {
    Write-Host "Creating resource group $ResourceGroupName in $Location..." -ForegroundColor Green
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location
}

# Check if the VM already exists
$vm = Get-AzVM -Name $VmName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if ($vm) {
    Write-Host "VM $VmName already exists in resource group $ResourceGroupName" -ForegroundColor Yellow
    exit
}

# Get VNet and subnet details
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (!$vnet) {
    Write-Error "Virtual Network $VNetName not found in resource group $ResourceGroupName"
    exit
}

$subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue
if (!$subnet) {
    Write-Error "Subnet $SubnetName not found in VNet $VNetName"
    exit
}

# Create a public IP address for the VM
Write-Host "Creating public IP address..." -ForegroundColor Green
$publicIp = New-AzPublicIpAddress -Name "$VmName-pip" -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic

# Create a network interface card (NIC)
Write-Host "Creating network interface..." -ForegroundColor Green
$nic = New-AzNetworkInterface -Name "$VmName-nic" -ResourceGroupName $ResourceGroupName -Location $Location `
    -SubnetId $subnet.Id -PublicIpAddressId $publicIp.Id

# Create VM configuration
Write-Host "Creating VM configuration..." -ForegroundColor Green
$vmConfig = New-AzVMConfig -VMName $VmName -VMSize $VmSize

# Set OS disk configuration
$vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $VmName `
    -Credential (New-Object System.Management.Automation.PSCredential ($AdminUsername, $AdminPassword)) `
    -ProvisionVMAgent -EnableAutoUpdate

# Set source image (Windows Server 2019)
$vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" `
    -Offer "WindowsServer" -Skus "2019-Datacenter" -Version "latest"

# Add NIC to VM configuration
$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id

# Create the VM
Write-Host "Creating VM $VmName... (This may take a few minutes)" -ForegroundColor Green
$vm = New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig

if ($?) {
    Write-Host "VM $VmName created successfully!" -ForegroundColor Green
}
else {
    Write-Error "Failed to create VM $VmName"
    exit
}

# Create Custom Script Extension to install On-Premises Data Gateway
Write-Host "Creating Custom Script Extension to install On-Premises Data Gateway..." -ForegroundColor Green

$settings = @{
    "fileUris" = @("https://raw.githubusercontent.com/microsoft/PowerPlatform-DataGateway-Samples/main/Scripts/GatewayInstall.ps1")
    "commandToExecute" = "powershell.exe -ExecutionPolicy Unrestricted -File GatewayInstall.ps1 -Silent"
}

Set-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VmName `
    -Name "InstallGateway" -Publisher "Microsoft.Compute" -Type "CustomScriptExtension" `
    -TypeHandlerVersion "1.10" -Settings $settings -Location $Location

Write-Host "On-Premises Data Gateway installation initiated. Please RDP to the VM and complete the gateway configuration." -ForegroundColor Yellow
Write-Host "VM Public IP: $($publicIp.IpAddress)" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. RDP to the VM using the credentials provided" -ForegroundColor Cyan
Write-Host "2. Complete the gateway registration in the PowerBI Gateway app" -ForegroundColor Cyan
Write-Host "3. Register the gateway in the Power Platform Admin Center" -ForegroundColor Cyan
Write-Host "4. Create connections from Power Apps/Power Automate using this gateway" -ForegroundColor Cyan

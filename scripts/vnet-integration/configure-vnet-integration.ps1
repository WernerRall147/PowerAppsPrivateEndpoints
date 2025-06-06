# This script creates the Enterprise Policy and configures VNet integration for a Power Platform environment

<#
.SYNOPSIS
    Configures VNet integration for a Power Platform environment
.DESCRIPTION
    This script:
    1. Connects to Power Platform admin and Azure
    2. Creates an Enterprise Policy using the subnet
    3. Associates the policy with a Power Platform environment
.PARAMETER VNetResourceGroupName
    Resource group containing the VNet
.PARAMETER VNetName
    Name of the Virtual Network
.PARAMETER SubnetName
    Name of the subnet delegated to Power Platform
.PARAMETER PowerPlatformEnvironment
    Power Platform environment ID or name to connect to VNet
.PARAMETER PolicyName
    Name for the Enterprise Policy to create
.EXAMPLE
    .\configure-vnet-integration.ps1 -VNetResourceGroupName "rg-powerplatform" -VNetName "vnet-powerplatform" -SubnetName "subnet-powerplatform" -PowerPlatformEnvironment "contoso-prod" -PolicyName "prod-policy"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$VNetResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$VNetName,
    
    [Parameter(Mandatory=$true)]
    [string]$SubnetName,
    
    [Parameter(Mandatory=$true)]
    [string]$PowerPlatformEnvironment,

    [Parameter(Mandatory=$true)]
    [string]$PolicyName
)

# Check if required modules are installed
$requiredModules = @("Az", "Microsoft.PowerApps.Administration.PowerShell")

foreach ($module in $requiredModules) {
    if (!(Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module $module not found. Installing..." -ForegroundColor Yellow
        Install-Module -Name $module -AllowClobber -Scope CurrentUser -Force
    }
}

# Import modules
Import-Module Az.Accounts
Import-Module Az.Network
Import-Module Microsoft.PowerApps.Administration.PowerShell

# Connect to Azure if not already connected
try {
    $azContext = Get-AzContext
    if (!$azContext) {
        Connect-AzAccount
    }
}
catch {
    Connect-AzAccount
}

# Connect to Power Platform Admin
try {
    Get-PowerAppEnvironment -ErrorAction Stop | Out-Null
}
catch {
    Write-Host "Connecting to Power Platform Admin..." -ForegroundColor Yellow
    Add-PowerAppsAccount
}

# Get subnet details
Write-Host "Getting subnet details..." -ForegroundColor Green
try {
    $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $VNetResourceGroupName -ErrorAction Stop
    $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName -ErrorAction Stop
    
    # Check if subnet has the proper delegation
    $hasDelegation = $false
    foreach ($delegation in $subnet.Delegations) {
        if ($delegation.ServiceName -eq "Microsoft.PowerPlatform/enterprisePolicies") {
            $hasDelegation = $true
            break
        }
    }
    
    if (!$hasDelegation) {
        Write-Error "Subnet $SubnetName does not have the required delegation to Microsoft.PowerPlatform/enterprisePolicies"
        exit 1
    }
}
catch {
    Write-Error "Failed to get subnet: $_"
    exit 1
}

# Get Power Platform environment details
Write-Host "Getting Power Platform environment details..." -ForegroundColor Green
try {
    $environment = Get-PowerAppEnvironment | Where-Object { 
        $_.DisplayName -eq $PowerPlatformEnvironment -or $_.EnvironmentName -eq $PowerPlatformEnvironment 
    }
    
    if (!$environment) {
        Write-Error "Environment $PowerPlatformEnvironment not found"
        exit 1
    }
    
    $environmentId = $environment.EnvironmentName
    $environmentLocation = $environment.Location

    # Check if environment is managed
    $environmentType = $environment.EnvironmentType
    if ($environmentType -ne "Managed") {
        Write-Error "Environment $PowerPlatformEnvironment is not a Managed Environment (current type: $environmentType). VNet integration requires a Managed Environment."
        exit 1
    }
}
catch {
    Write-Error "Failed to get environment details: $_"
    exit 1
}

# Subscription ID
$subscriptionId = (Get-AzContext).Subscription.Id

# This section uses direct REST API calls since the PowerShell cmdlets may not be available
# in the official modules for these preview/new features

# Get access token for ARM
$token = Get-AzAccessToken -ResourceUrl "https://management.azure.com/"
$headers = @{
    'Authorization' = "Bearer $($token.Token)"
    'Content-Type' = 'application/json'
}

# Create the Enterprise Policy
Write-Host "Creating Enterprise Policy for subnet injection..." -ForegroundColor Green
$policyUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$VNetResourceGroupName/providers/Microsoft.PowerPlatform/enterprisePolicies/$PolicyName`?api-version=2020-10-30"
$policyBody = @{
    location = $environmentLocation
    properties = @{
        subnetDelegations = @(
            @{
                name = "primary"
                properties = @{
                    subnet = @{
                        id = $subnet.Id
                    }
                }
            }
        )
    }
} | ConvertTo-Json -Depth 10

try {
    $policyResponse = Invoke-RestMethod -Uri $policyUrl -Method PUT -Headers $headers -Body $policyBody
    Write-Host "Enterprise Policy created successfully: $($policyResponse.name)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to create Enterprise Policy: $_"
    exit 1
}

# Wait for policy to be ready
Write-Host "Waiting for policy to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Link the Enterprise Policy to the environment
Write-Host "Linking Enterprise Policy to Power Platform environment..." -ForegroundColor Green
$linkUrl = "https://api.powerplatform.com/providers/Microsoft.ProcessSimple/environments/$environmentId/subnetInjectionSettings/default?api-version=2020-10-30"
$linkBody = @{
    properties = @{
        enterprisePolicyId = $policyResponse.id
    }
} | ConvertTo-Json

try {
    $powerPlatformToken = Get-PowerAppsAdminToken
    $linkHeaders = @{
        'Authorization' = "Bearer $powerPlatformToken"
        'Content-Type' = 'application/json'
    }
    
    $linkResponse = Invoke-RestMethod -Uri $linkUrl -Method PUT -Headers $linkHeaders -Body $linkBody
    Write-Host "VNet integration configured successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Failed to link Enterprise Policy to environment: $_"
    Write-Error $_.Exception.Response.Content
    exit 1
}

Write-Host 
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "VNet Integration Setup Complete" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Environment: $($environment.DisplayName)" -ForegroundColor White
Write-Host "VNet: $VNetName" -ForegroundColor White
Write-Host "Subnet: $SubnetName" -ForegroundColor White
Write-Host "Enterprise Policy: $PolicyName" -ForegroundColor White
Write-Host
Write-Host "Your Power Platform environment is now connected to Azure VNet." -ForegroundColor Green
Write-Host "Connectors will now be able to access Azure resources that have private endpoints." -ForegroundColor Green
Write-Host
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Create connections in Power Apps/Power Automate to your private resources" -ForegroundColor Yellow
Write-Host "2. Test connectivity to ensure private networking is working" -ForegroundColor Yellow
Write-Host "3. If using multiple regions, repeat this process for the secondary region" -ForegroundColor Yellow

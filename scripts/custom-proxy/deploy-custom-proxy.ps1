# Script to deploy the custom proxy Azure Function app with API Management
# and configure VNET integration for private endpoint access

<#
.SYNOPSIS
    Deploys and configures the Custom Proxy approach for Power Platform Private Endpoints connectivity.
.DESCRIPTION
    This script:
    1. Deploys the Azure Function with VNET integration
    2. Deploys API Management to expose the Function securely
    3. Configures everything for private endpoint access from Power Platform
.PARAMETER ResourceGroupName
    The resource group where resources will be deployed
.PARAMETER Location
    Azure region for resource deployment
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
.PARAMETER VNetName
    Name of the Virtual Network where services will be deployed
.PARAMETER SubnetName
    Name of the subnet for Function VNET integration
.PARAMETER SqlServerName
    Optional: Azure SQL Server name with private endpoint (if using SQL)
.PARAMETER DatabaseName
    Optional: Azure SQL Database name (if using SQL)
.PARAMETER BlobStorageAccountName
    Optional: Azure Storage Account name with private endpoint (if using Blob Storage)
.EXAMPLE
    .\deploy-custom-proxy.ps1 -ResourceGroupName "rg-powerplatform-proxy" -FunctionAppName "func-powerplatform-proxy" -StorageAccountName "stpowerplatformproxy" -ApimName "apim-powerplatform-proxy" -PublisherName "Contoso" -PublisherEmail "admin@contoso.com" -VNetName "vnet-powerplatform" -SubnetName "subnet-functions"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",

    [Parameter(Mandatory = $true)]
    [string]$FunctionAppName,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$ApimName,

    [Parameter(Mandatory = $true)]
    [string]$PublisherName,

    [Parameter(Mandatory = $true)]
    [string]$PublisherEmail,

    [Parameter(Mandatory = $true)]
    [string]$VNetName,

    [Parameter(Mandatory = $true)]
    [string]$SubnetName,

    [Parameter(Mandatory = $false)]
    [string]$SqlServerName = "",

    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "",

    [Parameter(Mandatory = $false)]
    [string]$BlobStorageAccountName = ""
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

# Check if resource group exists, create if not
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (!$rg) {
    Write-Host "Creating resource group $ResourceGroupName in $Location..." -ForegroundColor Green
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location
}

# Get the current script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateFile = Join-Path $scriptDir "proxy-infrastructure.json"

# Check if template file exists
if (!(Test-Path $templateFile)) {
    Write-Error "Template file not found at: $templateFile"
    exit
}

# Deploy the ARM template
Write-Host "Deploying custom proxy infrastructure..." -ForegroundColor Green
$deployParams = @{
    ResourceGroupName = $ResourceGroupName
    TemplateFile      = $templateFile
    functionAppName   = $FunctionAppName
    storageAccountName = $StorageAccountName
    location          = $Location
    vnetName          = $VNetName
    subnetName        = $SubnetName
    apiManagementName = $ApimName
    apiManagementPublisherName = $PublisherName
    apiManagementPublisherEmail = $PublisherEmail
}

# Add optional parameters if provided
if ($SqlServerName) {
    $deployParams.Add("sqlServerName", $SqlServerName)
    if ($DatabaseName) {
        $deployParams.Add("databaseName", $DatabaseName)
    }
}

if ($BlobStorageAccountName) {
    $deployParams.Add("storageAccountBlobName", $BlobStorageAccountName)
}

# Deploy the ARM template
$deployment = New-AzResourceGroupDeployment @deployParams

# Check deployment status
if ($deployment.ProvisioningState -eq "Succeeded") {
    Write-Host "Infrastructure deployment successful!" -ForegroundColor Green
    
    # Deploy Azure Function code
    Write-Host "Deploying Azure Function code..." -ForegroundColor Green
    
    # Publish the function code
    # First, we need to package the function app
    $publishFolder = Join-Path $env:TEMP "ProxyFunctionPublish"
    $zipFilePath = Join-Path $env:TEMP "ProxyFunction.zip"
    
    # Clean up any existing package
    if (Test-Path $publishFolder) {
        Remove-Item -Path $publishFolder -Recurse -Force
    }
    if (Test-Path $zipFilePath) {
        Remove-Item -Path $zipFilePath -Force
    }
    
    # Create publish directory
    New-Item -Path $publishFolder -ItemType Directory -Force
    
    # Copy function code to publish folder
    $sourceFunctionCode = Join-Path $scriptDir "*.*"
    Copy-Item -Path $sourceFunctionCode -Destination $publishFolder -Recurse -Exclude "deploy-custom-proxy.ps1"
    
    # Create the zip package
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($publishFolder, $zipFilePath)
    
    # Deploy the package to the function app
    $functionApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName
    Publish-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -ArchivePath $zipFilePath -Force
    
    # Generate instructions for Power Platform custom connector creation
    $functionAppUrl = "https://$($FunctionAppName).azurewebsites.net"
    $apiManagementUrl = "https://$($ApimName).azure-api.net"
    
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "Custom Proxy Deployment Complete" -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "Function App URL: $functionAppUrl" -ForegroundColor Yellow
    Write-Host "API Management URL: $apiManagementUrl" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Green
    Write-Host "1. Create a custom connector in Power Platform pointing to the API Management URL"
    Write-Host "2. Configure authentication using Azure AD if needed"
    Write-Host "3. Test the connection from Power Apps/Power Automate"
    Write-Host "==========================================================================" -ForegroundColor Cyan
    
} else {
    Write-Error "Deployment failed. Status: $($deployment.ProvisioningState)"
    Write-Error $deployment.Error
}

# This script helps register and configure the On-Premises Data Gateway after installation

<#
.SYNOPSIS
    Guides the configuration of On-Premises Data Gateway to access Private Endpoints
.DESCRIPTION
    This script:
    1. Helps test DNS resolution for private endpoints
    2. Provides guidance for registering the gateway
    3. Verifies connectivity to Azure SQL via private endpoint
.PARAMETER SqlServerName
    The Azure SQL server name (e.g., myserver.database.windows.net)
.PARAMETER DatabaseName
    The database name to test connectivity
.EXAMPLE
    .\configure-gateway.ps1 -SqlServerName "myserver.database.windows.net" -DatabaseName "SampleDB"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SqlServerName,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "On-Premises Data Gateway Configuration Helper" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host 

# Test DNS resolution for the SQL Server
Write-Host "Testing DNS resolution for $SqlServerName..." -ForegroundColor Yellow
$dnsResult = Resolve-DnsName -Name $SqlServerName -ErrorAction SilentlyContinue

if ($dnsResult) {
    Write-Host "DNS resolution successful!" -ForegroundColor Green
    Write-Host "Resolved to: $($dnsResult.IPAddress)" -ForegroundColor Green
    
    # Check if it's a private IP (simple check for common private IP ranges)
    $ip = $dnsResult.IPAddress
    $isPrivate = $ip.StartsWith("10.") -or $ip.StartsWith("172.16.") -or ($ip.StartsWith("172.17.")) -or ($ip.StartsWith("172.18.")) -or ($ip.StartsWith("172.19.")) -or ($ip.StartsWith("172.2")) -or ($ip.StartsWith("172.3")) -or $ip.StartsWith("192.168.")
    
    if ($isPrivate) {
        Write-Host "The SQL Server resolves to a private IP address, which is correct for private endpoint connectivity." -ForegroundColor Green
    } else {
        Write-Host "WARNING: The SQL Server resolves to a public IP address. This may indicate that private DNS resolution is not working correctly." -ForegroundColor Red
        Write-Host "Make sure your VM is in the same VNet as the private endpoint or has access to the private DNS zone." -ForegroundColor Yellow
    }
} else {
    Write-Host "DNS resolution failed for $SqlServerName." -ForegroundColor Red
    Write-Host "Please check your private DNS configuration or add a hosts file entry." -ForegroundColor Yellow
}

Write-Host 
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Gateway Registration Instructions" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "1. Open the On-Premises Data Gateway application on this VM" -ForegroundColor White
Write-Host "2. Sign in with your Power Platform admin account" -ForegroundColor White
Write-Host "3. Provide a name for this gateway (e.g., 'Private-Endpoint-Gateway')" -ForegroundColor White
Write-Host "4. Set a recovery key and store it securely" -ForegroundColor White
Write-Host "5. Complete the registration" -ForegroundColor White
Write-Host 
Write-Host "After registration, go to the Power Platform admin center to verify the gateway appears." -ForegroundColor Yellow
Write-Host "URL: https://admin.powerplatform.microsoft.com/ext/DataGateways" -ForegroundColor Yellow
Write-Host 

# Test SQL connectivity
Write-Host "Would you like to test SQL connectivity via the private endpoint? (Y/N)" -ForegroundColor Yellow
$response = Read-Host

if ($response -eq "Y" -or $response -eq "y") {
    Write-Host "Testing SQL connectivity to $SqlServerName..." -ForegroundColor Yellow
    Write-Host "You'll be prompted for SQL credentials..." -ForegroundColor Yellow
    
    $sqlUsername = Read-Host "Enter SQL username"
    $sqlPasswordSecure = Read-Host "Enter SQL password" -AsSecureString
    $sqlPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sqlPasswordSecure))
    
    try {
        # Check if SqlServer module is installed
        if (!(Get-Module -ListAvailable SqlServer)) {
            Write-Host "SqlServer PowerShell module not found. Installing..." -ForegroundColor Yellow
            Install-Module -Name SqlServer -Force -AllowClobber -Scope CurrentUser
        }
        
        # Import SqlServer module
        Import-Module SqlServer
        
        # Test SQL connection
        $connectionString = "Server=tcp:$SqlServerName,1433;Initial Catalog=$DatabaseName;Persist Security Info=False;User ID=$sqlUsername;Password=$sqlPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        
        Write-Host "Attempting to connect..." -ForegroundColor Yellow
        $connection.Open()
        
        if ($connection.State -eq "Open") {
            Write-Host "Successfully connected to SQL Database via private endpoint!" -ForegroundColor Green
            $connection.Close()
        }
    }
    catch {
        Write-Host "Failed to connect to SQL Database: $_" -ForegroundColor Red
        Write-Host "This could indicate that:" -ForegroundColor Yellow
        Write-Host "1. Private endpoint DNS resolution is not working" -ForegroundColor Yellow
        Write-Host "2. Network connectivity to the private endpoint is blocked" -ForegroundColor Yellow
        Write-Host "3. SQL credentials are incorrect" -ForegroundColor Yellow
    }
}

Write-Host 
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Next Steps in Power Platform" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "1. In Power Apps or Power Automate, create a new SQL Server connection" -ForegroundColor White
Write-Host "2. Enter the SQL Server name: $SqlServerName" -ForegroundColor White
Write-Host "3. Select 'Connect via on-premises data gateway'" -ForegroundColor White
Write-Host "4. Select the gateway you just registered" -ForegroundColor White
Write-Host "5. Provide authentication credentials for the SQL database" -ForegroundColor White
Write-Host "6. Test the connection" -ForegroundColor White
Write-Host 
Write-Host "Your Power Apps and Power Automate flows will now connect to the SQL database via the private endpoint!" -ForegroundColor Green

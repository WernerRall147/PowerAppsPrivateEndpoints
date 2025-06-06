---

# Connecting Power Platform to Azure Resources via Private Endpoints

Power Platform services (Power Apps, Power Automate) typically connect to Azure resources over public endpoints. To use Azure Private Endpoints (keeping traffic private and disabling public access), you must configure your environment using one of the following approaches:

---

## Required Azure Permissions

Implementing private endpoint connections between Power Platform and Azure resources requires specific permissions:

### For All Approaches
- **Azure Resource Owner Permissions** on the target resource (SQL DB, Storage, etc.) to configure private endpoints
- **Private DNS Zone Contributor** to manage DNS entries for private endpoints
- **Network Contributor** on the VNet where private endpoints will be deployed

### For On-Premises Data Gateway
- **Virtual Machine Contributor** to deploy and manage the gateway VM
- **Resource Group Contributor** on the resource group containing the gateway

### For Power Platform VNet Integration
- **Power Platform Admin** permissions to configure Managed Environments
- **Network Contributor** on the VNet and subnet to be delegated
- Specific PowerShell modules: Az.PowerPlatform and Power Platform CLI

### For Custom Proxy Approach
- **App Service Contributor** to deploy and configure Azure Functions
- **API Management Service Contributor** to set up API Management
- **VNet Join** permissions to connect services to the VNet

---

## 1. Using an On-Premises Data Gateway

- **Deploy the Gateway**: Install the Microsoft On-Premises Data Gateway on a VM/server in the Azure VNet (or peered network) with access to the private endpoint.
- **Configure DNS**: Ensure the gateway host resolves the private endpoint's hostname to its private IP (using Azure Private DNS or custom DNS).
- **Connect via Gateway**: In Power Apps/Automate, create a connection using the gateway and provide credentials.
- **Verify Connectivity**: Test the connection; all traffic routes through the gateway, with no inbound ports required.

**Notes:**
- This is the traditional, fully supported method for private access.
- Not all connectors (e.g., Azure Blob Storage) support gateways.
- Premium connectors require appropriate Power Platform licensing.

### Special Case – Azure Blob Storage

The Azure Blob Storage connector does not support gateway connections, even though the UI might show the option. For private Blob Storage, consider:
- Using VNet integration (option 2 below), which supports the Blob connector
- Creating a custom API proxy using Azure Functions and API Management

---

## 2. Power Platform Virtual Network Integration (VNet Injection)

- **Managed Environment**: Your Power Platform environment must be a Managed Environment (premium feature).
- **Azure VNet & Subnet**: Create a VNet and a dedicated /24 subnet in the same region as your Power Platform environment, delegated to Power Platform.
- **Enterprise Policy**: Use PowerShell scripts to create and link an Enterprise Policy between your environment and the subnet.
- **DNS Configuration**: Ensure the VNet can resolve private endpoint DNS names.
- **Use Connectors**: Standard connectors now operate from within your VNet, accessing private endpoints directly.

**Setup Steps:**
1. Create the required Virtual Network(s) and subnet(s) - use at least a /24 CIDR.
2. Create a "Subnet Injection Enterprise Policy" with PowerShell scripts from Microsoft.
3. Apply the policy to your environment using PowerShell.
4. Configure proper DNS resolution for your private endpoints.
5. Use standard connectors to connect to your private resources.

**Supported Connectors:** SQL Server/Azure SQL, Azure Storage (Blob/File), Key Vault, Service Bus, Queues, Snowflake, HTTP with Azure AD, Custom Connectors, and Dataverse plugins.

**Notes:**
- More cloud-native and recommended for new deployments.
- Setup is more complex and requires admin rights and premium licenses.
- Each environment needs its own subnet.
- Regional constraints apply - the VNet must be in a region corresponding to your environment.

---

## 3. Alternative: Custom Proxy/API

- Build an Azure Function or Web API in a VNet to access the resource.
- Expose it via Azure API Management.
- Power Platform calls the API, which accesses the resource privately.

This approach:
- Gives you full control over security and implementation
- Requires more development and maintenance
- Adds extra latency and potential costs

---

## Limitations & Caveats

### On-Premises Data Gateway Limitations
- Requires a VM to maintain (patching, scaling, availability)
- Limited connector support (no Blob Storage)
- Premium licensing still required
- Adds latency to requests
- Regional considerations for optimal placement

### VNet Integration Limitations
- Requires Power Platform admin privileges and Managed Environment
- Complex setup with Azure networking and PowerShell
- Regional constraints for VNet placement
- No subnet reuse across environments
- Limited connector support for some features
- Outbound internet access considerations

### Custom Proxy Limitations
- Custom development and ongoing maintenance
- Extra latency from additional hops
- Additional costs for Azure Functions, API Management

---

## Security & Networking Considerations

- **No Public Exposure**: Private endpoints eliminate public internet exposure.
- **Authentication**: Use Azure AD authentication when possible instead of SQL logins or storage keys.
- **DNS Configuration**: Proper DNS resolution is critical for private endpoints.
- **Network Rules**: Configure NSGs to enforce least-privilege access.
- **Monitoring**: Use Azure monitoring tools to track connectivity and performance.
- **Redundancy**: For gateways, set up clusters; for VNet integration, configure paired regions.
- **Data Exfiltration Prevention**: Control outbound connectivity from your VNet.

---

## Requirements and Prerequisites

### For On-Premises Data Gateway

- Azure VM or server in the VNet with access to the private endpoint.
- Microsoft On-Premises Data Gateway installed and configured.
- Proper DNS setup for private endpoint resolution.
- Power Platform premium licenses for users (for premium connectors).
- Supported connector (e.g., SQL Server; not all connectors like Blob Storage are supported).

### For Power Platform VNet Integration

- Power Platform Managed Environment (requires admin rights and premium licenses).
- Azure subscription with permission to create VNets and subnets.
- VNet and a dedicated /24 subnet in the same region as the Power Platform environment, delegated to Power Platform.
- PowerShell scripts and permissions to create and link Enterprise Policy.
- Proper DNS configuration for private endpoint resolution.
- Supported connectors (SQL, Blob, Key Vault, etc.).

### For Custom Proxy/API Approach

- Azure Function or Web API deployed in a VNet with access to the resource.
- Azure API Management (optional, for secure exposure).
- Power Platform custom connector or HTTP action to call the API.
- Custom development and maintenance.

---

## Implementation Steps

The following outlines the high-level implementation steps for each approach. Currently, no scripts are available in the project folders, but these will be developed.

### On-Premises Data Gateway Setup

1. **Create Azure Resource with Private Endpoint**:
   ```powershell
   # Example for Azure SQL Database (to be implemented)
   # New-AzSqlServerPrivateEndpoint -ResourceGroupName "rg-name" -ServerName "sql-server" -VNetName "vnet-name" -SubnetName "subnet-name"
   ```

2. **Deploy Gateway VM**:
   - Create VM in the same VNet as the private endpoint
   - Install latest On-Premises Data Gateway
   - Register gateway with Power Platform admin center

3. **Configure Connections**:
   - Create connections in Power Apps/Power Automate
   - Select the gateway in the connection configuration
   - Test connectivity through the private endpoint

### Power Platform VNet Integration Setup

1. **Create Required Azure Resources**:
   ```powershell
   # Example VNet and Subnet setup (to be implemented)
   # New-PowerPlatformVNetResources -ResourceGroupName "rg-name" -Location "eastus" -PowerPlatformEnvironment "env-name"
   ```

2. **Configure Managed Environment**:
   - Ensure environment is a Managed Environment
   - PowerShell scripts will be created to set this up

3. **Create Enterprise Policy**:
   ```powershell
   # Example policy creation (to be implemented)
   # New-PowerPlatformEnterprisePolicy -Name "policy-name" -SubnetId "subnet-id" -EnvironmentId "env-id"
   ```

4. **Connect Services**:
   - Use standard connectors in Power Platform
   - No gateway selection required - traffic routes through VNet

### Custom Proxy Approach Setup

1. **Deploy Azure Function with VNet Integration**:
   - Create Function App with VNet integration
   - Deploy code that accesses private resources
   - Configure MSI or service principal authentication

2. **Set Up API Management**:
   - Create API Management instance
   - Import Function API
   - Configure authentication and policies

3. **Create Power Platform Custom Connector**:
   - Define the API connection in Power Platform
   - Configure authentication
   - Test connectivity

---

## How to Use This Repository

This repository contains scripts and configuration files to implement and test the three approaches for connecting Power Platform to Azure resources via private endpoints. Below are instructions for using the tools provided.

### Directory Structure

```
PowerAppsPrivateEndpoints/
|-- scripts/                       # Individual approach-specific scripts
|   |-- gateway-approach/          # Scripts for On-Premises Data Gateway approach
|   |-- vnet-integration/          # Scripts for Power Platform VNet Integration
|   |-- custom-proxy/              # Scripts for Custom Proxy approach
|-- connector-definitions/         # Custom connector definitions for Power Platform
|-- demo-environments/             # Complete demo environment deployment scripts
    |-- gateway-demo/              # End-to-end Gateway demo
    |-- vnet-integration-demo/     # End-to-end VNet Integration demo
    |-- custom-proxy-demo/         # End-to-end Custom Proxy demo
```

### On-Premises Data Gateway Approach

#### Deploy Azure SQL with Private Endpoint

The `sql-private-endpoint.bicep` template deploys an Azure SQL Server and database with a private endpoint.

```powershell
# Deploy using Azure CLI
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file ./scripts/gateway-approach/sql-private-endpoint.bicep \
  --parameters sqlServerName=<sql-server-name> administratorLogin=<admin-username> \
  administratorPassword=<admin-password> vnetName=<vnet-name> subnetName=<subnet-name>

# Deploy using PowerShell
New-AzResourceGroupDeployment -ResourceGroupName <resource-group-name> `
  -TemplateFile ./scripts/gateway-approach/sql-private-endpoint.bicep `
  -sqlServerName <sql-server-name> -administratorLogin <admin-username> `
  -administratorPassword <admin-password> -vnetName <vnet-name> -subnetName <subnet-name>
```

#### Deploy Gateway VM

This script creates a virtual machine in your Azure VNet to host the data gateway.

```powershell
# Create secure password
$securePassword = ConvertTo-SecureString "<your-password>" -AsPlainText -Force

# Run the script
./scripts/gateway-approach/deploy-gateway-vm.ps1 `
  -ResourceGroupName "<resource-group-name>" `
  -VNetName "<vnet-name>" `
  -SubnetName "<subnet-name>" `
  -VmName "<vm-name>" `
  -AdminUsername "<admin-username>" `
  -AdminPassword $securePassword
```

#### Configure Gateway

Use this script after deploying the VM to install and configure the On-Premises Data Gateway.

```powershell
# Run the script on the gateway VM
./scripts/gateway-approach/configure-gateway.ps1 `
  -SqlServerName "<sql-server-name>.database.windows.net" `
  -DatabaseName "<database-name>"
```

#### End-to-End Gateway Demo

For a complete demo environment including all necessary resources:

```powershell
# Create secure password
$securePassword = ConvertTo-SecureString "<your-password>" -AsPlainText -Force

# Deploy complete environment
./demo-environments/gateway-demo/deploy-gateway-demo.ps1 `
  -ResourceGroupName "<resource-group-name>" `
  -AdminUsername "<admin-username>" `
  -AdminPassword $securePassword
```

### Power Platform VNet Integration Approach

#### Set Up VNet and Subnet

The `vnet-setup.bicep` template creates a VNet with a subnet properly configured for Power Platform integration.

```powershell
# Deploy using Azure CLI
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file ./scripts/vnet-integration/vnet-setup.bicep \
  --parameters vnetName=<vnet-name> powerPlatformSubnetName=<subnet-name>

# Deploy using PowerShell
New-AzResourceGroupDeployment -ResourceGroupName <resource-group-name> `
  -TemplateFile ./scripts/vnet-integration/vnet-setup.bicep `
  -vnetName <vnet-name> -powerPlatformSubnetName <subnet-name>
```

#### Configure VNet Integration

This script configures the Enterprise Policy to link your Power Platform environment to the VNet.

```powershell
# Run the script
./scripts/vnet-integration/configure-vnet-integration.ps1 `
  -ResourceGroupName "<resource-group-name>" `
  -EnvironmentId "/providers/Microsoft.PowerPlatform/environments/<environment-guid>" `
  -VNetId "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>" `
  -SubnetId "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Network/virtualNetworks/<vnet-name>/subnets/<subnet-name>"
```

#### End-to-End VNet Integration Demo

For a complete demo environment including all necessary resources:

```powershell
# Create secure password
$securePassword = ConvertTo-SecureString "<your-password>" -AsPlainText -Force

# Deploy complete environment
./demo-environments/vnet-integration-demo/deploy-vnet-integration-demo.ps1 `
  -ResourceGroupName "<resource-group-name>" `
  -PowerPlatformEnvironmentId "/providers/Microsoft.PowerPlatform/environments/<environment-guid>" `
  -AdminUsername "<admin-username>" `
  -AdminPassword $securePassword
```

### Custom Proxy Approach

#### Deploy Proxy Infrastructure

Use this script to deploy Azure Functions and API Management that will serve as a proxy to private resources.

```powershell
./scripts/custom-proxy/deploy-custom-proxy.ps1 `
  -ResourceGroupName "<resource-group-name>" `
  -FunctionAppName "<function-app-name>" `
  -StorageAccountName "<storage-account-name>" `
  -ApimName "<apim-name>" `
  -PublisherName "<publisher-name>" `
  -PublisherEmail "<publisher-email>" `
  -VNetName "<vnet-name>" `
  -SubnetName "<subnet-name>" `
  -SqlServerName "<sql-server-name>" `
  -DatabaseName "<database-name>" `
  -BlobStorageAccountName "<blob-storage-account-name>"
```

#### Custom Connector Definitions

Import one of the connector definition JSON files into Power Platform to create a custom connector:

1. In the Power Platform maker portal, go to **Data** > **Custom Connectors**
2. Click **New custom connector** > **Import an OpenAPI file**
3. Upload the JSON file from the `/connector-definitions/` folder
4. Configure authentication (typically Azure AD OAuth)
5. Test and create the connector

#### End-to-End Custom Proxy Demo

For a complete demo environment including all necessary resources:

```powershell
# Create secure password
$securePassword = ConvertTo-SecureString "<your-password>" -AsPlainText -Force

# Deploy complete environment
./demo-environments/custom-proxy-demo/deploy-custom-proxy-demo.ps1 `
  -ResourceGroupName "<resource-group-name>" `
  -FunctionAppName "<function-app-name>" `
  -StorageAccountName "<storage-account-name>" `
  -ApimName "<apim-name>" `
  -PublisherName "<publisher-name>" `
  -PublisherEmail "<publisher-email>" `
  -AdminUsername "<admin-username>" `
  -AdminPassword $securePassword
```

### Validation and Testing

After deploying any of the approaches:

1. **For Gateway Approach**:
   - RDP to the gateway VM
   - Register the gateway in the Power Platform admin center 
   - Create a SQL connection in Power Apps/Power Automate that uses the gateway

2. **For VNet Integration**:
   - Verify in the Power Platform admin center that the environment shows VNet Integration
   - Create a direct connection to the private resource in Power Apps/Power Automate

3. **For Custom Proxy**:
   - Import the custom connector definition into Power Platform
   - Create a connection using the custom connector
   - Use the connection in a Power App or Flow

### Troubleshooting

If you encounter issues with any of the approaches:

1. **Connectivity Issues**:
   - Verify private DNS resolution is working correctly
   - Check NSG rules to ensure traffic is allowed
   - For gateway approach, verify the gateway is online and configured correctly

2. **VNet Integration Issues**:
   - Ensure the subnet is correctly delegated to Power Platform
   - Verify the environment is a Managed Environment
   - Check that the Enterprise Policy is correctly linked

3. **Custom Proxy Issues**:
   - Check Azure Function logs for errors
   - Verify the VNet integration for the Function App is working
   - Test the API with Postman before using in Power Platform

---

## References

- [Virtual Network support overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [Set up Virtual Network support for Power Platform](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure)
- [Managed Environments overview](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview)
- [Azure Blob Storage Connectors](https://learn.microsoft.com/en-us/connectors/azureblob/)
- [What is a VNet data gateway](https://learn.microsoft.com/en-us/data-integration/vnet/overview)
- [Power Automate with Azure SQL MI via Private Endpoint](https://stackoverflow.com/questions/79607794/recommended-setup-for-connecting-power-automate-cloud-to-azure-sql-managed-insta)

https://learn.microsoft.com/en-us/answers/questions/2244028/how-to-integrated-azure-in-powerplatform
Favicon
Power Platform Managed Environments - Learn Microsoft

https://learn.microsoft.com/en-us/shows/dynamics-365-fasttrack-architecture-insights/power-platform-managed-environments
Favicon
Virtual Network support overview - Power Platform | Microsoft Learn

https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview
Favicon
Set up Virtual Network support for Power Platform - Power Platform | Microsoft Learn

https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure
Favicon
Virtual Network support overview - Power Platform | Microsoft Learn

https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview
Favicon
Azure Blob Storage - Connectors | Microsoft Learn

https://learn.microsoft.com/en-us/connectors/azureblob/
Favicon
Azure Blob Storage - Connectors | Microsoft Learn

https://learn.microsoft.com/en-us/connectors/azureblob/
Favicon
Virtual Network support overview - Power Platform | Microsoft Learn

https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview
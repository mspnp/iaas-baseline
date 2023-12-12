targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The resource group location')
param location string = resourceGroup().location

@description('The resource group name where the AppGw is going to be deployed.')
param resourceGroupName string = resourceGroup().name

@description('The zones where the App Gw is going to be deployed.')
@minValue(1)
@maxValue(3)
param numberOfAvailabilityZones int

@description('The regional network Net name that hosts the VM\'s NIC.')
param vnetName string

@description('The subnet name that will host App Gw\'s NIC.')
param appGatewaySubnetName string

@description('This is the base name for each Azure resource name.')
param baseName string

@description('The Azure KeyVault secret uri for the App Gw frontend TLS certificate.')
param gatewaySSLCertSecretUri string

@description('The Azure KeyVault secret uri for the backendpool wildcard TLS certificate.')
param gatewayTrustedRootSSLCertSecretUri string

@description('The public frontend domain name.')
param gatewayHostName string

@description('The Azure KeyVault where app gw secrets are stored.')
param keyVaultName string

@description('The backend domain name.')
param ingressDomainName string

@description('The Azure Log Analytics Workspace name.')
param logAnalyticsWorkspaceName string

/*** VARIABLES ***/

var agwName = 'agw-${baseName}'

var vmssFrontendSubdomain = 'frontend'
var vmssFrontendDomainName = '${vmssFrontendSubdomain}.${ingressDomainName}'

/*** EXISTING SUBSCRIPTION RESOURCES ***/

// Built-in Azure RBAC role that is applied a Key Vault to grant with metadata, certificates, keys and secrets read privileges.  Granted to App Gateway's managed identity.
resource keyVaultReaderRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: '21090545-7ca7-4776-b22c-e363652d74d2'
  scope: subscription()
}

// Built-in Azure RBAC role that is applied to a Key Vault to grant with secrets content read privileges. Granted to both Key Vault and our workload's identity.
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  name: '4633458b-17de-408a-b874-0445c86b69e6'
  scope: subscription()
}

/*** EXISTING RESOURCES ***/

// The target virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing =  {
  name: vnetName

  // Virtual network's subnet for application gateway
  resource appGatewaySubnet 'subnets' existing = {
    name: appGatewaySubnetName
  }

}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' existing = {
  name: logAnalyticsWorkspaceName
}

/*** RESOURCES ***/

// User Managed Identity that App Gateway is assigned. Used for Azure Key Vault Access.
resource appGatewayManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'id-appgateway'
  location: location
}

// Grant the Azure Application Gateway managed identity with key vault secrets role permissions; this allows pulling frontend and backend certificates.
module appGatewaySecretsUserRoleAssignmentModule './modules/keyvaultRoleAssignment.bicep' = {
  name: 'appGatewaySecretsUserRoleAssignmentDeploy'
  params: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: appGatewayManagedIdentity.properties.principalId
    keyVaultName: keyVaultName
  }
}

// Grant the Azure Application Gateway managed identity with key vault reader role permissions; this allows pulling frontend and backend certificates.
module appGatewayReaderRoleAssignmentModule './modules/keyvaultRoleAssignment.bicep' = {
  name: 'appGatewayReaderRoleAssignmentDeploy'
  params: {
    roleDefinitionId: keyVaultReaderRole.id
    principalId: appGatewayManagedIdentity.properties.principalId
    keyVaultName: keyVaultName
  }
}

resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2021-05-01' = {
  name: 'waf-${baseName}'
  location: location
  properties: {
    policySettings: {
      fileUploadLimitInMb: 10
      state: 'Enabled'
      mode: 'Prevention'
    }
    managedRules: {
      managedRuleSets: [
        {
            ruleSetType: 'OWASP'
            ruleSetVersion: '3.2'
            ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleGroupOverrides: []
        }
      ]
    }
  }
}

resource appGateway 'Microsoft.Network/applicationGateways@2021-05-01' = {
  name: agwName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appGatewayManagedIdentity.id}': {}
    }
  }
  zones: pickZones('Microsoft.Network', 'applicationGateways', location, numberOfAvailabilityZones)
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    sslPolicy: {
      policyType: 'Custom'
      cipherSuites: [
        'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
        'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
      ]
      minProtocolVersion: 'TLSv1_2'
    }
    trustedRootCertificates: [
      {
        name: 'root-cert-wildcard-vmss-webserver'
        properties: {
          keyVaultSecretId: gatewayTrustedRootSSLCertSecretUri
        }
      }
    ]
    gatewayIPConfigurations: [
      {
        name: 'agw-ip-configuration'
        properties: {
          subnet: {
            id: vnet::appGatewaySubnet.id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'agw-frontend-ip-configuration'
        properties: {
          publicIPAddress: {
            id: resourceId(subscription().subscriptionId, resourceGroupName, 'Microsoft.Network/publicIpAddresses', 'pip-gw')
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port-443'
        properties: {
          port: 443
        }
      }
    ]
    autoscaleConfiguration: {
      minCapacity: 0
      maxCapacity: 10
    }
    firewallPolicy: {
      id: wafPolicy.id
    }
    enableHttp2: false
    sslCertificates: [
      {
        name: '${agwName}-ssl-certificate'
        properties: {
          keyVaultSecretId: gatewaySSLCertSecretUri
        }
      }
    ]
    probes: [
      {
        name: 'probe-${gatewayHostName}'
        properties: {
          protocol: 'Https'
          path: '/favicon.ico'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {}
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'webappBackendPool'
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'vmss-webserver-backendpool-httpsettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          hostName: vmssFrontendDomainName
          pickHostNameFromBackendAddress: false
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', agwName, 'probe-${gatewayHostName}')
          }
          trustedRootCertificates: [
            {
              id: resourceId('Microsoft.Network/applicationGateways/trustedRootCertificates', agwName, 'root-cert-wildcard-vmss-webserver')
            }
          ]
        }
      }
    ]
    httpListeners: [
      {
        name: 'listener-https'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', agwName, 'agw-frontend-ip-configuration')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', agwName, 'port-443')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', agwName, '${agwName}-ssl-certificate')
          }
          hostName: gatewayHostName
          hostNames: []
          requireServerNameIndication: true
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'agw-routing-rules'
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', agwName, 'listener-https')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', agwName, 'webappBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', agwName, 'vmss-webserver-backendpool-httpsettings')
          }
        }
      }
    ]
  }
  dependsOn: [
    appGatewaySecretsUserRoleAssignmentModule
    appGatewayReaderRoleAssignmentModule
  ]
}

// App Gateway diagnostics
resource appGatewayDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: appGateway
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

/*** OUTPUTS ***/
output appGatewayName string = appGateway.name

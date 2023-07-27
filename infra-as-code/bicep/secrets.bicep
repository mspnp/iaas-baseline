targetScope = 'resourceGroup'

/*
  Deploy a Key Vault with a private endpoint and DNS zone
*/

/*** PARAMETERS ***/

@description('The resource group name where the AppGw is going to be deployed.')
param resourceGroupName string = resourceGroup().name

@description('This is the base name for each Azure resource name (6-12 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

@description('The certificate data for app gateway TLS termination. The value is base64 encoded.')
@secure()
param appGatewayListenerCertificate string

@description('The Base64 encoded Vmss Webserver public certificate (as .crt or .cer) to be stored in Azure Key Vault as secret and referenced by Azure Application Gateway as a trusted root certificate.')
param vmssWildcardTlsPublicCertificate string

@description('The Base64 encoded Vmss Webserver public and private certificates (formatterd as .pem or .pfx) to be stored in Azure Key Vault as secret and downloaded into the frontend and backend Vmss instances for the workloads ssl certificate configuration.')
@secure()
param vmssWildcardTlsPublicAndKeyCertificates string

@description('The regional network VNet name that hosts the VM\'s NIC.')
param vnetName string

@description('The subnet name for the private endpoints.')
param privateEndpointsSubnetName string

@description('The name of the private endpoint keyvault Application Security Group.')
param keyVaultApplicationSecurityGroupName string

/*** VARIABLES ***/

var keyVaultName = 'kv-${baseName}'
var keyVaultPrivateEndpointName = 'pep-${keyVaultName}'
var keyVaultDnsGroupName = '${keyVaultPrivateEndpointName}/default'
var keyVaultDnsZoneName = 'privatelink.vaultcore.azure.net' //Cannot use 'privatelink${environment().suffixes.keyvaultDns}', per https://github.com/Azure/bicep/issues/9708

/*** EXISTING SUBSCRIPTION RESOURCES ***/

resource targetResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: resourceGroupName
}

/*** EXISTING RESOURCES ***/

// The target virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing =  {
  name: vnetName

  // Virtual network's subnet for all private endpoints NICs
  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }
}

@description('Application Security Group applied to Key Vault private endpoint.')
resource keyVaultApplicationSecurityGroup 'Microsoft.Network/applicationSecurityGroups@2022-07-01' existing = {
  scope: targetResourceGroup
  name: keyVaultApplicationSecurityGroupName
}

/*** RESOURCES ***/

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    tenantId: tenant().tenantId
    createMode: 'default'
    accessPolicies: [] // Azure RBAC is used instead
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices' // Required for AppGW communication
      ipRules: []
      virtualNetworkRules: []
    }
  }

  resource kvsAppGwInternalVmssWebserverTls 'secrets' = {
    name: 'appgw-vmss-webserver-tls'
    properties: {
      value: vmssWildcardTlsPublicCertificate
    }
  }

  resource kvsGatewayPublicCert 'secrets' = {
    name: 'gateway-public-cert'
    properties: {
      value: appGatewayListenerCertificate
    }
  }

  resource kvsWorkloadPublicAndPrivatePublicCerts 'secrets' = {
    name: 'workload-public-private-cert'
    properties: {
      value: vmssWildcardTlsPublicAndKeyCertificates
      contentType: 'application/x-pkcs12'
    }
  }

}

@description('Private Endpoint for Key Vault. All resources in the virtual network will use this endpoint when attempting to access Azure KeyVault instance.')
resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: keyVaultPrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
    customNetworkInterfaceName: 'nic-pe-${keyVaultPrivateEndpointName}'
    applicationSecurityGroups: [
      {
        id: keyVaultApplicationSecurityGroup.id
      }
    ]
    privateLinkServiceConnections: [
      {
        name: keyVaultPrivateEndpointName
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: keyVaultDnsZoneName
  location: 'global'
  properties: {}
}

resource keyVaultDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultDnsZone
  name: '${keyVaultDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource keyVaultDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-11-01' = {
  name: keyVaultDnsGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: keyVaultDnsZoneName
        properties: {
          privateDnsZoneId: keyVaultDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    keyVaultPrivateEndpoint
  ]
}

/*** OUTPUTS ***/

@description('The name of the key vault account.')
output keyVaultName string= keyVault.name

@description('Uri to the secret holding the gatewat listener key cert.')
output gatewayCertSecretUri string = keyVault::kvsGatewayPublicCert.properties.secretUri

@description('Uri to the secret holding the vmss wildcard cert.')
output gatewayTrustedRootSSLCertSecretUri string = keyVault::kvsAppGwInternalVmssWebserverTls.properties.secretUri

@description('Uri to the secret holding the vmss wildcard cert.')
output vmssWorkloadPublicAndPrivatePublicCertsSecretUri string = keyVault::kvsWorkloadPublicAndPrivatePublicCerts.properties.secretUri

@description('The name of the Azure KeyVault Private DNS Zone.')
output keyVaultDnsZoneName string =  keyVaultDnsZone.name

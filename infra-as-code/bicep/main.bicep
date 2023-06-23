targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The regional network VNet Resource ID that will host the VM\'s NIC')
@minLength(79)
param targetVnetResourceId string

@description('IaaS region. This needs to be the same region as the vnet provided in these parameters.')
@allowed([
  'australiaeast'
  'canadacentral'
  'centralus'
  'eastus'
  'eastus2'
  'westus2'
  'francecentral'
  'germanywestcentral'
  'northeurope'
  'southafricanorth'
  'southcentralus'
  'uksouth'
  'westeurope'
  'japaneast'
  'southeastasia'
])
param location string = 'eastus2'

@description('The certificate data for app gateway TLS termination. It is base64 encoded')
@secure()
param appGatewayListenerCertificate string

@description('The Base64 encoded Vmss Webserver public certificate (as .crt or .cer) to be stored in Azure Key Vault as secret and referenced by Azure Application Gateway as a trusted root certificate.')
param vmssWildcardTlsPublicCertificate string

@description('The Base64 encoded Vmss Webserver public and private certificates (formatterd as .pem or .pfx) to be stored in Azure Key Vault as secret and downloaded into the frontend and backend Vmss instances for the workloads ssl certificate configuration.')
@secure()
param vmssWildcardTlsPublicAndKeyCertificates string

@description('Domain name to use for App Gateway and Vmss Webserver.')
param domainName string = 'contoso.com'

@description('A cloud init file (starting with #cloud-config) as a base 64 encoded string used to perform image customization on the jump box VMs. Used for user-management in this context.')
@minLength(100)
param frontendCloudInitAsBase64 string

@description('A cloud init file (starting with #cloud-config) as a base 64 encoded string used to perform image customization on the jump box VMs. Used for user-management in this context.')
@minLength(100)
param backendCloudInitAsBase64 string

@description('The admin passwork for the Windows backend machines.')
@secure()
param adminPassword string

/*** VARIABLES ***/

var subRgUniqueString = uniqueString('vmss', subscription().subscriptionId, resourceGroup().id)
var vmssName = 'vmss-${subRgUniqueString}'
var ilbName = 'ilb-${vmssName}'
var olbName = 'olb-${vmssName}'

var ingressDomainName = 'iaas-ingress.${domainName}'

var numberOfAvailabilityZones = 3

/*** EXISTING SUBSCRIPTION RESOURCES ***/

/*** EXISTING RESOURCES ***/

// resource group
resource targetResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: '${split(targetVnetResourceId,'/')[4]}'
}

// Virtual network
resource targetVirtualNetwork 'Microsoft.Network/virtualNetworks@2022-05-01' existing = {
  scope: targetResourceGroup
  name: '${last(split(targetVnetResourceId,'/'))}'

  // Virtual network's subnet for the nic ilb
  resource snetInternalLoadBalancer 'subnets' existing = {
    name: 'snet-ilbs'
  }
}

// Log Analytics Workspace
resource logAnaliticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' existing = {
  scope: targetResourceGroup
  name: 'log-${location}'
}

/*** RESOURCES ***/

// Deploy a Key Vault with a private endpoint and DNS zone
module secretsModule 'secrets.bicep' = {
  name: 'secretsDeploy'
  params: {
    location: location
    baseName: vmssName
    vnetName: targetVirtualNetwork.name //networkModule.outputs.vnetNName
    privateEndpointsSubnetName: 'snet-privatelinkendpoints' // networkModule.outputs.privateEndpointsSubnetName
    appGatewayListenerCertificate: appGatewayListenerCertificate
    vmssWildcardTlsPublicCertificate: vmssWildcardTlsPublicCertificate
    vmssWildcardTlsPublicAndKeyCertificates: vmssWildcardTlsPublicAndKeyCertificates
  }
}

//Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
module gatewayModule 'gateway.bicep' = {
  name: 'gatewayDeploy'
  params: {
    location: location
    vnetName: targetVirtualNetwork.name //networkModule.outputs.vnetName
    appGatewaySubnetName: 'snet-applicationgateway' //networkModule.outputs.snetAppGwName
    numberOfAvailabilityZones: numberOfAvailabilityZones
    baseName: vmssName
    keyVaultName: secretsModule.outputs.keyVaultName
    gatewaySSLCertSecretUri: secretsModule.outputs.gatewayCertSecretUri
    gatewayTrustedRootSSLCertSecretUri: secretsModule.outputs.gatewayTrustedRootSSLCertSecretUri
    gatewayHostName: domainName
  }
  dependsOn: []
}

//Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
module vmssModule 'vmss.bicep' = {
  name: 'vmssDeploy'
  params: {
    location: location
    vnetName: targetVirtualNetwork.name //networkModule.outputs.vnetName
    vmssFrontendSubnetName: 'snet-frontend' //networkModule.outputs.vmssFrontendSubnetName
    vmssBackendSubnetName: 'snet-backend' //networkModule.outputs.vmssBackendSubnetName
    numberOfAvailabilityZones: numberOfAvailabilityZones
    baseName: vmssName
    ingressDomainName: ingressDomainName
    frontendCloudInitAsBase64: frontendCloudInitAsBase64
    backendCloudInitAsBase64: backendCloudInitAsBase64
    keyVaultName: secretsModule.outputs.keyVaultName
    vmssWorkloadPublicAndPrivatePublicCertsSecretUri: secretsModule.outputs.vmssWorkloadPublicAndPrivatePublicCertsSecretUri
    agwName: gatewayModule.outputs.appGatewayName
    ilbName: ilbName
    olbName: olbName
    adminPassword: adminPassword
  }
  dependsOn: []
}

resource internalLoadBalancer 'Microsoft.Network/loadBalancers@2021-05-01' = {
  name: ilbName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        properties: {
          subnet: {
            id: targetVirtualNetwork::snetInternalLoadBalancer.id
          }
          privateIPAddress: '10.240.4.4'
          privateIPAllocationMethod: 'Static'
        }
        name: 'ilbBackend'
        zones: [
          '1'
          '2'
          '3'
        ]
      }
    ]
    backendAddressPools: [
      {
        name: 'apiBackendPool'
      }
    ]
    loadBalancingRules: [
      {
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', ilbName, 'ilbBackend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', ilbName, 'apiBackendPool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', ilbName, 'ilbprobe')
          }
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 443
          idleTimeoutInMinutes: 15
        }
        name: 'ilbrule'
      }
    ]
    probes: [
      {
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 15
          numberOfProbes: 2
        }
        name: 'ilbprobe'
      }
    ]
  }
  dependsOn: []
}

var numOutboundLoadBalancerIpAddressesToAssign = 3
resource pipsOutboundLoadbalanacer 'Microsoft.Network/publicIPAddresses@2021-05-01' = [for i in range(0, numOutboundLoadBalancerIpAddressesToAssign): {
  name: 'pip-olb-${location}-${padLeft(i, 2, '0')}'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
  }
}]

resource pipsOutboundLoadbalanacer_diagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = [for i in range(0, numOutboundLoadBalancerIpAddressesToAssign): {
  name: 'default'
  scope: pipsOutboundLoadbalanacer[i]
  properties: {
    workspaceId: logAnaliticsWorkspace.id
    logs: [
      {
        categoryGroup: 'audit'
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
}]

resource outboundLoadBalancer 'Microsoft.Network/loadBalancers@2021-05-01' = {
  name: olbName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [for i in range(0, numOutboundLoadBalancerIpAddressesToAssign): {
        name: pipsOutboundLoadbalanacer[i].name
        properties: {
          publicIPAddress: {
            id: pipsOutboundLoadbalanacer[i].id
          }
        }
    }]
    backendAddressPools: [
      {
        name: 'outboundBackendPool'
      }
    ]
    outboundRules: [
      {
        properties: {
          allocatedOutboundPorts: 16000 // this value must be the total number of available ports divided the amount of vms (e.g. 64000*3/6, where 64000 is the amount of port, 3 the selected number of ips and 6 the numbers of vms)
          enableTcpReset: true
          protocol: 'Tcp'
          idleTimeoutInMinutes: 15
          frontendIPConfigurations: [for i in range(0, numOutboundLoadBalancerIpAddressesToAssign): {
              id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', olbName, pipsOutboundLoadbalanacer[i].name)
          }]
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', olbName, 'outboundBackendPool')
          }
        }
        name: 'olbrule'
      }
    ]
    loadBalancingRules: []
    probes: []
  }
  dependsOn: []
}

/*** OUTPUTS ***/
output keyVaultName string = secretsModule.outputs.keyVaultName

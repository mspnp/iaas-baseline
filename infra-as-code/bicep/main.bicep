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
    ilbName: internalLoadBalancerModule.outputs.ilbName
    olbName: outboundLoadBalancerModule.outputs.olbName
    adminPassword: adminPassword
  }
  dependsOn: []
}

//Deploy an Azure Internal Load Balancer.
module internalLoadBalancerModule 'internalloadbalancer.bicep' = {
  name: 'internalLoadBalancerDeploy'
  params: {
    location: location
    vnetName: targetVirtualNetwork.name //networkModule.outputs.vnetName
    internalLoadBalancerSubnetName: 'snet-ilbs' //networkModule.outputs.snetInternalLoadBalancerName
    numberOfAvailabilityZones: numberOfAvailabilityZones
    baseName: vmssName
  }
  dependsOn: []
}

//Deploy an Azure Outbound Load Balancer.
module outboundLoadBalancerModule 'outboundloadbalancer.bicep' = {
  name: 'outboundLoadBalancerDeploy'
  params: {
    location: location
    numberOfAvailabilityZones: numberOfAvailabilityZones
    baseName: vmssName
  }
  dependsOn: []
}

/*** OUTPUTS ***/
output keyVaultName string = secretsModule.outputs.keyVaultName

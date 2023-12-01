targetScope = 'resourceGroup'

/*** PARAMETERS ***/

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

@description('The admin passwork for the Windows backend machines.')
@secure()
param adminPassword string

@description('The Azure Active Directory group/user object id (guid) that will be assigned as the admin users for all deployed virtual machines.')
@minLength(36)
param adminAadSecurityPrincipalObjectId string

@description('The principal type of the adminAadSecurityPrincipalObjectId ID.')
@allowed([
  'User'
  'Group'
])
param adminAddSecurityPrincipalType string = 'User'

/*** VARIABLES ***/

var subRgUniqueString = uniqueString('vmss', subscription().subscriptionId, resourceGroup().id)
var vmssName = 'vmss-${subRgUniqueString}'

var ingressDomainName = 'iaas-ingress.${domainName}'

var numberOfAvailabilityZones = 3

/*** EXISTING SUBSCRIPTION RESOURCES ***/

/*** EXISTING RESOURCES ***/

/*** RESOURCES ***/

//Enable VM insights for Azure Monitor Agent.
module governanceModule 'governance.bicep' = {
  name: 'governanceDeploy'
  params: {
    location: location
  }
  dependsOn: []
}

// Deploy a vnet and subnets for the vmss, appgateway, load balancers and bastion
module networkingModule 'networking.bicep' = {
  name: 'networkingDeploy'
  params: {
    location: location
    logAnalyticsWorkspaceName: monitoringModule.outputs.logAnalyticsWorkspaceName
  }
}

// Deploy a Key Vault with a private endpoint and DNS zone
module secretsModule 'secrets.bicep' = {
  name: 'secretsDeploy'
  params: {
    location: location
    baseName: vmssName
    vnetName: networkingModule.outputs.vnetName
    privateEndpointsSubnetName: networkingModule.outputs.privateEndpointsSubnetName
    appGatewayListenerCertificate: appGatewayListenerCertificate
    vmssWildcardTlsPublicCertificate: vmssWildcardTlsPublicCertificate
    vmssWildcardTlsPublicAndKeyCertificates: vmssWildcardTlsPublicAndKeyCertificates
    keyVaultApplicationSecurityGroupName: networkingModule.outputs.keyVaultApplicationSecurityGroupName
  }
}

//Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
module gatewayModule 'gateway.bicep' = {
  name: 'gatewayDeploy'
  params: {
    location: location
    vnetName: networkingModule.outputs.vnetName
    appGatewaySubnetName: networkingModule.outputs.appGatewaySubnetName
    numberOfAvailabilityZones: numberOfAvailabilityZones
    baseName: vmssName
    keyVaultName: secretsModule.outputs.keyVaultName
    gatewaySSLCertSecretUri: secretsModule.outputs.gatewayCertSecretUri
    gatewayTrustedRootSSLCertSecretUri: secretsModule.outputs.gatewayTrustedRootSSLCertSecretUri
    gatewayHostName: domainName
    ingressDomainName: ingressDomainName
    logAnalyticsWorkspaceName: monitoringModule.outputs.logAnalyticsWorkspaceName
  }
  dependsOn: []
}

//Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
module vmssModule 'vmss.bicep' = {
  name: 'vmssDeploy'
  params: {
    location: location
    vnetName: networkingModule.outputs.vnetName
    vmssFrontendSubnetName: networkingModule.outputs.vmssFrontendSubnetName
    vmssBackendSubnetName: networkingModule.outputs.vmssBackendSubnetName
    numberOfAvailabilityZones: numberOfAvailabilityZones
    baseName: vmssName
    ingressDomainName: ingressDomainName
    frontendCloudInitAsBase64: frontendCloudInitAsBase64
    keyVaultName: secretsModule.outputs.keyVaultName
    vmssWorkloadPublicAndPrivatePublicCertsSecretUri: secretsModule.outputs.vmssWorkloadPublicAndPrivatePublicCertsSecretUri
    agwName: gatewayModule.outputs.appGatewayName
    ilbName: internalLoadBalancerModule.outputs.ilbName
    olbName: outboundLoadBalancerModule.outputs.olbName
    logAnalyticsWorkspaceName: monitoringModule.outputs.logAnalyticsWorkspaceName
    adminPassword: adminPassword
    vmssFrontendApplicationSecurityGroupName: networkingModule.outputs.vmssFrontendApplicationSecurityGroupName
    vmssBackendApplicationSecurityGroupName: networkingModule.outputs.vmssBackendApplicationSecurityGroupName
    adminAadSecurityPrincipalObjectId: adminAadSecurityPrincipalObjectId
    adminAddSecurityPrincipalType: adminAddSecurityPrincipalType
    keyVaultDnsZoneName: secretsModule.outputs.keyVaultDnsZoneName
  }
  dependsOn: []
}

//Deploy an Azure Internal Load Balancer.
module internalLoadBalancerModule 'internalloadbalancer.bicep' = {
  name: 'internalLoadBalancerDeploy'
  params: {
    location: location
    vnetName: networkingModule.outputs.vnetName
    internalLoadBalancerSubnetName: networkingModule.outputs.internalLoadBalancerSubnetName
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
    logAnalyticsWorkspaceName: monitoringModule.outputs.logAnalyticsWorkspaceName
  }
  dependsOn: []
}

//Enable VM insights for Azure Monitor Agent.
module monitoringModule 'monitoring.bicep' = {
  name: 'monitoringDeploy'
  params: {
    location: location
  }
  dependsOn: []
}

/*** OUTPUTS ***/
output keyVaultName string = secretsModule.outputs.keyVaultName
output appGwPublicIpAddress string = networkingModule.outputs.appGwPublicIpAddress
output bastionHostName string = networkingModule.outputs.bastionHostName
output backendAdminUserName string = vmssModule.outputs.backendAdminUserName
output logAnalyticsWorkspaceId string = monitoringModule.outputs.logAnalyticsWorkspaceId

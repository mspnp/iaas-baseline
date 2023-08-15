targetScope = 'resourceGroup'

/*** PARAMETERS ***/

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
@description('Region on which to create the VNnet. All resources tied to this VNnet will also be homed in this region. The region passed as a parameter is assumed to have Availability Zone support.')
param location string

@description('The Azure Log Analytics Workspace name.')
param logAnalyticsWorkspaceName string

/*** VARIABLES ***/
// A designator that represents a business unit id and application id
var vnetName = 'vnet'

/*** RESOURCES ***/

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' existing = {
  scope: resourceGroup()
  name: logAnalyticsWorkspaceName
}

// NSG around the Azure Bastion Subnet.
resource bastionSubnetNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${location}-bastion'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowWebExperienceInbound'
        properties: {
          description: 'Allow our users in. Update this to be as restrictive as possible.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowControlPlaneInbound'
        properties: {
          description: 'Service Requirement. Allow control plane access. Regional Tag not yet supported.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHealthProbesInbound'
        properties: {
          description: 'Service Requirement. Allow Health Probes.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowBastionHostToHostInbound'
        properties: {
          description: 'Service Requirement. Allow Required Host to Host Communication.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'No further inbound traffic allowed.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowSshToVnetOutbound'
        properties: {
          description: 'Allow SSH out to the virtual network'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '22'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowRdpToVnetOutbound'
        properties: {
          description: 'Allow RDP out to the virtual network'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '3389'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowControlPlaneOutbound'
        properties: {
          description: 'Required for control plane outbound. Regional prefix not yet supported'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '443'
          destinationAddressPrefix: 'AzureCloud'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowBastionHostToHostOutbound'
        properties: {
          description: 'Service Requirement. Allow Required Host to Host Communication.'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 130
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowBastionCertificateValidationOutbound'
        properties: {
          description: 'Service Requirement. Allow Required Session and Certificate Validation.'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '80'
          destinationAddressPrefix: 'Internet'
          access: 'Allow'
          priority: 140
          direction: 'Outbound'
        }
      }
      {
        name: 'DenyAllOutbound'
        properties: {
          description: 'No further outbound traffic allowed.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource bastionSubnetNetworkSecurityGroupDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: bastionSubnetNetworkSecurityGroup
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// Default ASG on the vmss frontend. Feel free to constrict further.
resource vmssFrontendApplicationSecurityGroup 'Microsoft.Network/applicationSecurityGroups@2022-07-01' = {
  name: 'asg-frontend'
  location: location
}

// Default ASG on the vmss backend. Feel free to constrict further.
resource vmssBackendApplicationSecurityGroup 'Microsoft.Network/applicationSecurityGroups@2022-07-01' = {
  name: 'asg-backend'
  location: location
}

@description('Application Security Group applied to Key Vault private endpoint.')
resource keyVaultApplicationSecurityGroup 'Microsoft.Network/applicationSecurityGroups@2022-11-01' = {
  name: 'asg-keyvault'
  location: location
}

// Default NSG on the vmss frontend. Feel free to constrict further.
resource vmssFrontendSubnetNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${vnetName}-frontend'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAppGwToToFrontendInbound'
        properties: {
          description: 'Allow AppGw traffic inbound.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '10.240.5.0/24'
          destinationPortRange: '*'
          destinationApplicationSecurityGroups: [
            {
              id: vmssFrontendApplicationSecurityGroup.id
            }
          ]
          direction: 'Inbound'
          access: 'Allow'
          priority: 100
        }
      }
      {
        name: 'AllowHealthProbesInbound'
        properties: {
          description: 'Allow Azure Health Probes in.'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          direction: 'Inbound'
          access: 'Allow'
          priority: 110
        }
      }
      {
        name: 'AllowBastionSubnetSshInbound'
        properties: {
          description: 'Allow Azure Azure Bastion in.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '10.240.6.0/26'
          destinationPortRange: '22'
          destinationApplicationSecurityGroups: [
            {
              id: vmssFrontendApplicationSecurityGroup.id
            }
          ]
          direction: 'Inbound'
          access: 'Allow'
          priority: 120
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'No further inbound traffic allowed.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowFrontendToToBackenddApplicationSecurityGroupHTTPSOutbBund'
        properties: {
          description: 'Allow frontend ASG outbound traffic to backend ASG 443.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceApplicationSecurityGroups: [
            {
              id: vmssFrontendApplicationSecurityGroup.id
            }
          ]
          destinationPortRange: '443'
          destinationApplicationSecurityGroups: [
            {
              id: vmssBackendApplicationSecurityGroup.id
            }
          ]
          direction: 'Outbound'
          access: 'Allow'
          priority: 100
        }
      }
      {
          name: 'Allow443ToInternetOutBound'
          properties: {
              description: 'Allow VMs to communicate to Azure management APIs, Azure Storage, and perform install tasks.'
              protocol: 'Tcp'
              sourcePortRange: '*'
              sourceAddressPrefix: 'VirtualNetwork'
              destinationPortRange: '443'
              destinationAddressPrefix: 'Internet'
              access: 'Allow'
              priority: 101
              direction: 'Outbound'
          }
      }
      {
          name: 'Allow80ToInternetOutBound'
          properties: {
              description: 'Allow Packer VM to use apt-get to upgrade packages'
              protocol: 'Tcp'
              sourcePortRange: '*'
              sourceAddressPrefix: 'VirtualNetwork'
              destinationPortRange: '80'
              destinationAddressPrefix: 'Internet'
              access: 'Allow'
              priority: 102
              direction: 'Outbound'
          }
      }
      {
          name: 'AllowVnetOutBound'
          properties: {
              description: 'Allow VM to communicate to other devices in the virtual network'
              protocol: '*'
              sourcePortRange: '*'
              sourceAddressPrefix: 'VirtualNetwork'
              destinationPortRange: '*'
              destinationAddressPrefix: 'VirtualNetwork'
              access: 'Allow'
              priority: 110
              direction: 'Outbound'
          }
      }
      {
          name: 'DenyAllOutBound'
          properties: {
              description: 'Deny all remaining outbound traffic'
              protocol: '*'
              sourcePortRange: '*'
              sourceAddressPrefix: '*'
              destinationPortRange: '*'
              destinationAddressPrefix: '*'
              access: 'Deny'
              priority: 1000
              direction: 'Outbound'
          }
      }
    ]
  }
}

resource vmssFrontendSubnetNetworkSecurityGroupDiagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: vmssFrontendSubnetNetworkSecurityGroup
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// Default NSG on the vmss backend. Feel free to constrict further.
resource vmssBackendSubnetNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${vnetName}-backend'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowFrontendToToBackenddApplicationSecurityGroupHTTPSInbound'
        properties: {
          description: 'Allow frontend ASG traffic into backend ASG 443.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceApplicationSecurityGroups: [
            {
              id: vmssFrontendApplicationSecurityGroup.id
            }
          ]
          destinationPortRange: '443'
          destinationApplicationSecurityGroups: [
            {
              id: vmssBackendApplicationSecurityGroup.id
            }
          ]
          direction: 'Inbound'
          access: 'Allow'
          priority: 100
        }
      }
      {
        name: 'AllowHealthProbesInbound'
        properties: {
          description: 'Allow Azure Health Probes in.'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          direction: 'Inbound'
          access: 'Allow'
          priority: 110
        }
      }
      {
        name: 'AllowBastionSubnetSshInbound'
        properties: {
          description: 'Allow Azure Azure Bastion in.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '10.240.6.0/26'
          destinationPortRange: '22'
          destinationApplicationSecurityGroups: [
            {
              id: vmssBackendApplicationSecurityGroup.id
            }
          ]
          direction: 'Inbound'
          access: 'Allow'
          priority: 120
        }
      }
      {
        name: 'AllowBastionSubnetRdpInbound'
        properties: {
          description: 'Allow Azure Azure Bastion in.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '10.240.6.0/26'
          destinationPortRange: '3389'
          destinationApplicationSecurityGroups: [
            {
              id: vmssBackendApplicationSecurityGroup.id
            }
          ]
          direction: 'Inbound'
          access: 'Allow'
          priority: 121
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'No further inbound traffic allowed.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
          name: 'Allow443ToInternetOutBound'
          properties: {
              description: 'Allow VMs to communicate to Azure management APIs, Azure Storage, and perform install tasks.'
              protocol: 'Tcp'
              sourcePortRange: '*'
              sourceAddressPrefix: 'VirtualNetwork'
              destinationPortRange: '443'
              destinationAddressPrefix: 'Internet'
              access: 'Allow'
              priority: 100
              direction: 'Outbound'
          }
      }
      {
          name: 'Allow80ToInternetOutBound'
          properties: {
              description: 'Allow Packer VM to use apt-get to upgrade packages'
              protocol: 'Tcp'
              sourcePortRange: '*'
              sourceAddressPrefix: 'VirtualNetwork'
              destinationPortRange: '80'
              destinationAddressPrefix: 'Internet'
              access: 'Allow'
              priority: 102
              direction: 'Outbound'
          }
      }
      {
          name: 'AllowVnetOutBound'
          properties: {
              description: 'Allow VM to communicate to other devices in the virtual network'
              protocol: '*'
              sourcePortRange: '*'
              sourceAddressPrefix: 'VirtualNetwork'
              destinationPortRange: '*'
              destinationAddressPrefix: 'VirtualNetwork'
              access: 'Allow'
              priority: 110
              direction: 'Outbound'
          }
      }
      {
          name: 'DenyAllOutBound'
          properties: {
              description: 'Deny all remaining outbound traffic'
              protocol: '*'
              sourcePortRange: '*'
              sourceAddressPrefix: '*'
              destinationPortRange: '*'
              destinationAddressPrefix: '*'
              access: 'Deny'
              priority: 1000
              direction: 'Outbound'
          }
      }
    ]
  }
}

resource vmssBackendSubnetNetworkSecurityGroupDiagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: vmssBackendSubnetNetworkSecurityGroup
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// Default NSG on the Vmss Backend internal load balancer subnet. Feel free to constrict further.
resource internalLoadBalancerSubnetNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${vnetName}-ilbs'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowFrontendApplicationSecurityGroupHTTPSInbound'
        properties: {
          description: 'Allow Frontend ASG web traffic into 443.'
          protocol: 'Tcp'
          sourceApplicationSecurityGroups: [
            {
              id: vmssFrontendApplicationSecurityGroup.id
            }
          ]
          sourcePortRange: '*'
          destinationPortRange: '443'
          destinationAddressPrefix: '10.240.4.4'
          direction: 'Inbound'
          access: 'Allow'
          priority: 100
        }
      }
      {
        name: 'AllowHealthProbesInbound'
        properties: {
          description: 'Allow Azure Health Probes in.'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          direction: 'Inbound'
          access: 'Allow'
          priority: 110
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'No further inbound traffic allowed.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAllOutbound'
        properties: {
          description: 'Allow all outbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource internalLoadBalancerSubnetNetworkSecurityGroupDiagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: internalLoadBalancerSubnetNetworkSecurityGroup
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// NSG on the Application Gateway subnet.
resource appGwSubnetNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${vnetName}-appgw'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow443Inbound'
        properties: {
          description: 'Allow ALL web traffic into 443. (If you wanted to allow-list specific IPs, this is where you\'d list them.)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationPortRange: '443'
          destinationAddressPrefix: 'VirtualNetwork'
          direction: 'Inbound'
          access: 'Allow'
          priority: 100
        }
      }
      {
        name: 'AllowControlPlaneInbound'
        properties: {
          description: 'Allow Azure Control Plane in. (https://learn.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups)'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'GatewayManager'
          destinationPortRange: '65200-65535'
          destinationAddressPrefix: '*'
          direction: 'Inbound'
          access: 'Allow'
          priority: 110
        }
      }
      {
        name: 'AllowHealthProbesInbound'
        properties: {
          description: 'Allow Azure Health Probes in. (https://learn.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups)'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          direction: 'Inbound'
          access: 'Allow'
          priority: 120
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'No further inbound traffic allowed.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAllOutbound'
        properties: {
          description: 'App Gateway v2 requires full outbound access.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource appGwSubnetNetworkSecurityGroupDiagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: appGwSubnetNetworkSecurityGroup
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// NSG on the Private Link subnet.
resource privateLinkEndpointsSubnetNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${vnetName}-privatelinkendpoints'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAll443InFromVnet'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
          destinationApplicationSecurityGroups: [
            {
              id: keyVaultApplicationSecurityGroup.id
            }
          ]
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource privateLinkEndpointsSubnetNetworkSecurityGroupDiagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: privateLinkEndpointsSubnetNetworkSecurityGroup
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// NSG on the Deployment Agent subnet.
resource deploymentAgentSubnetNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'nsg-${vnetName}-deploymentagent'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAll443InFromVnet'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllOutbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

// The spoke virtual network.
// 65,536 (-reserved) IPs available to the workload, split across subnets four subnets for Compute,
// one for App Gateway and one for Private Link endpoints.
resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.240.0.0/21'
      ]
    }
    subnets: [
      {
        name: 'snet-frontend'
        properties: {
          addressPrefix: '10.240.0.0/24'
          networkSecurityGroup: {
            id: vmssFrontendSubnetNetworkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-backend'
        properties: {
          addressPrefix: '10.240.1.0/24'
          networkSecurityGroup: {
            id: vmssBackendSubnetNetworkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-ilbs'
        properties: {
          addressPrefix: '10.240.4.0/28'
          networkSecurityGroup: {
            id: internalLoadBalancerSubnetNetworkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-privatelinkendpoints'
        properties: {
          addressPrefix: '10.240.4.32/28'
          networkSecurityGroup: {
            id: privateLinkEndpointsSubnetNetworkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-deploymentagent'
        properties: {
          addressPrefix: '10.240.4.64/28'
          networkSecurityGroup: {
            id: deploymentAgentSubnetNetworkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-applicationgateway'
        properties: {
          addressPrefix: '10.240.5.0/24'
          networkSecurityGroup: {
            id: appGwSubnetNetworkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.240.6.0/26'
          networkSecurityGroup: {
            id: bastionSubnetNetworkSecurityGroup.id
          }
        }
      }
    ]
  }

  resource vmssFrontendSubnet 'subnets' existing = {
    name: 'snet-frontend'
  }

  resource vmssBackendSubnet 'subnets' existing = {
    name: 'snet-backend'
  }

  resource bastionHostSubnet 'subnets' existing = {
    name: 'AzureBastionSubnet'
  }

  resource privateLinkEndpointsSubnet 'subnets' existing = {
    name: 'snet-privatelinkendpoints'
  }

  resource appGatewaySubnet 'subnets' existing = {
    name: 'snet-applicationgateway'
  }

  resource internalLoadBalancerSubnet 'subnets' existing = {
    name: 'snet-ilbs'
  }

}

resource vnetDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: vnet
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

@description('The public IP for the regional hub\'s Azure Bastion service.')
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'pip-ab-${location}'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: pickZones('Microsoft.Network', 'publicIPAddresses', location, 3)
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
  }
}

resource bastionPublicIpDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' =  {
  name: 'default'
  scope: bastionPublicIp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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
}

@description('This regional hub\'s Azure Bastion service.')
resource bastionHost 'Microsoft.Network/bastionHosts@2021-05-01' = {
  name: 'ab-${location}'
  location: location
  properties: {
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'hub-subnet'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet::bastionHostSubnet.id
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
  sku: {
    name: 'Standard'
  }
}

resource bastionHostDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: bastionHost
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'BastionAuditLogs'
        enabled: true
      }
    ]
  }
}

// Used as primary public entry point for the workload. Expected to be assigned to an Azure Application Gateway.
// This is a public facing IP, and would be best behind a DDoS Policy (not deployed simply for cost considerations)
resource primaryWorkloadPublicIp 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'pip-gw'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: pickZones('Microsoft.Network', 'publicIPAddresses', location, 3)
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
  }
}

resource primaryWorkloadPublicIpDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' =  {
  name: 'default'
  scope: primaryWorkloadPublicIp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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
}

/*** OUTPUTS ***/

output vnetResourceId string = vnet.id
output vmssSubnetResourceIds array = [
  vnet::vmssFrontendSubnet.id
  vnet::vmssBackendSubnet.id
]
output appGwPublicIpAddress string = primaryWorkloadPublicIp.properties.ipAddress
output bastionHostName string = bastionHost.name

output vnetName string = vnet.name
output privateEndpointsSubnetName string = vnet::privateLinkEndpointsSubnet.name
output appGatewaySubnetName string = vnet::appGatewaySubnet.name
output vmssFrontendSubnetName string = vnet::vmssFrontendSubnet.name
output vmssBackendSubnetName string = vnet::vmssBackendSubnet.name
output internalLoadBalancerSubnetName string = vnet::internalLoadBalancerSubnet.name

output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

output vmssFrontendApplicationSecurityGroupName string = vmssFrontendApplicationSecurityGroup.name
output vmssBackendApplicationSecurityGroupName string = vmssBackendApplicationSecurityGroup.name
output keyVaultApplicationSecurityGroupName string = keyVaultApplicationSecurityGroup.name


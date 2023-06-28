targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The resource group location')
param location string = resourceGroup().location

@description('The zones where the Public Ips is going to be deployed.')
@minValue(1)
@maxValue(3)
param numberOfAvailabilityZones int

@description('This is the base name for each Azure resource name.')
param baseName string

@description('The resource group name where the AppGw is going to be deployed.')
param resourceGroupName string = resourceGroup().name

/*** VARIABLES ***/

var olbName = 'olb-${baseName}'

/*** EXISTING SUBSCRIPTION RESOURCES ***/

resource targetResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: resourceGroupName
}

/*** EXISTING RESOURCES ***/

// Log Analytics Workspace
resource logAnaliticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' existing = {
  scope: targetResourceGroup
  name: 'log-${location}'
}

/*** RESOURCES ***/

var numOutboundLoadBalancerIpAddressesToAssign = 3
resource pipsOutboundLoadbalanacer 'Microsoft.Network/publicIPAddresses@2021-05-01' = [for i in range(0, numOutboundLoadBalancerIpAddressesToAssign): {
  name: 'pip-olb-${location}-${padLeft(i, 2, '0')}'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: pickZones('Microsoft.Network', 'publicIPAddresses', location, numberOfAvailabilityZones)
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
output olbName string = outboundLoadBalancer.name

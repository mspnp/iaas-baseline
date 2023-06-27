targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The resource group location')
param location string = resourceGroup().location

@description('The zones where the Internal Load Balancer is going to be deployed.')
@minValue(1)
@maxValue(3)
param numberOfAvailabilityZones int

@description('The regional network Net name that hosts the VM\'s NIC.')
param vnetName string

@description('The subnet name that will host App Gw\'s NIC.')
param internalLoadBalancerSubnetName string

@description('This is the base name for each Azure resource name.')
param baseName string

/*** VARIABLES ***/

var ilbName = 'ilb-${baseName}'

/*** EXISTING SUBSCRIPTION RESOURCES ***/


/*** EXISTING RESOURCES ***/

// The target virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing =  {
  name: vnetName

  // Virtual network's subnet for the internal load balancer
  resource internalLoadBalancerSubnet 'subnets' existing = {
    name: internalLoadBalancerSubnetName
  }

}

/*** RESOURCES ***/

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
            id: vnet::internalLoadBalancerSubnet.id
          }
          privateIPAddress: '10.240.4.4'
          privateIPAllocationMethod: 'Static'
        }
        name: 'ilbBackend'
        zones: range(1, numberOfAvailabilityZones)
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

/*** OUTPUTS ***/
output ilbName string = internalLoadBalancer.name

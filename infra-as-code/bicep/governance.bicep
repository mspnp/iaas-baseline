targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The resource group location')
param location string = resourceGroup().location

/*** VARIABLES ***/

@description('Consistent prefix on all assignments to facilitate deleting assignments in the cleanup process.')
var policyAssignmentNamePrefix = '[IaaS baseline] -'

/*** EXISTING SUBSCRIPTION RESOURCES ***/

/*** EXISTING TENANT RESOURCES ***/

@description('Built-in: Azure Security agent should be installed on your Linux virtual machine scale sets.')
resource noLinuxVirtualMachinesWithoutAzureSecurityAgentPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' existing  = {
  scope: tenant()
  name: '62b52eae-c795-44e3-94e8-1b3d264766fb'
}

@description('Built-in: Azure Security agent should be installed on your Windows virtual machine scale sets.')
resource noWindowsVirtualMachinesWithoutAzureSecurityAgentPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' existing  = {
  scope: tenant()
  name: 'e16f967a-aa57-4f5e-89cd-8d1434d0a29a'
}

/*** EXISTING RESOURCES ***/

/*** RESOURCES ***/

@description('Audit Linux virtual machines without Azure Security agent.')
resource noLinuxVirtualMachinesWithoutAzureSecurityAgentPolicyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('online management group', noLinuxVirtualMachinesWithoutAzureSecurityAgentPolicyDefinition.id, resourceGroup().id)
  location: location
  properties: {
    displayName: take('${policyAssignmentNamePrefix} ${noLinuxVirtualMachinesWithoutAzureSecurityAgentPolicyDefinition.properties.displayName}', 120)
    description: take(noLinuxVirtualMachinesWithoutAzureSecurityAgentPolicyDefinition.properties.description, 500)
    enforcementMode: 'Default'
    policyDefinitionId: noLinuxVirtualMachinesWithoutAzureSecurityAgentPolicyDefinition.id
    parameters: {
      effect: {
        value: 'AuditIfNotExists'
      }
    }
  }
}

@description('Audit Windows virtual machines without Azure Security agent.')
resource noWindowsVirtualMachinesWithoutAzureSecurityAgentPolicyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('online management group', noWindowsVirtualMachinesWithoutAzureSecurityAgentPolicyDefinition.id, resourceGroup().id)
  location: location
  properties: {
    displayName: take('${policyAssignmentNamePrefix} ${noWindowsVirtualMachinesWithoutAzureSecurityAgentPolicyDefinition.properties.displayName}', 120)
    description: take(noWindowsVirtualMachinesWithoutAzureSecurityAgentPolicyDefinition.properties.description, 500)
    enforcementMode: 'Default'
    policyDefinitionId: noWindowsVirtualMachinesWithoutAzureSecurityAgentPolicyDefinition.id
    parameters: {
      effect: {
        value: 'AuditIfNotExists'
      }
    }
  }
}

/*** OUTPUTS ***/

targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The regional network VNet name that hosts the VM\'s NIC.')
param vnetName string

@description('The subnet name that will host vmss Frontend\'s NIC.')
param vmssFrontendSubnetName string

@description('The subnet name that will host vmss Backend\'s NIC.')
param vmssBackendSubnetName string

@description('The resource group location')
param location string = resourceGroup().location

@description('The resource group name where the AppGw is going to be deployed.')
param resourceGroupName string = resourceGroup().name

@description('The zones where the App Gw is going to be deployed.')
@minValue(1)
@maxValue(3)
param numberOfAvailabilityZones int = 3

@description('This is the base name for each Azure resource name.')
param baseName string

@description('The backend domain name.')
param ingressDomainName string

@description('A cloud init file (starting with #cloud-config) as a base 64 encoded string used to perform image customization on the jump box VMs. Used for user-management in this context.')
@minLength(100)
param frontendCloudInitAsBase64 string

@description('The Azure KeyVault secret uri for the frontend and backendpool wildcard TLS public and key certificate.')
param vmssWorkloadPublicAndPrivatePublicCertsSecretUri string

@description('The Azure KeyVault where vmss secrets are stored.')
param keyVaultName string

@description('The Azure KeyVault where vmss secrets are stored.')
param agwName string

@description('The Azure Internal Load Balancer name.')
param ilbName string

@description('The Azure Outbound Load Balancer name.')
param olbName string

@description('The Azure Log Analytics Workspace name.')
param logAnalyticsWorkspaceName string

@description('The admin passwork for the Windows backend machines.')
@secure()
param adminPassword string

@description('The name of the frontend Application Security Group.')
param vmssFrontendApplicationSecurityGroupName string

@description('The name of the backend Application Security Group.')
param vmssBackendApplicationSecurityGroupName string

@description('The Microsoft Entra group/user object id (guid) that will be assigned as the admin users for all deployed virtual machines.')
@minLength(36)
param adminSecurityPrincipalObjectId string

@description('The principal type of the adminSecurityPrincipalObjectId ID.')
@allowed([
  'User'
  'Group'
])
param adminSecurityPrincipalType string

@description('The name of the Azure KeyVault Private DNS Zone.')
param keyVaultDnsZoneName string

/*** VARIABLES ***/

var vmssBackendSubdomain = 'backend'
var vmssFrontendSubdomain = 'frontend'
var vmssFrontendDomainName = '${vmssFrontendSubdomain}.${ingressDomainName}'

var defaultAdminUserName = uniqueString(baseName, resourceGroup().id)

/*** EXISTING GLOBAL RESOURCES ***/

resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: keyVaultDnsZoneName

  resource keyVaultDnsZoneLink 'virtualNetworkLinks' existing = {
    name: '${keyVaultDnsZoneName}-link'
  }
}

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

@description('Built-in Azure RBAC role that is applied to the virtual machines to grant remote user access to them via SSH or RDP. Granted to the provided group object id.')
resource virtualMachineAdminLoginRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: '1c0163c0-47e6-4577-8991-ea5c82e286e4'
}

resource targetResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: resourceGroupName
}

/*** EXISTING RESOURCES ***/

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  scope: targetResourceGroup
  name: logAnalyticsWorkspaceName
}

// The target virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing =  {
  name: vnetName

  // Virtual network's subnet for the nic vms
  resource frontendSubnet 'subnets' existing = {
    name: vmssFrontendSubnetName
  }

  // Virtual network's subnet for the nic vms
  resource backendSubnet 'subnets' existing = {
    name: vmssBackendSubnetName
  }

}

// Default ASG on the vmss frontend. Feel free to constrict further.
resource vmssFrontendApplicationSecurityGroup 'Microsoft.Network/applicationSecurityGroups@2022-07-01' existing = {
  scope: targetResourceGroup
  name: vmssFrontendApplicationSecurityGroupName
}

// Default ASG on the vmss backend. Feel free to constrict further.
resource vmssBackendApplicationSecurityGroup 'Microsoft.Network/applicationSecurityGroups@2022-07-01' existing = {
  scope: targetResourceGroup
  name: vmssBackendApplicationSecurityGroupName
}

resource outboundLoadBalancer 'Microsoft.Network/loadBalancers@2024-07-01' existing = {
  name: olbName
}

resource internalLoadBalancer 'Microsoft.Network/loadBalancers@2024-07-01' existing = {
  name: ilbName
}

resource appGateway 'Microsoft.Network/applicationGateways@2024-07-01' existing = {
  name: agwName
}

/*** RESOURCES ***/

@description('The managed identity for frontend instances')
resource vmssFrontendManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: 'id-vm-frontend'
  location: location
}

@description('The managed identity for backend instances')
resource vmssBackendManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: 'id-vm-backend'
  location: location
}

// Grant the Vmss Frontend managed identity with key vault secrets role permissions; this allows pulling frontend and backend certificates.
module vmssFrontendSecretsUserRoleRoleAssignmentModule './modules/keyvaultRoleAssignment.bicep' = {
  name: guid(resourceGroup().id, 'id-vm-frontend', keyVaultSecretsUserRole.id)
  params: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: vmssFrontendManagedIdentity.properties.principalId
    keyVaultName: keyVaultName
  }
}

// Grant the Vmss Frontend managed identity with key vault reader role permissions; this allows pulling frontend and backend certificates.
module vmssFrontendKeyVaultReaderRoleAssignmentModule './modules/keyvaultRoleAssignment.bicep' = {
  name: guid(resourceGroup().id, 'id-vm-frontend', keyVaultReaderRole.id)
  params: {
    roleDefinitionId: keyVaultReaderRole.id
    principalId: vmssFrontendManagedIdentity.properties.principalId
    keyVaultName: keyVaultName
  }
}

// Grant the Vmss Backend managed identity with key vault secrets role permissions; this allows pulling frontend and backend certificates.
module vmssBackendSecretsUserRoleRoleAssignmentModule './modules/keyvaultRoleAssignment.bicep' = {
  name: guid(resourceGroup().id, 'id-vm-backend', keyVaultSecretsUserRole.id)
  params: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: vmssBackendManagedIdentity.properties.principalId
    keyVaultName: keyVaultName
  }
}

// Grant the Vmss Backend managed identity with key vault reader role permissions; this allows pulling frontend and backend certificates.
module vmssBackendKeyVaultReaderRoleAssignmentModule './modules/keyvaultRoleAssignment.bicep' = {
  name: guid(resourceGroup().id, 'id-vm-backend', keyVaultReaderRole.id)
  params: {
    roleDefinitionId: keyVaultReaderRole.id
    principalId: vmssBackendManagedIdentity.properties.principalId
    keyVaultName: keyVaultName
  }
}

@description('Sets up the provided object id that belongs to a group or user to have access to authenticate into virtual machines with the Microsoft Entra ID login (AADLogin/AADSSHLogin) extension installed in this resource group.')
resource groupOrUserAdminLoginRoleRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, adminSecurityPrincipalObjectId, virtualMachineAdminLoginRole.id)
  properties: {
    principalId: adminSecurityPrincipalObjectId
    roleDefinitionId: virtualMachineAdminLoginRole.id
    principalType: adminSecurityPrincipalType
    description: 'Allows users in this group or a single user access to log into virtual machines through Microsoft Entra ID.'
  }
}

resource contosoDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: ingressDomainName
  location: 'global'

  resource vmssBackendSubdomainARecord 'A' = {
    name: vmssBackendSubdomain
    properties: {
      ttl: 3600
      aRecords: [
        {
          ipv4Address: '10.240.4.4' // Internal Load Balancer IP address
        }
      ]
    }
  }

  resource vnetlnk 'virtualNetworkLinks' = {
    name: 'to_${vnet.name}'
    location: 'global'
    properties: {
      virtualNetwork: {
        id: vnet.id
      }
      registrationEnabled: false
    }
  }
}

@description('The compute for frontend instances; these machines are assigned to the frontend app team to deploy their workloads')
resource vmssFrontend 'Microsoft.Compute/virtualMachineScaleSets@2024-11-01' = {
  name: 'vmss-frontend'
  location: location
  zones: pickZones('Microsoft.Compute', 'virtualMachineScaleSets', location, numberOfAvailabilityZones)
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${vmssFrontendManagedIdentity.id}': {}
    }
  }
  sku: {
    name: 'Standard_D4s_v3'
    tier: 'Standard'
    capacity: 3
  }
  properties: {
    singlePlacementGroup: false
    additionalCapabilities: {
      ultraSSDEnabled: false
    }
    orchestrationMode: 'Flexible'
    platformFaultDomainCount: 1
    zoneBalance: false
    automaticRepairsPolicy: {
      enabled: true
      gracePeriod: 'PT30M'
    }
    virtualMachineProfile: {
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
        }
      }
      osProfile: {
        computerNamePrefix: 'frontend'
        linuxConfiguration: {
          disablePasswordAuthentication: true
          provisionVMAgent: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${defaultAdminUserName}/.ssh/authorized_keys'
                keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCcFvQl2lYPcK1tMB3Tx2R9n8a7w5MJCSef14x0ePRFr9XISWfCVCNKRLM3Al/JSlIoOVKoMsdw5farEgXkPDK5F+SKLss7whg2tohnQNQwQdXit1ZjgOXkis/uft98Cv8jDWPbhwYj+VH/Aif9rx8abfjbvwVWBGeA/OnvfVvXnr1EQfdLJgMTTh+hX/FCXCqsRkQcD91MbMCxpqk8nP6jmsxJBeLrgfOxjH8RHEdSp4fF76YsRFHCi7QOwTE/6U+DpssgQ8MTWRFRat97uTfcgzKe5MOfuZHZ++5WFBgaTr1vhmSbXteGiK7dQXOk2cLxSvKkzeaiju9Jy6hoSl5oMygUVd5fNPQ94QcqTkMxZ9tQ9vPWOHwbdLRD31Ses3IBtDV+S6ehraiXf/L/e0jRUYk8IL/J543gvhOZ0hj2sQqTj9XS2hZkstZtrB2ywrJzV5ByETUU/oF9OsysyFgnaQdyduVqEPHaqXqnJvBngqqas91plyT3tSLMez3iT0s= unused-generated-by-azure'
              }
            ]
          }
        }
        customData: frontendCloudInitAsBase64
        adminUsername: defaultAdminUserName
      }
      storageProfile: {
        osDisk: {
          osType: 'Linux'
          diffDiskSettings: {
            option: 'Local'
            placement: 'CacheDisk'
          }
          caching: 'ReadOnly'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS' // Ephemeral OS disk is supported for VMs or VM Scale Set Instances using Standard LRS storage account type only
          }
        }
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-focal'
          sku: '20_04-lts-gen2'
          version: 'latest'
        }
        dataDisks: [
          {
            caching: 'None'
            createOption: 'Empty'
            deleteOption: 'Delete'
            diskSizeGB: 4
            lun: 0
            managedDisk: {
              storageAccountType: 'Premium_ZRS'
            }
          }
        ]
      }
      networkProfile: {
        networkApiVersion: '2024-07-01'
        networkInterfaceConfigurations: [
          {
            name: 'nic-frontend'
            properties: {
              primary: true
              enableIPForwarding: false
              enableAcceleratedNetworking: false
              networkSecurityGroup: null
              ipConfigurations: [
                {
                  name: 'default'
                  properties: {
                    primary: true
                    privateIPAddressVersion: 'IPv4'
                    publicIPAddressConfiguration: null
                    subnet: {
                      id: vnet::frontendSubnet.id
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', outboundLoadBalancer.name, 'outboundBackendPool')
                      }
                    ]
                    applicationGatewayBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGateway.name, 'webappBackendPool')
                      }
                    ]
                    applicationSecurityGroups: [
                      {
                        id: vmssFrontendApplicationSecurityGroup.id
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'AADSSHLogin'
            properties: {
              provisionAfterExtensions: [
                'CustomScript'
              ]
              publisher: 'Microsoft.Azure.ActiveDirectory'
              type: 'AADSSHLoginForLinux'
              typeHandlerVersion: '1.0'
              autoUpgradeMinorVersion: true
            }
          }
          {
            name: 'KeyVaultForLinux'
            properties: {
              publisher: 'Microsoft.Azure.KeyVault'
              type: 'KeyVaultForLinux'
              typeHandlerVersion: '2.0'
              autoUpgradeMinorVersion: true
              enableAutomaticUpgrade: true
              settings: {
                secretsManagementSettings: {
                  certificateStoreLocation: '/var/lib/waagent/Microsoft.Azure.KeyVault.Store'
                  observedCertificates: [
                    vmssWorkloadPublicAndPrivatePublicCertsSecretUri
                  ]
                  pollingIntervalInS: '3600'
                }
              }
            }
          }
          {
            name: 'CustomScript'
            properties: {
              provisionAfterExtensions: [
                'KeyVaultForLinux'
              ]
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.1'
              autoUpgradeMinorVersion: true
              protectedSettings: {
                commandToExecute: 'sh configure-nginx-frontend.sh'
                // The following installs and configure Nginx for the frontend Linux machine, which is used as an application stand-in for this reference implementation. Using the CustomScript extension can be useful for bootstrapping VMs in leu of a larger DSC solution, but is generally not recommended for application deployment in production environments.
                fileUris: [
                  'https://raw.githubusercontent.com/mspnp/iaas-baseline/main/configure-nginx-frontend.sh'
                ]
              }
            }
          }
          {
            name: 'AzureMonitorLinuxAgent'
            properties: {
              publisher: 'Microsoft.Azure.Monitor'
              type: 'AzureMonitorLinuxAgent'
              typeHandlerVersion: '1.25'
              autoUpgradeMinorVersion: true
              enableAutomaticUpgrade: true
              settings: {
                authentication: {
                  managedIdentity: {
                    'identifier-name': 'mi_res_id'
                    'identifier-value': vmssFrontendManagedIdentity.id
                  }
                }
              }
            }
          }
          {
            name: 'DependencyAgentLinux'
            properties: {
              provisionAfterExtensions: [
                'AzureMonitorLinuxAgent'
              ]
              publisher: 'Microsoft.Azure.Monitoring.DependencyAgent'
              type: 'DependencyAgentLinux'
              typeHandlerVersion: '9.10'
              autoUpgradeMinorVersion: true
              enableAutomaticUpgrade: true
              settings: {
                enableAMA: true
              }
            }
          }
          {
            name: 'HealthExtension'
            properties: {
              provisionAfterExtensions: [
                'CustomScript'
              ]
              publisher: 'Microsoft.ManagedServices'
              type: 'ApplicationHealthLinux'
              typeHandlerVersion: '1.0'
              autoUpgradeMinorVersion: true
              enableAutomaticUpgrade: true
              settings: {
                protocol: 'https'
                port: 443
                requestPath: '/favicon.ico'
                intervalInSeconds: 5
                numberOfProbes: 3
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    appGateway
    outboundLoadBalancer
    omsVmssInsights
    vmssFrontendSecretsUserRoleRoleAssignmentModule
    vmssFrontendKeyVaultReaderRoleAssignmentModule
    vmssBackend
    contosoDnsZone::vmssBackendSubdomainARecord
    contosoDnsZone::vnetlnk
    keyVaultDnsZone::keyVaultDnsZoneLink
    groupOrUserAdminLoginRoleRoleAssignment
  ]
}

@description('The compute for backend instances; these machines are assigned to the api app team so they can deploy their workloads.')
resource vmssBackend 'Microsoft.Compute/virtualMachineScaleSets@2024-11-01' = {
  name: 'vmss-backend'
  location: location
  zones: pickZones('Microsoft.Compute', 'virtualMachineScaleSets', location, numberOfAvailabilityZones)
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${vmssBackendManagedIdentity.id}': {}
    }
  }
  sku: {
    name: 'Standard_E2s_v3'
    tier: 'Standard'
    capacity: 3
  }
  properties: {
    singlePlacementGroup: false
    additionalCapabilities: {
      ultraSSDEnabled: false
    }
    orchestrationMode: 'Flexible'
    platformFaultDomainCount: 1
    zoneBalance: false
    automaticRepairsPolicy: {
      enabled: true
      gracePeriod: 'PT30M'
    }
    virtualMachineProfile: {
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
        }
      }
      osProfile: {
        computerNamePrefix: 'backend'
        windowsConfiguration: {
          provisionVMAgent: true
          enableAutomaticUpdates: true
          patchSettings: {
            patchMode: 'AutomaticByPlatform'
            automaticByPlatformSettings: {
              rebootSetting: 'IfRequired'
            }
            assessmentMode: 'ImageDefault'
            enableHotpatching: false
          }
        }
        adminUsername: defaultAdminUserName
        adminPassword: adminPassword
        secrets: []
        allowExtensionOperations: true
      }
      storageProfile: {
        osDisk: {
          osType: 'Windows'
          diffDiskSettings: {
            option: 'Local'
            placement: 'CacheDisk'
          }
          caching: 'ReadOnly'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS' // Ephemeral OS disk is supported for VMs or VM Scale Set Instances using Standard LRS storage account type only
          }
          deleteOption: 'Delete'
          diskSizeGB: 30
        }
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2022-datacenter-azure-edition-smalldisk'
          version: 'latest'
        }
        dataDisks: [
          {
            caching: 'None'
            createOption: 'Empty'
            deleteOption: 'Delete'
            diskSizeGB: 4
            lun: 0
            managedDisk: {
              storageAccountType: 'Premium_ZRS'
            }
          }
        ]
      }
      networkProfile: {
        networkApiVersion: '2024-07-01'
        networkInterfaceConfigurations: [
          {
            name: 'nic-backend'
            properties: {
              deleteOption: 'Delete'
              primary: true
              enableIPForwarding: false
              enableAcceleratedNetworking: false
              networkSecurityGroup: null
              ipConfigurations: [
                {
                  name: 'default'
                  properties: {
                    primary: true
                    privateIPAddressVersion: 'IPv4'
                    publicIPAddressConfiguration: null
                    subnet: {
                      id: vnet::backendSubnet.id
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', internalLoadBalancer.name, 'apiBackendPool')
                      }
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', outboundLoadBalancer.name, 'outboundBackendPool')
                      }
                    ]
                    applicationSecurityGroups: [
                      {
                        id: vmssBackendApplicationSecurityGroup.id
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'AADLogin'
            properties: {
              provisionAfterExtensions: [
                'CustomScript'
              ]
              autoUpgradeMinorVersion: true
              publisher: 'Microsoft.Azure.ActiveDirectory'
              type: 'AADLoginForWindows'
              typeHandlerVersion: '2.0'
              settings: {
                mdmId: ''
              }
            }
          }

          {
            name: 'KeyVaultForWindows'
            properties: {
              publisher: 'Microsoft.Azure.KeyVault'
              type: 'KeyVaultForWindows'
              typeHandlerVersion: '3.0'
              autoUpgradeMinorVersion: true
              enableAutomaticUpgrade: true
              settings: {
                secretsManagementSettings: {
                  observedCertificates: [
                    {
                      certificateStoreName: 'MY'
                      certificateStoreLocation: 'LocalMachine'
                      keyExportable: true
                      url: vmssWorkloadPublicAndPrivatePublicCertsSecretUri
                      accounts: [
                        'Network Service'
                        'Local Service'
                      ]
                    }
                  ]
                  linkOnRenewal: true
                  pollingIntervalInS: '3600'
                }
              }
            }
          }

          {
            name: 'CustomScript'
            properties: {
              provisionAfterExtensions: [
                'KeyVaultForWindows'
              ]
              publisher: 'Microsoft.Compute'
              type: 'CustomScriptExtension'
              typeHandlerVersion: '1.10'
              autoUpgradeMinorVersion: true
              protectedSettings: {
                commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File configure-nginx-backend.ps1'
                // The following installs and configure Nginx for the backend Windows machine, which is used as an application stand-in for this reference implementation. Using the CustomScript extension can be useful for bootstrapping VMs in leu of a larger DSC solution, but is generally not recommended for application deployment in production environments.
                fileUris: [
                  'https://raw.githubusercontent.com/mspnp/iaas-baseline/main/configure-nginx-backend.ps1'
                ]
              }
            }
          }

          {
            name: 'AzureMonitorWindowsAgent'
            properties: {
              publisher: 'Microsoft.Azure.Monitor'
              type: 'AzureMonitorWindowsAgent'
              typeHandlerVersion: '1.14'
              autoUpgradeMinorVersion: true
              enableAutomaticUpgrade: true
              settings: {
                authentication: {
                  managedIdentity: {
                    'identifier-name': 'mi_res_id'
                    'identifier-value': vmssBackendManagedIdentity.id
                  }
                }
              }
            }
          }

          {
            name: 'DependencyAgentWindows'
            properties: {
              provisionAfterExtensions: [
                'AzureMonitorWindowsAgent'
              ]
              publisher: 'Microsoft.Azure.Monitoring.DependencyAgent'
              type: 'DependencyAgentWindows'
              typeHandlerVersion: '9.10'
              autoUpgradeMinorVersion: true
              enableAutomaticUpgrade: true
              settings: {
                enableAMA: true
              }
            }
          }

          {
            name: 'ApplicationHealthWindows'
            properties: {
              provisionAfterExtensions: [
                'CustomScript'
              ]
              publisher: 'Microsoft.ManagedServices'
              type: 'ApplicationHealthWindows'
              typeHandlerVersion: '1.0'
              autoUpgradeMinorVersion: true
              enableAutomaticUpgrade: true
              settings: {
                protocol: 'https'
                port: 443
                requestPath: '/favicon.ico'
                intervalInSeconds: 5
                numberOfProbes: 3
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    omsVmssInsights
    internalLoadBalancer
    outboundLoadBalancer
    vmssBackendSecretsUserRoleRoleAssignmentModule
    contosoDnsZone::vmssBackendSubdomainARecord
    contosoDnsZone::vnetlnk
    keyVaultDnsZone::keyVaultDnsZoneLink
    groupOrUserAdminLoginRoleRoleAssignment
  ]
}

resource omsVmssInsights 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'VMInsights(${logAnalyticsWorkspace.name})'
  location: location
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'VMInsights(${logAnalyticsWorkspace.name})'
    product: 'OMSGallery/VMInsights'
    promotionCode: ''
    publisher: 'Microsoft'
  }
}

/*** OUTPUTS ***/
output backendAdminUserName string = defaultAdminUserName

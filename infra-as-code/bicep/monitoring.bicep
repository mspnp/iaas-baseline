targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The resource group location')
param location string = resourceGroup().location

/*** VARIABLES ***/

@description('Consistent prefix on all assignments to facilitate deleting assignments in the cleanup process.')
var policyAssignmentNamePrefix = '[IaaS baseline] -'

/*** EXISTING SUBSCRIPTION RESOURCES ***/

@description('Built-in Monitoring Contributor Azure RBAC role.')
resource monitoringContributorRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
}

@description('Built-in Log Analytics Contributor Azure RBAC role.')
resource logAnalyticsContributorRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: '92aaf0da-9dab-42b6-94a3-d43ce8d16293'
}

/*** EXISTING RESOURCES ***/

@description('Built-in: Deploy Data Collection Rule for Linux virtual machines.')
resource configureLinuxMachinesWithDataCollectionRulePolicy 'Microsoft.Authorization/policyDefinitions@2021-06-01' existing = {
  scope: tenant()
  name: '2ea82cdd-f2e8-4500-af75-67a2e084ca74'
}

@description('Built-in: Deploy Data Collection Rule for Windows virtual machines.')
resource configureWindowsMachinesWithDataCollectionRulePolicy 'Microsoft.Authorization/policyDefinitions@2021-06-01' existing = {
  scope: tenant()
  name: 'eab1f514-22e3-42e3-9a1f-e1dc9199355c'
}

/*** RESOURCES ***/

// This Log Analytics workspace stores logs from the regional spokes network, and bastion.
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${location}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    forceCmkForQuery: false
    features: {
      disableLocalAuth: false
      enableDataExport: false
      enableLogAccessUsingOnlyResourcePermissions: false
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
  }

  resource windowsLogsCustomTable 'tables' = {
    name: 'WindowsLogsTable_CL'
    properties: {
      schema: {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'DateTime'
          }
          {
            name: 'RawData'
            type: 'String'
          }
        ]
        name: 'WindowsLogsTable_CL'
      }
    }
  }
}

resource logAnalyticsWorkspaceDiagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope:logAnalyticsWorkspace
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

@description('Ensure the managed identity for DCR DINE policies is has needed permissions.')
resource dineLinuxDcrPolicyLogAnalyticsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, logAnalyticsContributorRole.id, configureLinuxMachinesWithDataCollectionRulePolicyAssignment.id)
  properties: {
    principalId: configureLinuxMachinesWithDataCollectionRulePolicyAssignment.identity.principalId
    roleDefinitionId: logAnalyticsContributorRole.id
    principalType: 'ServicePrincipal'
  }
}

@description('Ensure the managed identity for DCR DINE policies is has needed permissions.')
resource dineLinuxDcrPolicyMonitoringContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, monitoringContributorRole.id, configureLinuxMachinesWithDataCollectionRulePolicyAssignment.id)
  properties: {
    principalId: configureLinuxMachinesWithDataCollectionRulePolicyAssignment.identity.principalId
    roleDefinitionId: monitoringContributorRole.id
    principalType: 'ServicePrincipal'
  }
}

resource windowsVmLogsDataCollectionEndpoints 'Microsoft.Insights/dataCollectionEndpoints@2021-09-01-preview' = {
  name: 'dceWindowsLogs'
  location: location
  kind: 'Windows'
  properties: {
    configurationAccess: {}
    logsIngestion: {}
    networkAcls: {
      publicNetworkAccess: 'Disabled'
    }
  }
}

resource windowsVmLogsCustomDataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcrWindowsLogs'
  location: location
  kind: 'Windows'
  properties: {
    dataCollectionEndpointId: windowsVmLogsDataCollectionEndpoints.id
    streamDeclarations: {
      'Custom-WindowsLogsTable_CL': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'RawData'
            type: 'string'
          }
        ]
      }
    }
    dataSources: {
      logFiles: [
        {
          streams: [
            'Custom-WindowsLogsTable_CL'
          ]
          filePatterns: [
             'w:\\nginx\\data\\*.data'
          ]
          format: 'text'
          settings: {
            text: {
              recordStartTimestampFormat: 'ISO 8601'
            }
          }
          name: 'backendLogFileFormat-Windows'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Custom-WindowsLogsTable_CL'
        ]
        destinations: [
          logAnalyticsWorkspace.name
        ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: 'Custom-WindowsLogsTable_CL'
      }
    ]
    destinations: {
      logAnalytics: [
        {
          name: logAnalyticsWorkspace.name
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    description: 'Default data collection rule for Windows virtual machine logs.'
  }
  dependsOn: [
    logAnalyticsWorkspace::windowsLogsCustomTable
  ]
}

@description('Add logs data collection rules to Windows virtual machines.')
resource configureWindowsMachinesWithLogsDataCollectionRulePolicyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('workload', 'dca-windows-logs', configureWindowsMachinesWithDataCollectionRulePolicy.id, resourceGroup().id)
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: take('${policyAssignmentNamePrefix} Configure Windows virtual machines with logs data collection rules', 120)
    description: take(configureWindowsMachinesWithDataCollectionRulePolicy.properties.description, 500)
    enforcementMode: 'Default'
    policyDefinitionId: configureWindowsMachinesWithDataCollectionRulePolicy.id
    parameters: {
      effect: {
        value: 'DeployIfNotExists'
      }
      dcrResourceId: {
        value: windowsVmLogsCustomDataCollectionRule.id
      }
      resourceType: {
        value: windowsVmLogsCustomDataCollectionRule.type
      }
    }
  }
  dependsOn: []
}

@description('Ensure the managed identity for logs DCR DINE policies is has needed permissions.')
resource dineWindowsLogsDcrPolicyLogAnalyticsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, logAnalyticsContributorRole.id, configureWindowsMachinesWithLogsDataCollectionRulePolicyAssignment.id)
  properties: {
    principalId: configureWindowsMachinesWithLogsDataCollectionRulePolicyAssignment.identity.principalId
    roleDefinitionId: logAnalyticsContributorRole.id
    principalType: 'ServicePrincipal'
  }
}

@description('Ensure the managed identity for logs DCR DINE policies is has needed permissions.')
resource dineWindowsLogsDcrPolicyMonitoringContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, monitoringContributorRole.id, configureWindowsMachinesWithLogsDataCollectionRulePolicyAssignment.id)
  properties: {
    principalId: configureWindowsMachinesWithLogsDataCollectionRulePolicyAssignment.identity.principalId
    roleDefinitionId: monitoringContributorRole.id
    principalType: 'ServicePrincipal'
  }
}

@description('Enable the change tracking features of Azure Monitor')
resource changeTrackingTablesSolutions 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'ChangeTracking(${logAnalyticsWorkspace.name})'
  location: location
  plan: {
    name: 'ChangeTracking(${logAnalyticsWorkspace.name})'
    publisher: 'Microsoft'
    promotionCode: ''
    product: 'OMSGallery/ChangeTracking'
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
}

@description('Data collection rule for Windows virtual machines.')
resource windowsVmDataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcrWindowsEventsAndMetrics'
  location: location
  kind: 'Windows'
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'VMInsightsPerfCounters'
          samplingFrequencyInSeconds: 60
          streams: [
            'Microsoft-InsightsMetrics'
          ]
          counterSpecifiers: [
            '\\VmInsights\\DetailedMetrics'
          ]
        }
      ]
      extensions: [
        {
          name: 'CTDataSource-Windows'
          extensionName: 'ChangeTracking-Windows'
          streams: [
            'Microsoft-ConfigurationChange'
            'Microsoft-ConfigurationChangeV2'
            'Microsoft-ConfigurationData'
          ]
          extensionSettings: {
            enableFiles: true
            enableSoftware: true
            enableRegistry: true
            enableServices: true
            enableInventory: true
            registrySettings: {
              registryCollectionFrequency: 3000
              registryInfo: [
                {
                  name: 'Registry_1'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Group Policy\\Scripts\\Startup'
                  valueName: ''
                }
                {
                  name: 'Registry_2'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Group Policy\\Scripts\\Shutdown'
                  valueName: ''
                }
                {
                  name: 'Registry_3'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Run'
                  valueName: ''
                }
                {
                  name: 'Registry_4'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Active Setup\\Installed Components'
                  valueName: ''
                }
                {
                  name: 'Registry_5'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Classes\\Directory\\ShellEx\\ContextMenuHandlers'
                  valueName: ''
                }
                {
                  name: 'Registry_6'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Classes\\Directory\\Background\\ShellEx\\ContextMenuHandlers'
                  valueName: ''
                }
                {
                  name: 'Registry_7'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Classes\\Directory\\Shellex\\CopyHookHandlers'
                  valueName: ''
                }
                {
                  name: 'Registry_8'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\ShellIconOverlayIdentifiers'
                  valueName: ''
                }
                {
                  name: 'Registry_9'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Explorer\\ShellIconOverlayIdentifiers'
                  valueName: ''
                }
                {
                  name: 'Registry_10'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Browser Helper Objects'
                  valueName: ''
                }
                {
                  name: 'Registry_11'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Browser Helper Objects'
                  valueName: ''
                }
                {
                  name: 'Registry_12'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Internet Explorer\\Extensions'
                  valueName: ''
                }
                {
                  name: 'Registry_13'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\Internet Explorer\\Extensions'
                  valueName: ''
                }
                {
                  name: 'Registry_14'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Drivers32'
                  valueName: ''
                }
                {
                  name: 'Registry_15'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\Windows NT\\CurrentVersion\\Drivers32'
                  valueName: ''
                }
                {
                  name: 'Registry_16'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\KnownDlls'
                  valueName: ''
                }
                {
                  name: 'Registry_17'
                  groupTag: 'Recommended'
                  enabled: false
                  recurse: true
                  description: ''
                  keyName: 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon\\Notify'
                  valueName: ''
                }
              ]
            }
            fileSettings: {
              fileCollectionFrequency: 2700
            }
            softwareSettings: {
              softwareCollectionFrequency: 1800
            }
            inventorySettings: {
              inventoryCollectionFrequency: 36000
            }
            servicesSettings: {
              serviceCollectionFrequency: 1800
            }
          }
        }
        {
          streams: [
            'Microsoft-ServiceMap'
          ]
          extensionName: 'DependencyAgent'
          name: 'DependencyAgentDataSource'
          extensionSettings: {}
        }
      ]
      windowsEventLogs: [
        {
          name: 'eventLogsDataSource'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            'Application!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]'
            'Security!*[System[(band(Keywords,13510798882111488))]]'
            'System!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]'
          ]
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ConfigurationChange'
          'Microsoft-ConfigurationChangeV2'
          'Microsoft-ConfigurationData'
        ]
        destinations: [
          logAnalyticsWorkspace.name
        ]
      }
      {
        streams: [
          'Microsoft-InsightsMetrics'
        ]
        destinations: [
          logAnalyticsWorkspace.name
        ]
      }
      {
        streams: [
          'Microsoft-Event'
        ]
        destinations: [
          logAnalyticsWorkspace.name
        ]
        transformKql: 'source'
        outputStream: 'Microsoft-Event'
      }
      {
        streams: [
          'Microsoft-ServiceMap'
        ]
        destinations: [
          logAnalyticsWorkspace.name
        ]
      }
    ]
    destinations: {
      azureMonitorMetrics: {
        name: 'azureMonitorMetrics-default'
      }
      logAnalytics: [
        {
          name: logAnalyticsWorkspace.name
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    description: 'Default data collection rule for Windows virtual machine.'
  }
  dependsOn: [
    changeTrackingTablesSolutions
  ]
}

@description('Add data collection rules to Windows virtual machines.')
resource configureWindowsMachinesWithDataCollectionRulePolicyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('workload', 'dca-windows', configureWindowsMachinesWithDataCollectionRulePolicy.id, resourceGroup().id)
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: take('${policyAssignmentNamePrefix} Configure Windows virtual machines with data collection rules', 120)
    description: take(configureWindowsMachinesWithDataCollectionRulePolicy.properties.description, 500)
    enforcementMode: 'Default'
    policyDefinitionId: configureWindowsMachinesWithDataCollectionRulePolicy.id
    parameters: {
      effect: {
        value: 'DeployIfNotExists'
      }
      dcrResourceId: {
        value: windowsVmDataCollectionRule.id
      }
      resourceType: {
        value: windowsVmDataCollectionRule.type
      }
    }
  }
  dependsOn: [
    changeTrackingTablesSolutions
  ]
}

@description('Ensure the managed identity for DCR DINE policies is has needed permissions.')
resource dineWindowsDcrPolicyLogAnalyticsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, logAnalyticsContributorRole.id, configureWindowsMachinesWithDataCollectionRulePolicyAssignment.id)
  properties: {
    principalId: configureWindowsMachinesWithDataCollectionRulePolicyAssignment.identity.principalId
    roleDefinitionId: logAnalyticsContributorRole.id
    principalType: 'ServicePrincipal'
  }
}

@description('Ensure the managed identity for DCR DINE policies is has needed permissions.')
resource dineWindowsDcrPolicyMonitoringContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, monitoringContributorRole.id, configureWindowsMachinesWithDataCollectionRulePolicyAssignment.id)
  properties: {
    principalId: configureWindowsMachinesWithDataCollectionRulePolicyAssignment.identity.principalId
    roleDefinitionId: monitoringContributorRole.id
    principalType: 'ServicePrincipal'
  }
}

@description('Data collection rule for Linux virtual machines.')
resource linuxVmDataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcrLinuxSyslogAndMetrics'
  location: location
  kind: 'Linux'
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'VMInsightsPerfCounters'
          samplingFrequencyInSeconds: 60
          streams: [
            'Microsoft-InsightsMetrics'
          ]
          counterSpecifiers: [
            '\\VmInsights\\DetailedMetrics'
          ]
        }
      ]
      extensions: [
        {
          name: 'CTDataSource-Linux'
          extensionName: 'ChangeTracking-Linux'
          streams: [
            'Microsoft-ConfigurationChange'
            'Microsoft-ConfigurationChangeV2'
            'Microsoft-ConfigurationData'
          ]
          extensionSettings: {
            enableFiles: true
            enableSoftware: true
            enableRegistry: false
            enableServices: true
            enableInventory: true
            fileSettings: {
              fileCollectionFrequency: 900
              fileInfo: [
                {
                  name: 'ChangeTrackingLinuxPath_default'
                  enabled: true
                  destinationPath: '/etc/.*.conf'
                  useSudo: true
                  recurse: true
                  maxContentsReturnable: 5000000
                  pathType: 'File'
                  type: 'File'
                  links: 'Follow'
                  maxOutputSize: 500000
                  groupTag: 'Recommended'
                }
              ]
            }
            softwareSettings: {
              softwareCollectionFrequency: 300
            }
            inventorySettings: {
              inventoryCollectionFrequency: 36000
            }
            servicesSettings: {
              serviceCollectionFrequency: 300
            }
          }
        }
        {
          name: 'DependencyAgentDataSource'
          extensionName: 'DependencyAgent'
          streams: [
            'Microsoft-ServiceMap'
          ]
          extensionSettings: {}
        }
      ]
      syslog: [
        {
          name: 'eventLogsDataSource-info'
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            'auth'
            'authpriv'
          ]
          logLevels: [
            'Info'
            'Notice'
            'Warning'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
        }
        {
          name: 'eventLogsDataSource-notice'
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            'cron'
            'daemon'
            'mark'
            'kern'
            'local0'
            'local1'
            'local2'
            'local3'
            'local4'
            'local5'
            'local6'
            'local7'
            'lpr'
            'mail'
            'news'
            'syslog'
            'user'
            'uucp'
          ]
          logLevels: [
            'Notice'
            'Warning'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ConfigurationChange'
          'Microsoft-ConfigurationChangeV2'
          'Microsoft-ConfigurationData'
        ]
        destinations: [
          logAnalyticsWorkspace.name
        ]
      }
      {
        streams: [
          'Microsoft-InsightsMetrics'
        ]
        destinations: [
          logAnalyticsWorkspace.name
        ]
      }
      {
        streams: [
          'Microsoft-ServiceMap'
        ]
        destinations: [
          logAnalyticsWorkspace.name
        ]
      }
      {
        streams: [
          'Microsoft-Syslog'
        ]
        destinations: [
          logAnalyticsWorkspace.name
        ]
        transformKql: 'source'
        outputStream: 'Microsoft-Syslog'
      }
    ]
    destinations: {
      logAnalytics: [
        {
          name: logAnalyticsWorkspace.name
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
    description: 'Default data collection rule for Linux virtual machines.'
  }
  dependsOn: [
    changeTrackingTablesSolutions
  ]
}

@description('Add data collection rules to Linux virtual machines.')
resource configureLinuxMachinesWithDataCollectionRulePolicyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: guid('workload', 'dca-linux', configureLinuxMachinesWithDataCollectionRulePolicy.id, resourceGroup().id)
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: take('${policyAssignmentNamePrefix} Configure Linux virtual machines with data collection rules', 120)
    description: take(configureLinuxMachinesWithDataCollectionRulePolicy.properties.description, 500)
    enforcementMode: 'Default'
    policyDefinitionId: configureLinuxMachinesWithDataCollectionRulePolicy.id
    parameters: {
      effect: {
        value: 'DeployIfNotExists'
      }
      dcrResourceId: {
        value: linuxVmDataCollectionRule.id
      }
      resourceType: {
        value: linuxVmDataCollectionRule.type
      }
    }
  }
}

/*** OUTPUTS ***/
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

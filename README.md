# Azure Infrastructure as a Service baseline

This reference implementation demonstrates a _recommended starting (baseline) infrastructure as a service architecture_ using [Virtual Machine Scale Sets](#). This implementation and document is meant to guide an interdisciplinary team or multiple distinct teams like networking, security and development through the process of getting this general purpose baseline infrastructure deployed and understanding its components.

We walk through the deployment here in a rather _verbose_ method to help you understand each component of this compute that relies on the very foundation of Virtual Machines. This guidance is meant to teach about each layer and providing you with the knowledge necessary to apply it to your workload.

## Azure Architecture Center guidance

This project has a companion set of articles that describe challenges, design patterns, and best practices for using Virtual Machine Scale Sets. You can find this article on the Azure Architecture Center at [Azure Infrastructure as a Service baseline](https://aka.ms/architecture/iaas-baseline). If you haven't reviewed it, we suggest you read it to learn about the considerations applied in the implementation. Ultimately, this is the direct implementation of that specific architectural guidance.

## Architecture

**This architecture is infrastructure focused**, more so than on workload. It concentrates on the VMSS itself, including concerns with identity, bootstrapping configuration, secret management, and network topologies.

The implementation presented here is the _minimum recommended baseline. This implementation integrates with Azure services that will deliver observability, provide a network topology that will support multi-regional growth, and keep the traffic secure. This architecture should be considered your starting point for pre-production and production stages.

The material here is relatively dense. We strongly encourage you to dedicate time to walk through these instructions, with a mind to learning. We do NOT provide any "one click" deployment here. However, once you've understood the components involved and identified the shared responsibilities between your team and your great organization, it is encouraged that you build suitable, auditable deployment processes around your final infrastructure.

Throughout the reference implementation, you will see reference to _Contoso_. Contoso is a fictional fast-growing startup that provides online web services to its clientele on the west coast of North America. The company has on-premise data centers and all their line of business applications are now about to be orchestrated by secure, enterprise-ready Infrastructure as a Service using Virtual Machine Scale Sets. You can read more about [their requirements and their IT team composition](./docs/contoso/README.md). This narrative provides grounding for some implementation details, naming conventions, etc. You should adapt as you see fit.

Finally, this implementation uses [Nginx](https://nginx.org) as an example workload in the the frontend and backend VMs. This workload is purposefully uninteresting, as it is here exclusively to help you experience the baseline infrastructure.

### Core architecture components

#### Azure platform

- VMSS
  - [Availability Zones](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-use-availability-zones)
  - [Flex orchestration mode](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-orchestration-modes)
  - Monitoring: [VM Insights](https://learn.microsoft.com/azure/azure-monitor/vm/vminsights-overview)
  - Security: [Automatic Guest Patching](https://learn.microsoft.com/azure/virtual-machines/automatic-vm-guest-patching)
  - Extensions
    1. [Azure Monitor Agent](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-manage?toc=%2Fazure%2Fvirtual-machines%2Ftoc.json&tabs=azure-portal)
    1. _Preview_ [Application Health](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-health-extension)
    1. Azure KeyVaut [Linux](https://learn.microsoft.com/azure/virtual-machines/extensions/key-vault-linux) and [Windows](https://learn.microsoft.com/azure/virtual-machines/extensions/key-vault-windows?tabs=version3)
    1. Custom Script for [Linux](https://learn.microsoft.com/azure/virtual-machines/extensions/custom-script-linux) and [Windows](https://learn.microsoft.com/azure/virtual-machines/extensions/custom-script-windows)
    1. [Automatic Extension Upgrades](https://learn.microsoft.com/azure/virtual-machines/automatic-extension-upgrade)
  - [Autoscale](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-autoscale-overview)
  - [Ephemeral OS disks](https://learn.microsoft.com/en-us/azure/virtual-machines/ephemeral-os-disks)
  - Managed Identities
- Azure Virtual Networks
- Azure Application Gateway (WAF)
- Internal Load Balancers
- Azure Load Balancer egress

#### In-VM OSS components

- [NGINX](http://nginx.org/)

![Diagram depicting the IaaS Baseline architecture.](./iaas-baseline-components-overview.png)

## Deploy the reference implementation

A deployment of VM-hosted workloads typically experiences a separation of duties and lifecycle management in the area of prerequisites, the host network, the compute infrastructure, and finally the workload itself. This reference implementation is similar. Also, be aware our primary purpose is to illustrate the topology and decisions of a baseline infrastructure as a service. We feel a "step-by-step" flow will help you learn the pieces of the solution and give you insight into the relationship between them. Ultimately, lifecycle/SDLC management of your compute and its dependencies will depend on your situation (team roles, organizational standards, etc), and will be implemented as appropriate for your needs.

**Please start this learning journey in the _Preparing for the VMs_ section.** If you follow this through to the end, you'll have our recommended baseline infrastructure as a service installed, with an end-to-end sample workload running for you to reference in your own Azure subscription.

### 1. :rocket: Preparing

There are considerations that must be addressed before you start deploying your compute. Do I have enough permissions in my subscription and AD tenant to do a deployment of this size? How much of this will be handled by my team directly vs having another team be responsible?

| :clock10: | These steps are intentionally verbose, intermixed with context, narrative, and guidance. The deployments are all conducted via [Bicep templates](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview), but they are executed manually via `az cli` commands. We strongly encourage you to dedicate time to walk through these instructions, with a focus on learning. We do not provide any "one click" method to complete all deployments.<br><br>Once you understand the components involved and have identified the shared responsibilities between your team and your greater organization, you are encouraged to build suitable, repeatable deployment processes around your final infrastructure and bootstrapping. The [DevOps archicture design](https://learn.microsoft.com/azure/architecture/guide/devops/devops-start-here) is a great place to learn best practices to build your own automation pipelines. |
|-----------|:--------------------------|

1. An Azure subscription.

   The subscription used in this deployment cannot be a [free account](https://azure.microsoft.com/free); it must be a standard EA, pay-as-you-go, or Visual Studio benefit subscription. This is because the resources deployed here are beyond the quotas of free subscriptions.

1. Login into the Azure subscription that you'll be deploying into.

   ```bash
   az login
   export TENANTID_AZSUBSCRIPTION_IAAS_BASELINE=$(az account show --query tenantId -o tsv)
   echo TENANTID_AZSUBSCRIPTION_IAAS_BASELINE: $TENANTID_AZSUBSCRIPTION_IAAS_BASELINE
   TENANTS=$(az rest --method get --url https://management.azure.com/tenants?api-version=2020-01-01 --query 'value[].{TenantId:tenantId,Name:displayName}' -o table)
   ```

1. Validate your saved Azure subscription's tenant id is correct

   ```bash
   echo "${TENANTS}" | grep -z ${TENANTID_AZSUBSCRIPTION_IAAS_BASELINE}
   ```

   :warning: Do not procced if the tenant highlighted in red is not correct. Start over by `az login` into the proper Azure subscription.

1. The user or service principal initiating the deployment process _must_ have the following minimal set of Azure Role-Based Access Control (RBAC) roles:

   * [Contributor role](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#contributor) is _required_ at the subscription level to have the ability to create resource groups and perform deployments.
   * [User Access Administrator role](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#user-access-administrator) is _required_ at the subscription level since you'll be performing role assignments to managed identities across various resource groups.

1. Latest [Azure CLI installed](https://learn.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest) (must be at least 2.40), or you can perform this from Azure Cloud Shell by clicking below.

   [![Launch Azure Cloud Shell](https://learn.microsoft.com/azure/includes/media/cloud-shell-try-it/launchcloudshell.png)](https://shell.azure.com)

1. Clone/download this repo locally, or even better fork this repository.

   > :twisted_rightwards_arrows: If you have forked this reference implementation repo, you'll be able to customize some of the files and commands for a more personalized and production-like experience; ensure references to this git repository mentioned throughout the walk-through are updated to use your own fork.

   ```bash
   git clone https://github.com/mspnp/iaas-baseline.git
   cd iaas-baseline
   ```

   > :bulb: The steps shown here and elsewhere in the reference implementation use Bash shell commands. On Windows, you can use the [Windows Subsystem for Linux](https://learn.microsoft.com/windows/wsl/about) to run Bash.

1. Ensure [OpenSSL is installed](https://github.com/openssl/openssl#download) in order to generate self-signed certs used in this implementation. _OpenSSL is already installed in Azure Cloud Shell._

   > :warning: Some shells may have the `openssl` command aliased for LibreSSL. LibreSSL will not work with the instructions found here. You can check this by running `openssl version` and you should see output that says `OpenSSL <version>` and not `LibreSSL <version>`.

1. Set a variable for the domain that will be used in the rest of this deployment.

   ```bash
   export DOMAIN_NAME_IAAS_BASELINE="contoso.com"
   ```

1. Generate a client-facing, self-signed TLS certificate.

   > :book: Contoso needs to procure a CA certificate for the web site. As this is going to be a user-facing site, they purchase an EV cert from their CA. This will be served in front of the Azure Application Gateway. They will also procure another one, a standard cert, and the certificate to implement TLS communication among the VMs in the environment. The second one is not EV, as it will not be user facing.

   :warning: Do not use the certificate created by this script for your solutions. Self-signed certificates are used here for illustration purposes only. For your compute infrastructure, use your organization's requirements for procurement and lifetime management of TLS certificates, _even for development purposes_.

   Create the certificate that will be presented to web clients by Azure Application Gateway.

   ```bash
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 -out appgw.crt -keyout appgw.key -subj "/CN=${DOMAIN_NAME_IAAS_BASELINE}/O=Contoso" -addext "subjectAltName = DNS:${DOMAIN_NAME_IAAS_BASELINE}" -addext "keyUsage = digitalSignature" -addext "extendedKeyUsage = serverAuth"
   openssl pkcs12 -export -out appgw.pfx -in appgw.crt -inkey appgw.key -passout pass:
   ```

1. Base64 encode the client-facing certificate.

   :bulb: No matter if you used a certificate from your organization or you generated one from above, you'll need the certificate (as `.pfx`) to be Base64 encoded for proper storage in Key Vault later.

   ```bash
   export APP_GATEWAY_LISTENER_CERTIFICATE_IAAS_BASELINE=$(cat appgw.pfx | base64 | tr -d '\n')
   echo APP_GATEWAY_LISTENER_CERTIFICATE_IAAS_BASELINE: $APP_GATEWAY_LISTENER_CERTIFICATE_IAAS_BASELINE
   ```

1. Generate the wildcard certificate for the VMs.

   > :book: Contoso will also procure another TLS certificate, a standard cert, to be used by the VMs. This one is not EV, as it will not be user facing. The app team decided to use a wildcard certificate `*.iaas-ingress.contoso.com` for both the frontend and backend endpoints.

   ```bash
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 -out nginx-ingress-internal-iaas-ingress-tls.crt -keyout nginx-ingress-internal-iaas-ingress-tls.key -subj "/CN=*.iaas-ingress.${DOMAIN_NAME_IAAS_BASELINE}/O=Contoso IaaS Ingresses"
   ```

1. Base64 encode the VMs certificate.

   :bulb: Regardless of whether you used a certificate from your organization or generated one with the instructions provided in this document, you'll need the public certificate (as `.crt` or `.cer`) to be Base64 encoded for proper storage in Key Vault.

   ```bash
   export VMSS_WILDCARD_CERTIFICATE_BASE64_IAAS_BASELINE=$(cat nginx-ingress-internal-iaas-ingress-tls.crt | base64 | tr -d '\n')
   echo VMSS_WILDCARD_CERTIFICATE_BASE64_IAAS_BASELINE: $VMSS_WILDCARD_CERTIFICATE_BASE64_IAAS_BASELINE
   ```

1. Format to PKCS12 the wildcard certificate for `*.iaas-ingress.contoso.com`.

   :warning: If you already have access to an [appropriate certificate](https://learn.microsoft.com/azure/key-vault/certificates/certificate-scenarios#formats-of-import-we-support), or can procure one from your organization, consider using it for this step. For more information, please take a look at the [import certificate tutorial using Azure Key Vault](https://learn.microsoft.com/azure/key-vault/certificates/tutorial-import-certificate#import-a-certificate-to-key-vault).

   :warning: Do not use the certificate created by this script for your solutions. Self-signed certificates are used here for  illustration purposes only. In your solutions, use your organization's requirements for procurement and lifetime management of TLS certificates, _even for development purposes_.

   ```bash
   openssl pkcs12 -export -out nginx-ingress-internal-iaas-ingress-tls.pfx -in nginx-ingress-internal-iaas-ingress-tls.crt -inkey nginx-ingress-internal-iaas-ingress-tls.key -passout pass:
   ```

1. Base64 encode the internal wildcard certificate private and public key.

   :bulb: No matter if you used a certificate from your organization or generated one from above, you'll need the certificate (as `.pfx`) to be Base64 encoded for proper storage in Key Vault.

   ```bash
   export VMSS_WILDCARD_CERT_PUBLIC_PRIVATE_KEYS_BASE64_IAAS_BASELINE=$(cat nginx-ingress-internal-iaas-ingress-tls.pfx | base64 | tr -d '\n')
   echo VMSS_WILDCARD_CERT_PUBLIC_PRIVATE_KEYS_BASE64_IAAS_BASELINE: $VMSS_WILDCARD_CERT_PUBLIC_PRIVATE_KEYS_BASE64_IAAS_BASELINE
   ```

### 2. Create the resoure group

The following two resource groups will be created and populated with networking resources in the steps below.

| Name                            | Purpose                                   |
|---------------------------------|-------------------------------------------|
| rg-iaas-{LOCATION_IAAS_BASELINE} | Contains all of your organization's regional spokes and related networking resources. |

1. Create the networking spokes resource group.

   > :book: The networking team also keeps all of their spokes in a centrally-managed resource group. The location of this group does not matter and will not factor into where our network will live. (This resource group would have already existed or would have been part of an Azure landing zone that contains the compute resources.)

   ```bash
   LOCATION_IAAS_BASELINE=centralus
   # [This takes less than one minute to run.]
   az group create -n rg-iaas-${LOCATION_IAAS_BASELINE} -l ${LOCATION_IAAS_BASELINE}
   ```

### 3. Build the target network and deploy VMs

Microsoft recommends VMs be deployed into a carefully planned network; sized appropriately for your needs and with proper network observability. Organizations typically favor a traditional hub-spoke model, which is reflected from derivatives of this implementation such as landing zones.

This is the heart of the guidance in this reference implementation. Here you will deploy the Azure resources for your netorking, compute and the adjacent services such as Azure Application Gateway WAF, Azure Monitor, and Azure Key Vault. This is also where you will validate the VMs are bootstrapped.

1. Generate new VM authentication SSH keys by following the instructions from [Create and manage SSH keys for authentication to a Linux VM in Azure](https://learn.microsoft.com/azure/virtual-machines/linux/create-ssh-keys-detailed). Alternatively, quickly execute the following command:

   ```bash
   ssh-keygen -m PEM -t rsa -b 4096 -C "opsuser01@iaas" -f ~/.ssh/opsuser01.pem -q -N ""
   ```

   > Note: you will be able to use the Entra ID integration to authenticate as well as local users with SSH keys and/or passwords based on your preference as everything is enabled as part of this deployment. But the steps will guide you over the SSH authN process using local users(ops and/or admin) as this offers you a consistent story between Azure Linux and Windows using SSH auth type since at the time of writing this the SSH Entra ID integration is not supported in Azure Windows VMs.

1. Ensure you have **read-only** access to the private key.

   ```bash
   chmod 400 ~/.ssh/opsuser01.pem
   ```

1. Get the public SSH cert

   ```bash
   SSH_PUBLIC=$(cat ~/.ssh/opsuser01.pem.pub)
   ```

1. Set the public SSH key for the opsuser in `frontendCloudInit.yml`

   ```bash
   sed -i "s:YOUR_SSH-RSA_HERE:${SSH_PUBLIC}:" ./frontendCloudInit.yml
   ```

1. Convert your frontend cloud-init (users) file to Base64.

   ```bash
   FRONTEND_CLOUDINIT_BASE64=$(base64 frontendCloudInit.yml | tr -d '\n')
   ```

1. Deploy the compute infrastructure stamp Bicep template.
  :exclamation: By default, this deployment will allow you establish SSH and RDP connections usgin Bastion to your machines. In the case of the backend machines you are granted with admin access.

   ```bash
   # [This takes about 30 minutes.]
   az deployment group create -g rg-iaas-${LOCATION_IAAS_BASELINE} -f infra-as-code/bicep/main.bicep -p location=eastus2 frontendCloudInitAsBase64="${FRONTEND_CLOUDINIT_BASE64}" appGatewayListenerCertificate=${APP_GATEWAY_LISTENER_CERTIFICATE_IAAS_BASELINE} vmssWildcardTlsPublicCertificate=${VMSS_WILDCARD_CERTIFICATE_BASE64_IAAS_BASELINE} vmssWildcardTlsPublicAndKeyCertificates=${VMSS_WILDCARD_CERT_PUBLIC_PRIVATE_KEYS_BASE64_IAAS_BASELINE} domainName=${DOMAIN_NAME_IAAS_BASELINE} adminSecurityPrincipalObjectId="$(az ad signed-in-user show --query "id" -o tsv)"
   ```

   The deployment creation will emit the following:

     * `appGwPublicIpAddress` - The Public IP address of the Azure Application Gateway (WAF) that will receive traffic for your workload.
     * `bastionHostName` - The name of your Azure Bastion Host instance that will be used for remoting your vms.
     * `keyVaultName` - The name of your Azure KeyVault instance that stores all your TLS certs.
     * `backendAdminUserName` - The Azure backend VMs admin user name that will be used to validate connectivity with your VMs.

   > Alteratively, you could have updated the [`azuredeploy.parameters.prod.json`](./infra-as-a-code/bicep/parameters.json) file and deployed as above, using `-p "@./infra-as-a-code/bicep/parameters.json"` instead of providing the individual key-value pairs.

1. Check all your recently created VMs at the rg-iaas-${LOCATION_IAAS_BASELINE} resources group are in `running` power state

   ```bash
   az graph query -q "resources | where type =~ 'Microsoft.Compute/virtualMachines' and resourceGroup contains 'rg-iaas-${LOCATION_IAAS_BASELINE}' | extend ['8-PowerState'] = properties.extended.instanceView.powerState.code, ['1-Zone'] = tostring(zones[0]), ['2-Name'] = name, ['4-OSType'] = tostring(properties.storageProfile.osDisk.osType), ['5-OSDiskSizeGB'] = properties.storageProfile.osDisk.diskSizeGB, ['7-DataDiskSizeGB'] = tostring(properties.storageProfile.dataDisks[0].diskSizeGB), ['6-DataDiskType'] = tostring(properties.storageProfile.dataDisks[0].managedDisk.storageAccountType), ['3-VMSize'] = tostring(properties.hardwareProfile.vmSize) | project ['8-PowerState'], ['1-Zone'], ['2-Name'], ['4-OSType'], ['5-OSDiskSizeGB'], ['7-DataDiskSizeGB'], ['6-DataDiskType'], ['3-VMSize'] | sort by ['1-Zone'] asc, ['4-OSType'] asc" -o table
   ````

   ```output
   1-Zone    2-Name                     3-VMSize         4-OSType    5-OSDiskSizeGB    6-DataDiskType    7-DataDiskSizeGB    8-PowerState
   --------  -------------------------  ---------------  ----------  ----------------  ----------------  ------------------  ------------------
   1         vmss-frontend-00_e49497b3  Standard_D4s_v3  Linux       30                Premium_ZRS       4                   PowerState/running
   1         vmss-backend-00_c454e7bb   Standard_E2s_v3  Windows     30                Premium_ZRS       4                   PowerState/running
   2         vmss-frontend-00_187eb769  Standard_D4s_v3  Linux       30                Premium_ZRS       4                   PowerState/running
   2         vmss-backend-00_e4057ba4   Standard_E2s_v3  Windows     30                Premium_ZRS       4                   PowerState/running
   3         vmss-frontend-00_9d738714  Standard_D4s_v3  Linux       30                Premium_ZRS       4                   PowerState/running
   3         vmss-backend-00_6e781ed7   Standard_E2s_v3  Windows     30                Premium_ZRS       4                   PowerState/running
   ```

   :bulb: From the `Zone` column you can easily understand how you VMs were spread at provisioning time in the Azure Availablity Zones. Additionally, you will notice that only backend machines are attached with managed data disks. This list also gives you the current power state of every machine in your VMSS instances.

1. Validate all your VMs have been able to sucessfully install all the desired VM extensions

   ```bash
    az graph query -q "Resources | where type == 'microsoft.compute/virtualmachines' and resourceGroup contains 'rg-iaas-${LOCATION_IAAS_BASELINE}' | extend JoinID = toupper(id), ComputerName = tostring(properties.osProfile.computerName), VMName = name | join kind=leftouter( Resources | where type == 'microsoft.compute/virtualmachines/extensions' | extend VMId = toupper(substring(id, 0, indexof(id, '/extensions'))), ExtensionName = name ) on \$left.JoinID == \$right.VMId | summarize Extensions = make_list(ExtensionName) by VMName, ComputerName | order by tolower(ComputerName) asc" --query '[].[VMName, ComputerName, Extensions[]]' -o table
   ```

   ```output
   Column1                 Column2         Column3
   ----------------------  --------------  ------------------------------------------------------------------------------------------------------------------------------------
   vmss-backend_cde8db05   backendDWC7I3   ['DependencyAgentWindows', 'AADLogin', 'KeyVaultForWindows', 'CustomScript', 'ApplicationHealthWindows', 'AzureMonitorWindowsAgent']
   vmss-backend_c0d74d90   backendHIVL2O   ['ApplicationHealthWindows', 'KeyVaultForWindows', 'AzureMonitorWindowsAgent', 'DependencyAgentWindows', 'AADLogin', 'CustomScript']
   vmss-backend_aabab2a4   backendNNQTZW   ['ApplicationHealthWindows', 'KeyVaultForWindows', 'AzureMonitorWindowsAgent', 'CustomScript', 'DependencyAgentWindows', 'AADLogin']
   vmss-frontend_22b8ee46  frontend9MTYKM  ['AzureMonitorLinuxAgent', 'CustomScript', 'KeyVaultForLinux', 'AADSSHLogin', 'HealthExtension', 'DependencyAgentLinux']
   vmss-frontend_da993e21  frontendADLBDR  ['CustomScript', 'KeyVaultForLinux', 'DependencyAgentLinux', 'AzureMonitorLinuxAgent', 'HealthExtension', 'AADSSHLogin']
   vmss-frontend_47a941aa  frontendJVSX4A  ['AzureMonitorLinuxAgent', 'KeyVaultForLinux', 'HealthExtension', 'DependencyAgentLinux', 'AADSSHLogin', 'CustomScript']
   ```

   :bulb: From some of the extension names in `Column3` you can easily spot that the backend VMs are `Windows` machines and the frontend VMs are `Linux` machines. For more information about the VM extensions please take a look at <https://learn.microsoft.com/azure/virtual-machines/extensions/overview>.

1. Query Heath Extension substatus for your Frontend VMs and see whether your application is healthy

   ```bash
   az vm get-instance-view -g rg-iaas-${LOCATION_IAAS_BASELINE} --ids $(az vm list -g rg-iaas-${LOCATION_IAAS_BASELINE} --query "[[?contains(name,'vmss-frontend')].id]" -o tsv) --query "[*].[name, instanceView.extensions[?name=='HealthExtension'].substatuses[].message]"
   ```

   :bulb: this reports you back on application health from inside the virtual machine instance probing on a local application endpoint that happens to be `./favicon.ico` over HTTPS. This health status is used by Azure to initiate repairs on unhealthy instances and to determine if an instance is eligible for upgrade operations. Additionally, this extension can be used in situations where an external probe such as the Azure Load Balancer health probes can't be used.

   ```output
   [
     "vmss-frontend<0>",
     [
       "Application found to be healthy"
     ]
     ...
     "vmss-frontend<N>",
     [
       "Application found to be healthy"
     ]
   ]
   ```

   :exclamation: Provided the Health extension substatus message says that the "Application found to be healthy", it means your virtual machine is healthy while if the message is empty it is being considered unhealthy.

1. Query Application Heath Windows Extension substatus for your Backend VMs and see whether your application is healthy

   ```bash
   az vm get-instance-view -g rg-iaas-${LOCATION_IAAS_BASELINE} --ids $(az vm list -g rg-iaas-${LOCATION_IAAS_BASELINE} --query "[[?contains(name,'vmss-backend')].id]" -o tsv) --query "[*].[name, instanceView.extensions[?name=='ApplicationHealthWindows'].substatuses[].message]"
   ```

   :bulb: this reports you back on application health from inside the virtual machine instance probing on a local application endpoint that happens to be `./favicon.ico` over HTTPS. This health status is used by Azure to initiate repairs on unhealthy instances and to determine if an instance is eligible for upgrade operations. Additionally, this extension can be used in situations where an external probe such as the Azure Load Balancer health probes can't be used.

   ```output
   [
     "vmss-backend<0>",
     [
       "Application found to be healthy"
     ]
     ...
     "vmss-backend<N>",
     [
       "Application found to be healthy"
     ]
   ]
   ```

   :exclamation: Provided the Health extension substatus message says that the "Application found to be healthy", it means your virtual machine is healthy while if the message is empty it is being considered unhealthy.

1. Query the virtual machine scale set frontend and backend auto repair policy configuration

   ```bash
   az graph query -q "resources | where type =~ 'Microsoft.Compute/virtualMachineScaleSets' and resourceGroup contains 'rg-iaas-${LOCATION_IAAS_BASELINE}' | project ['1-Name'] = name, ['2-AutoRepairEnabled'] = properties.automaticRepairsPolicy.enabled, ['3-AutoRepairEnabledGracePeriod'] = properties.automaticRepairsPolicy.gracePeriod" -o table
   ```

   :bulb: If the auto repair is enabled and an instance is found to be unhealthy, then the scale set performs repair action by deleting the unhealthy instance and creating a new one to replace it. At any given time, no more than 5% of the instances in the scale set are repaired through the automatic repairs policy. Grace period is the amount of time to allow the instance to return to healthy state.

   ```output
   1-Name         2-AutoRepairEnabled    3-AutoRepairEnabledGracePeriod
   -------------  ---------------------  --------------------------------
   vmss-backend   True                   PT30M
   vmss-frontend  True                   PT30M
   ```

1. Query the resources that are Non Compliance based on the Policies assigned to them

   ```bash
   az graph query -q "PolicyResources | where type == 'microsoft.policyinsights/policystates' and properties.policyAssignmentScope contains 'rg-iaas-${LOCATION_IAAS_BASELINE}' | where properties.complianceState == 'NonCompliant' | project ['1-PolicyAssignmentName'] = properties.policyAssignmentName, ['2-NonCompliantResourceId'] = properties.resourceId" -o table
   ```

   ```output
   1-PolicyAssignmentName                2-NonCompliantResourceId
   ------------------------------------  --------------------------------------------------------------------------------------------------------------------------------------------
   9c2bf0f9-855d-596c-a2b0-0439c3b5a6c3  /subscriptions/d0d422cd-e446-42aa-a2e2-e88806508d3b/resourcegroups/rg-iaas-${LOCATION_IAAS_BASELINE}/providers/microsoft.compute/virtualmachinescalesets/vmss-backend
   bba5016f-b2e2-587d-8d8c-e25c5853b5fc  /subscriptions/d0d422cd-e446-42aa-a2e2-e88806508d3b/resourcegroups/rg-iaas-${LOCATION_IAAS_BASELINE}/providers/microsoft.compute/virtualmachinescalesets/vmss-frontend
   ```

1. Get the Azure Bastion name.

   ```bash
   AB_NAME=$(az deployment group show -g rg-iaas-${LOCATION_IAAS_BASELINE} -n main --query properties.outputs.bastionHostName.value -o tsv)
   echo AB_NAME: $AB_NAME
   ```

1. Remote SSH using Bastion into a frontend VM

   ```bash
   az network bastion ssh -n $AB_NAME -g rg-iaas-${LOCATION_IAAS_BASELINE} --username opsuser01 --ssh-key ~/.ssh/opsuser01.pem --auth-type ssh-key --target-resource-id $(az graph query -q "resources | where type =~ 'Microsoft.Compute/virtualMachines' | where resourceGroup contains 'rg-iaas-${LOCATION_IAAS_BASELINE}' and name contains 'vmss-frontend'| project id" --query [0].id -o tsv)
   ```

1. Validate your workload (a Nginx instance) is running in the frontend

   ```bash
   curl https://frontend.iaas-ingress.contoso.com/ --resolve frontend.iaas-ingress.contoso.com:443:127.0.0.1 -k
   ```

1. Exit the SSH session from the frontend VM

   ```bash
   exit
   ```

1. Get the backend admin user name.

   ```bash
   BACKEND_ADMINUSERNAME=$(az deployment group show -g rg-iaas-${LOCATION_IAAS_BASELINE} -n main --query properties.outputs.backendAdminUserName.value -o tsv)
   echo BACKEND_ADMINUSERNAME: $BACKEND_ADMINUSERNAME
   ```

1. Remote SSH using Bastion into a backend VM

   ```bash
   az network bastion ssh -n $AB_NAME -g rg-iaas-${LOCATION_IAAS_BASELINE} --username $BACKEND_ADMINUSERNAME --auth-typ password --target-resource-id $(az graph query -q "resources | where type =~ 'Microsoft.Compute/virtualMachines' | where resourceGroup contains 'rg-iaas-${LOCATION_IAAS_BASELINE}' and name contains 'vmss-backend'| project id" --query [0].id -o tsv)
   ```

1. Validate your backend workload (another Nginx instance) is running in the backend

   ```bash
   curl http://127.0.0.1
   ```

1. Exit the SSH session from the backend VM

   ```bash
   exit
   ```

We perform the prior steps manually here for you to understand the involved components, but we advocate for an automated DevOps process. Therefore, incorporate the prior steps into your CI/CD pipeline, as you would any infrastructure as code (IaC).

### 5. :checkered_flag: Validation

Now that the compute and the sample workload is deployed; it's time to look at how the VMs are functioning.

#### Validate the Contoso web app

This section will help you to validate the workload is exposed correctly and responding to HTTP requests.

1. Get the public IP address of Application Gateway.

   > :book: The app team conducts a final acceptance test to be sure that traffic is flowing end-to-end as expected, so they place a request against the Azure Application Gateway endpoint.

   ```bash
   # query the Azure Application Gateway Public Ip
   APPGW_PUBLIC_IP=$(az deployment group show -g rg-iaas-${LOCATION_IAAS_BASELINE} -n main --query properties.outputs.appGwPublicIpAddress.value -o tsv)
   echo APPGW_PUBLIC_IP: $APPGW_PUBLIC_IP
   ```

1. Create an `A` record for DNS.

   > :bulb: You can simulate this via a local hosts file modification. You're welcome to add a real DNS entry for your specific deployment's application domain name, if you have access to do so.

   Map the Azure Application Gateway public IP address to the application domain name. To do that, please edit your hosts file (`C:\Windows\System32\drivers\etc\hosts` or `/etc/hosts`) and add the following record to the end: `${APPGW_PUBLIC_IP} ${DOMAIN_NAME_IAAS_BASELINE}` (e.g. `50.140.130.120  contoso.com`)

1. Validate your workload is reachable over internet through your Azure Application Gateway public endpoint

   ```bash
   curl https://contoso.com --resolve contoso.com:443:$APPGW_PUBLIC_IP -k
   ```

1. Browse to the site (e.g. <https://contoso.com>).

   > :bulb: Remember to include the protocol prefix `https://` in the URL you type in the address bar of your browser. A TLS warning will be present due to using a self-signed certificate. You can ignore it or import the self-signed cert (`appgw.pfx`) to your user's trusted root store.

   ```bash
   open https://contoso.com
   ```

   Refresh the web page a couple of times and observe the frontend and backend values `Machine name` displayed at the top of the page. As the Application Gateway and Internal Load Balancer balances the requests between the tiers, the machine names will change from one machine name to the other throughtout your queries.

#### Validate web application firewall functionality

Your workload is placed behind a Web Application Firewall (WAF), which has rules designed to stop intentionally malicious activity. You can test this by triggering one of the built-in rules with a request that looks malicious.

> :bulb: This reference implementation enables the built-in OWASP 3.0 ruleset, in **Prevention** mode.

1. Browse to the site with the following appended to the URL: `?sql=DELETE%20FROM` (e.g. <https://contoso.com/?sql=DELETE%20FROM>).
1. Observe that your request was blocked by Application Gateway's WAF rules and your workload never saw this potentially dangerous request.
1. Blocked requests (along with other gateway data) will be visible in the attached Log Analytics workspace.

   Browse to the Application Gateway in the resource group `rg-iaas-${LOCATION_IAAS_BASELINE}` and navigate to the _Logs_ blade. Execute the following query below to show WAF logs and see that the request was rejected due to a _SQL Injection Attack_ (field _Message_).

   > :warning: Note that it may take a couple of minutes until the logs are transferred from the Application Gateway to the Log Analytics Workspace. So be a little patient if the query does not immediatly return results after sending the https request in the former step.

   ```
   AzureDiagnostics
   | where ResourceProvider == "MICROSOFT.NETWORK" and Category == "ApplicationGatewayFirewallLog"
   ```

#### Validate Azure Monitor VM insights and logs

1. Monitoring your compute infrastructure is critical, especially when you're running in production. Therefore, your VMs are configured with [boot diagnostics](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/boot-diagnostics) and to send [diagnostic information](https://learn.microsoft.com/azure/azure-monitor/essentials/diagnostic-settings?tabs=portal) to the Log Analytics Workspace deployed as part of the [bootstrapping step](./05-bootstrap-prep.md).

   ```bash
   az vm boot-diagnostics get-boot-log --ids $(az vm list -g rg-iaas-${LOCATION_IAAS_BASELINE} --query "[].id" -o tsv)
   ```

1. In the Azure Portal, navigate to your VM resources.
1. Click _Insights_ to see captured data. For more infomation please take a look at <https://learn.microsoft.com/azure/azure-monitor/vm/vminsights-overview>.

You can also execute [queries](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-tutorial) on the [VM Insights logs captured](https://learn.microsoft.com/azure/azure-monitor/vm/vminsights-log-query).

1. In the Azure Portal, navigate to your VMSS resources.
1. Click _Logs_ to see and query log data.

#### Monitor your Windows VM logs

1. Get the Log Analytics Workspace Id.

   ```bash
   LA_WORKSPACEID=$(az deployment group show -g rg-iaas-${LOCATION_IAAS_BASELINE} -n main --query properties.outputs.logAnalyticsWorkspaceId.value -o tsv)
   echo LA_WORKSPACEID: $LA_WORKSPACEID
   ```

1. Check your Azure Monitor Agents within the last three minutes sent heartbeats to Log Analytics

   ```bash
   az monitor log-analytics query -w $LA_WORKSPACEID --analytics-query "Heartbeat | where TimeGenerated > ago(3m) | where ResourceGroup has 'rg-iaas-${LOCATION_IAAS_BASELINE}' | project  Computer, TimeGenerated, Category, Version | order by TimeGenerated desc" -o table
   ```

   ```output
   Category             Computer        TableName      TimeGenerated                 Version
   -------------------  --------------  -------------  ----------------------------  ---------
   Azure Monitor Agent  frontend33W1H1  PrimaryResult  2023-08-03T18:23:53.9882669Z  1.27.4
   Azure Monitor Agent  frontendUZHWTP  PrimaryResult  2023-08-03T18:23:52.5931826Z  1.27.4
   Azure Monitor Agent  frontendF6YYWG  PrimaryResult  2023-08-03T18:23:38.2812975Z  1.27.4
   Azure Monitor Agent  backendRZRPWY   PrimaryResult  2023-08-03T18:23:29.5531509Z  1.18.0.0
   Azure Monitor Agent  frontend33W1H1  PrimaryResult  2023-08-03T18:22:54.0179506Z  1.27.4
   Azure Monitor Agent  frontendUZHWTP  PrimaryResult  2023-08-03T18:22:52.6105985Z  1.27.4
   Azure Monitor Agent  frontendF6YYWG  PrimaryResult  2023-08-03T18:22:38.2799208Z  1.27.4
   Azure Monitor Agent  backendYDTYW7   PrimaryResult  2023-08-03T18:22:30.6282239Z  1.18.0.0
   Azure Monitor Agent  backendRZRPWY   PrimaryResult  2023-08-03T18:22:29.5507687Z  1.18.0.0
   ...
   ```

1. Query your DCR based custom table to check if any custom logs have been received

   ```bash
   az monitor log-analytics query -w $LA_WORKSPACEID --analytics-query "WindowsLogsTable_CL | where TimeGenerated > ago(48h) | project RawData, TimeGenerated, _ResourceId | order by TimeGenerated desc" -t P3DT12H -o table
   ```

   ```output
   RawData                                                                    TableName      TimeGenerated                 _ResourceId
   ------------------------------------------------------------------------   -------------  ----------------------------  --------------------------------------------------------------------------------------------------------------------------------------------
   10.240.0.4 - - [15/Aug/2023:14:54:38 +0000] "GET / HTTP/1.0" 200 7741...   PrimaryResult  2023-08-15T14:58:00.3130909Z  /subscriptions/<YOUR_SUSBSCRIPTION_ID>/resourcegroups/rg-iaas-${LOCATION_IAAS_BASELINE}/providers/microsoft.compute/virtualmachines/vmss-backend_57752db5
   10.240.0.6 - - [15/Aug/2023:14:54:40 +0000] "GET / HTTP/1.0" 200 7741...   PrimaryResult  2023-08-15T14:58:00.3130909Z  /subscriptions/<YOUR_SUSBSCRIPTION_ID>/resourcegroups/rg-iaas-${LOCATION_IAAS_BASELINE}/providers/microsoft.compute/virtualmachines/vmss-backend_57752db5
   10.240.0.5 - - [15/Aug/2023:14:54:38 +0000] "GET / HTTP/1.0" 200 7741...   PrimaryResult  2023-08-15T14:57:46.269107Z   /subscriptions/<YOUR_SUSBSCRIPTION_ID>/resourcegroups/rg-iaas-${LOCATION_IAAS_BASELINE}/providers/microsoft.compute/virtualmachines/vmss-backend_9949700b
   ...
   ```

   :warning: it might take some time to sink logs into Log Analytics.

## :broom: Clean up resources

Most of the Azure resources deployed in the prior steps will incur ongoing charges unless removed.

1. Obtain the Azure KeyVault resource name

   ```bash
   export KEYVAULT_NAME_IAAS_BASELINE=$(az deployment group show -g rg-iaas-${LOCATION_IAAS_BASELINE} -n main --query properties.outputs.keyVaultName.value -o tsv)
   echo KEYVAULT_NAME_IAAS_BASELINE: $KEYVAULT_NAME_IAAS_BASELINE
   ```

1. Delete the resource groups as a way to delete all contained Azure resources.

   > To delete all Azure resources associated with this reference implementation, you'll need to delete the three resource groups created.

   :warning: Ensure you are using the correct subscription, and validate that the only resources that exist in these groups are ones you're okay deleting.

   ```bash
   az group delete -n rg-iaas-${LOCATION_IAAS_BASELINE}
   ```

1. Purge Azure Key Vault

   > Because this reference implementation enables soft delete on Key Vault, execute a purge so your next deployment of this implementation doesn't run into a naming conflict.

   ```bash
   az keyvault purge -n $KEYVAULT_NAME_IAAS_BASELINE
   ```

1. If any temporary changes were made to Entra ID or Azure RBAC permissions consider removing those as well.

### Automation

Before you can automate a process, it's important to experience the process in a bit more raw form as was presented here. That experience allows you to understand the various steps, inner- & cross-team dependencies, and failure points along the way. However, the steps provided in this walkthrough are not specifically designed with automation in mind. It does present a perspective on some common seperation of duties often encountered in organizations, but that might not align with your organization.

Now that you understand the components involved and have identified the shared responsibilities between your team and your greater organization, you are encouraged to build repeatable deployment processes around your final infrastructure and compute bootstrapping. Please refer to the [DevOps architecture designs](https://learn.microsoft.com/azure/architecture/guide/devops/devops-start-here) to learn how GitHub Actions combined with Infrastructure as Code can be used to facilitate this automation.

## Related reference implementations

The Infrastructure as a Service baseline was used as the foundation for the following additional reference implementations:

- [Virtual machine baseline for Azure landing zones](https://github.com/mspnp/iaas-landing-zone-baseline)

## Advanced topics

This reference implementation intentionally does not cover more advanced scenarios. For example topics like the following are not addressed:

- Compute lifecycle management with regard to SDLC and GitOps
- Workload SDLC integration
- Multiple (related or unrelated) workloads owned by the same team
- Multiple workloads owned by disparate teams (VMs as a shared platform in your organization)
- [Autoscaling](https://learn.microsoft.com/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-autoscale-overview)

Keep watching this space, as we build out reference implementation guidance on topics such as these. Further guidance delivered will use this baseline infrastructure as a service implementation as their starting point. If you would like to contribute or suggest a pattern built on this baseline, [please get in touch](./CONTRIBUTING.md).

## Related documentation

- [Virtual Machine Scale Sets Documentation](https://learn.microsoft.com/azure/virtual-machine-scale-sets/)
- [Microsoft Azure Well-Architected Framework](https://learn.microsoft.com/azure/architecture/framework/)

## Contributions

Please see our [contributor guide](./CONTRIBUTING.md).

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact <opencode@microsoft.com> with any additional questions or comments.

With :heart: from Microsoft Patterns & Practices, [Azure Architecture Center](https://aka.ms/architecture).

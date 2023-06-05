# Deploy a virtual network

The prerequisites for the [IaaS baseline](./) are now completed with [Azure AD group and user work](./03-aad.md) performed in the prior steps. Now we will start with our first Azure resource deployment, the network resources.

## Subscription and resource group topology

We expect you to explore this reference implementation within a single subscription, but when you implement this at your organization, you will need to take what you've learned here and apply it to your expected subscription and resource group topology (such as those [offered by the Cloud Adoption Framework](https://learn.microsoft.com/azure/cloud-adoption-framework/decision-guides/subscriptions/).) This single subscription, multiple resource group model is for simplicity of demonstration purposes only.

## Expected results

### Resource groups

The following two resource groups will be created and populated with networking resources in the steps below.

| Name                            | Purpose                                   |
|---------------------------------|-------------------------------------------|
| rg-enterprise-networking-spokes | Contains all of your organization's regional spokes and related networking resources. |

### Resources

* Network spoke for the compute resources
* Network Security Groups for all subnets

## Steps

1. Login into the Azure subscription that you'll be deploying into.

   > :book: The networking team logins into the Azure subscription that will contain the regional spokes. At Contoso, all of their regional spokes are in the same, centrally-managed subscription.

   ```bash
   az login -t $TENANTID_AZSUBSCRIPTION_IAAS_BASELINE
   ```

1. Create the networking spokes resource group.

   > :book: The networking team also keeps all of their spokes in a centrally-managed resource group. The location of this group does not matter and will not factor into where our network will live. (This resource group would have already existed or would have been part of an Azure landing zone that contains the compute resources.)

   ```bash
   # [This takes less than one minute to run.]
   az group create -n rg-enterprise-networking-spokes -l centralus
   ```

1. Create the spoke that will be home to the compute and its adjacent resources.

   > :book: The networking team receives a request from an app team in business unit (BU) 0001 for a network spoke to house their new VM-based application (Internally know as Application ID: A0008). The network team talks with the app team to understand their requirements and aligns those needs with Microsoft's best practices for a general-purpose compute deployment. They capture those specific requirements and deploy the spoke.

   ```bash
   # [This takes about four minutes to run.]
   az deployment group create -g rg-enterprise-networking-spokes -f networking/spoke-BU0001A0008.bicep -p location=eastus2
   ```

   The spoke creation will emit the following:

     * `appGwPublicIpAddress` - The Public IP address of the Azure Application Gateway (WAF) that will receive traffic for your workload.
     * `spokeVnetResourceId` - The resource ID of the Virtual network where the VMs, App Gateway, and related resources will be deployed. E.g. `/subscriptions/[id]/resourceGroups/rg-enterprise-networking-spokes/providers/Microsoft.Network/virtualNetworks/vnet-spoke-BU0001A0008-00`
     * `vmssSubnetResourceIds` - The resource IDs of the Virtual network subnets for the VMs. E.g. `[ /subscriptions/[id]/resourceGroups/rg-enterprise-networking-spokes/providers/Microsoft.Network/virtualNetworks/vnet-spoke-BU0001A0008-00/subnet/snet-frontend, /subscriptions/[id]/resourceGroups/rg-enterprise-networking-spokes/providers/Microsoft.Network/virtualNetworks/vnet-spoke-BU0001A0008-00/subnet/snet-backend ]`

### Next step

:arrow_forward: [Deploy the compute infrastructure](./06-compute-infra.md)

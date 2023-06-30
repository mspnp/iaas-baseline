# Networking resource templates

> Note: This is part of the IaaS baseline reference implementation. For more information check out the [readme file in the root](../README.md).

These files are the Bicep templates used in the deployment of this reference implementation.

## Files

* [`networking.bicep`](../infra-as-code/bicep/networking.bicep) is a file that defines a specific vnet. A vnet is created for each workload.

Your organization will likely have its own standards and typically implement a hub-spoke topology. For the sake of simplicity, in this reference implementation we deploy a single vnet. Be sure to follow your organizational guidelines.

## Topology details

See the [IaaS baseline network topology](./topology.md) for defined subnets and IP space allocation concerns accounted for.

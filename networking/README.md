# Networking resource templates

> Note: This is part of the IaaS baseline reference implementation. For more information check out the [readme file in the root](../README.md).

These files are the Bicep templates used in the deployment of this reference implementation.

## Files

* [`vnet.bicep`](./vnet.bicep) is a file that defines a specific spoke in the topology. A spoke, in our narrative, is create for each workload in a business unit, hence the naming pattern in the file name.

Your organization will likely have its own standards for their hub-spoke implementation. Be sure to follow your organizational guidelines.

## Topology details

See the [IaaS baseline network topology](./topology.md) for defined subnets and IP space allocation concerns accounted for.

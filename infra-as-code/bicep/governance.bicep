targetScope = 'resourceGroup'

/*** PARAMETERS ***/

@description('The resource group location')
param location string = resourceGroup().location

@description('The resource group name where the AppGw is going to be deployed.')
param resourceGroupName string = resourceGroup().name

@description('This is the base name for each Azure resource name.')
param baseName string

/*** VARIABLES ***/


/*** EXISTING SUBSCRIPTION RESOURCES ***/


/*** EXISTING RESOURCES ***/


/*** RESOURCES ***/


/*** OUTPUTS ***/

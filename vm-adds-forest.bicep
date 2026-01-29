param vmName string
param location string
param domainName string
param domainNetbiosName string
param domainAdminUsername string
@secure()
param domainAdminPassword string
param ouPath string = ''


@description('DSC Modules.zip URL')
param modulesUrl string


@description('DSC configuration function')
param configurationFunction string


resource dscExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
name: '${vmName}/addc'
location: location
properties: {
publisher: 'Microsoft.Powershell'
type: 'DSC'
typeHandlerVersion: '2.83'
autoUpgradeMinorVersion: true
settings: {
modulesUrl: modulesUrl
configurationFunction: configurationFunction
properties: {
DomainName: domainName
DomainNetbiosName: domainNetbiosName
AdminCreds: {
UserName: domainAdminUsername
Password: domainAdminPassword
}
RetryCount: 20
RetryIntervalSec: 60
OuPath: ouPath
}
}
protectedSettings: {
items: {
'domainAdminPassword': domainAdminPassword
}
}
}
}

param vmName string
param location string
param vmSize string
param subnetId string
param adminUsername string
@secure()
param adminPassword string
param imageReference object
param vmIdentityType string = 'None' // 'None' | 'SystemAssigned'


resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
name: '${vmName}-nic'
location: location
properties: {
ipConfigurations: [
{
name: 'ipconfig1'
properties: {
subnet: {
id: subnetId
}
privateIPAllocationMethod: 'Dynamic'
}
}
]
}
}


resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
name: vmName
location: location
identity: {
type: vmIdentityType
}
properties: {
hardwareProfile: {
vmSize: vmSize
}
osProfile: {
computerName: vmName
adminUsername: adminUsername
adminPassword: adminPassword
}
storageProfile: {
imageReference: imageReference
osDisk: {
createOption: 'FromImage'
managedDisk: {
storageAccountType: 'Premium_LRS'
}
}
}
networkProfile: {
networkInterfaces: [
{
id: nic.id
}
]
}
}
}


output vmId string = vm.id
output privateIp string = reference(nic.id, '2024-05-01').ipConfigurations[0].properties.privateIPAddress
output principalId string = vmIdentityType == 'SystemAssigned' ? vm.identity.principalId : ''

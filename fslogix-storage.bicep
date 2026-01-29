param storageAccountName string
param location string
param shareName string
param allowedSubnetIds array


resource sa 'Microsoft.Storage/storageAccounts@2023-01-01' = {
name: storageAccountName
location: location
kind: 'StorageV2'
sku: {
name: 'Standard_LRS'
}
properties: {
minimumTlsVersion: 'TLS1_2'
supportsHttpsTrafficOnly: true
allowBlobPublicAccess: false
allowSharedKeyAccess: false
publicNetworkAccess: 'Enabled'
networkAcls: {
bypass: 'AzureServices'
defaultAction: 'Deny'
virtualNetworkRules: [
for s in allowedSubnetIds: {
id: s
action: 'Allow'
}
]
ipRules: []
}
}
}


resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
name: '${storageAccountName}/default'
}


resource share 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
name: '${storageAccountName}/default/${shareName}'
properties: {
shareQuota: 1024
}
}


output storageAccountId string = sa.id
output fileEndpoint string = sa.properties.primaryEndpoints.file

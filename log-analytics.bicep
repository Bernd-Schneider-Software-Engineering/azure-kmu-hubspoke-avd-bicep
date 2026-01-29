param name string
param location string
param retentionInDays int = 30
param skuName string = 'PerGB2018'


resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
name: name
location: location
properties: {
retentionInDays: retentionInDays
}
sku: {
name: skuName
}
}


output workspaceId string = law.id
output customerId string = law.properties.customerId

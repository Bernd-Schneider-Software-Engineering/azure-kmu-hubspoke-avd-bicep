param name string
param location string
param addressSpace string


@description('Array of subnet objects: { name, addressPrefix, natGatewayId?, nsgId? }')
param subnets array


@description('Optional DNS servers')
param dnsServers array = []


resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
name: name
location: location
properties: {
addressSpace: {
addressPrefixes: [
addressSpace
]
}
dhcpOptions: empty(dnsServers) ? null : {
dnsServers: dnsServers
}
subnets: [
for s in subnets: {
name: s.name
properties: union(
{
addressPrefix: s.addressPrefix
}
// NAT Gateway (optional)
(contains(s, 'natGatewayId') && !empty(s.natGatewayId)) ? {
natGateway: {
id: s.natGatewayId
}
} : {}
// NSG (optional)
(contains(s, 'nsgId') && !empty(s.nsgId)) ? {
networkSecurityGroup: {
id: s.nsgId
}
} : {}
)
}
]
}
}


output vnetId string = vnet.id
output subnetIds array = [for s in vnet.properties.subnets: s.id]

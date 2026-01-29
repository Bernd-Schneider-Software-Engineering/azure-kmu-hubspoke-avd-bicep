param name string
param location string


@description('Array of security rule objects (same shape as in main)')
param securityRules array = []


resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
name: name
location: location
properties: {
securityRules: [
for r in securityRules: {
name: r.name
properties: {
priority: r.priority
direction: r.direction
access: r.access
protocol: r.protocol
sourceAddressPrefix: r.sourceAddressPrefix
sourcePortRange: r.sourcePortRange
destinationAddressPrefix: r.destinationAddressPrefix
destinationPortRange: r.destinationPortRange
description: contains(r, 'description') ? r.description : ''
}
}
]
}
}


output nsgId string = nsg.id

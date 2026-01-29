// main.bicep
// HUB + 2 Spokes + NAT + Peering + 2 VMs (DC, APP) + 1 AVD VM + Azure Files (FSLogix)
// Fixes: 2/3/5/6/7/8/9

targetScope = 'subscription'

@description('Prefix (2–12 chars). Nur a-z, 0-9 und "-". Wird für alle Ressourcennamen verwendet.')
@minLength(2)
@maxLength(12)
param prefix string

@description('Azure Region')
param location string = 'westeurope'

@description('Hub RG Name')
param hubRgName string = 'rg-${prefix}-hub'

@description('Infra RG Name')
param infraRgName string = 'rg-${prefix}-infra'

@description('AVD RG Name')
param avdRgName string = 'rg-${prefix}-avd'

@description('Address prefix for Hub VNet')
param hubVnetPrefix string = '10.0.0.0/16'

@description('Address prefix for Infra VNet')
param infraVnetPrefix string = '10.1.0.0/16'

@description('Address prefix for AVD VNet')
param avdVnetPrefix string = '10.2.0.0/16'

@description('Hub subnets')
param hubSubnetPrefixes array = [
  '10.0.0.0/24' // hub subnet
]

@description('Infra subnets')
param infraSubnetPrefixes array = [
  '10.1.0.0/24' // DC subnet
  '10.1.1.0/24' // APP subnet
]

@description('AVD subnets')
param avdSubnetPrefixes array = [
  '10.2.0.0/24' // AVD Session Hosts
  '10.2.1.0/24' // FSLogix / Files
]

@description('Subnet names')
param hubSubnetName string = 'snet-hub'
param dcSubnetName string = 'snet-dc'
param appSubnetName string = 'snet-app'
param avdSubnetName string = 'snet-avd'
param fslogixSubnetName string = 'snet-fslogix'

@description('VM admin username (local admin für Bootstrap)')
param adminUsername string = 'azureadmin'

@description('VM admin password (secure)')
@secure()
param adminPassword string

// AD Domain
@description('AD DS Domain FQDN')
param domainName string = 'corp.local'

@description('Domain NetBIOS name')
param domainNetbiosName string = 'CORP'

@description('Domain Admin username')
param domainAdminUsername string = 'domainadmin'

@description('Domain Admin password (secure)')
@secure()
param domainAdminPassword string

@description('OU Distinguished Name (optional). Leer = Default-Container.')
param ouPath string = ''

// =====================
// Punkt 7: Prefix-Validierung (ohne Regex in Bicep)
// =====================
var prefixLower = toLower(prefix)
var prefixLc = (prefixLower == prefix) ? prefix : fail('prefix muss komplett lowercase sein (a-z, 0-9, -).')

// Remove allowed chars; if anything remains -> fail
var stripped0 = replace(prefixLc, '-', '')
var stripped1 = replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
  stripped0,
  '0',''), '1',''), '2',''), '3',''), '4',''), '5',''), '6',''), '7',''), '8',''), '9','')

var stripped2 = replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
  stripped1,
  'a',''), 'b',''), 'c',''), 'd',''), 'e',''), 'f',''), 'g',''), 'h',''), 'i',''), 'j','')

var stripped3 = replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
  stripped2,
  'k',''), 'l',''), 'm',''), 'n',''), 'o',''), 'p',''), 'q',''), 'r',''), 's',''), 't','')

var stripped4 = replace(replace(replace(replace(replace(replace(
  stripped3,
  'u',''), 'v',''), 'w',''), 'x',''), 'y',''), 'z','')

var prefixSafe = (length(stripped4) == 0) ? prefixLc : fail('prefix darf nur a-z, 0-9 und "-" enthalten.')

// =====================
// Punkt 2: AVD Image Referenz parametriert (SKU nicht hardcoded)
// =====================
@description('AVD Image Publisher (vor Deploy per az CLI verifizieren)')
param avdImagePublisher string = 'MicrosoftWindowsDesktop'

@description('AVD Image Offer')
param avdImageOffer string = 'windows-11'

@description('AVD Image SKU (z.B. win11-23h2-avd). Muss in der Region verfügbar sein.')
param avdImageSku string = 'win11-23h2-avd'

@description('AVD Image Version: "latest" oder exakte Versionsnummer')
param avdImageVersion string = 'latest'

var avdImageReference = {
  publisher: avdImagePublisher
  offer: avdImageOffer
  sku: avdImageSku
  version: avdImageVersion
}

// VM Settings
@description('DC VM size')
param dcVmSize string = 'Standard_B2ms'

@description('APP VM size')
param appVmSize string = 'Standard_B2ms'

@description('AVD Session Host VM size')
param avdVmSize string = 'Standard_D4s_v5'

@description('Windows Server Image Reference for DC / APP')
param serverImageReference object = {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2022-datacenter'
  version: 'latest'
}

// =====================
// Punkt 5: NSGs
// =====================
@description('Management Source CIDR für RDP (z.B. Hub-Subnet oder Office VPN).')
param managementSourceCidr string = '10.0.0.0/24'

@description('Wenn true: NSGs setzen Default-Deny inbound und erlauben nur whitelisted Ports.')
param hardenNsg bool = true

// =====================
// Punkt 3: Supply-Chain für ADDS-DSC Artefakte (URL parametriert)
// =====================
@description('DSC Modules.zip URL für ADDS Setup. Empfehlung: auf eigenen Storage/Repo pinnen (Commit/Release), nicht "master".')
param addsDscModulesUrl string = 'https://github.com/Azure/azure-quickstart-templates/raw/master/quickstarts/microsoft.compute/101-vm-dsc-windows-ad/Modules.zip'

@description('DSC configuration function (Name in Modules.zip). Default: ActiveDirectoryDsc\CreateADPDC')
param addsDscConfigurationFunction string = 'ActiveDirectoryDsc\\CreateADPDC'

// =====================
// Punkt 8: Observability (Log Analytics + Diagnostics + Alerts)
// =====================
@description('Operations/Observability aktivieren (Log Analytics, Diagnostic Settings, optionale Alerts)')
param enableOps bool = true

@description('Log Analytics retention in days')
param logAnalyticsRetentionInDays int = 30

@description('Optional: Alert E-Mail. Leer = keine ActionGroup/Alerts.')
param alertEmail string = ''

// =====================
// Punkt 6: FSLogix (Auth/ACL)
// =====================
@description('FSLogix Storage Account name')
param fslogixStorageAccountName string = 'st${prefix}fslogix'

@description('FSLogix file share name')
param fslogixShareName string = 'fslogix'

@description('FSLogix Users Gruppe (NTFS) – Default: Domain Users. Passe auf eure Struktur an.')
param fslogixUsersGroupName string = 'Domain Users'

@description('FSLogix Admins Gruppe (NTFS) – Default: Domain Admins. Passe auf eure Struktur an.')
param fslogixAdminsGroupName string = 'Domain Admins'

@description('AzFilesHybrid ZIP URL (pin auf Release empfohlen). Default pinned: v0.3.2')
param azFilesHybridZipUrl string = 'https://github.com/Azure-Samples/azure-files-samples/releases/download/v0.3.2/AzFilesHybrid.zip'

// ----
// Resource Groups
// ----
resource hubRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: hubRgName
  location: location
}

resource infraRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: infraRgName
  location: location
}

resource avdRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: avdRgName
  location: location
}

// ----
// NAT Gateways
// ----
module hubNat 'modules/nat-gateway.bicep' = {
  name: 'hubNat'
  scope: hubRg
  params: {
    name: 'nat-${prefixSafe}-hub'
    location: location
  }
}

module infraNat 'modules/nat-gateway.bicep' = {
  name: 'infraNat'
  scope: infraRg
  params: {
    name: 'nat-${prefixSafe}-infra'
    location: location
  }
}

module avdNat 'modules/nat-gateway.bicep' = {
  name: 'avdNat'
  scope: avdRg
  params: {
    name: 'nat-${prefixSafe}-avd'
    location: location
  }
}

// ----
// NSGs (Punkt 5)
// ----
var dcNsgRules = hardenNsg ? [
  // Allow AD/DNS/Kerberos/LDAP/SMB/RPC inbound to DC from VirtualNetwork
  {
    name: 'Allow-AD-DNS'
    priority: 100
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '53'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'DNS TCP'
  }
  {
    name: 'Allow-AD-DNS-UDP'
    priority: 110
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Udp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '53'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'DNS UDP'
  }
  {
    name: 'Allow-AD-Kerberos'
    priority: 120
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '88'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'Kerberos TCP'
  }
  {
    name: 'Allow-AD-Kerberos-UDP'
    priority: 130
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Udp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '88'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'Kerberos UDP'
  }
  {
    name: 'Allow-AD-LDAP'
    priority: 140
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '389'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'LDAP TCP'
  }
  {
    name: 'Allow-AD-LDAPS'
    priority: 150
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '636'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'LDAPS TCP'
  }
  {
    name: 'Allow-AD-SMB'
    priority: 160
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '445'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'SMB TCP'
  }
  {
    name: 'Allow-AD-RPC-Endpoint'
    priority: 170
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '135'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'RPC endpoint mapper'
  }
  {
    name: 'Allow-AD-RPC-Dynamic'
    priority: 180
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '49152-65535'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'RPC dynamic ports'
  }
  {
    name: 'Allow-AD-GC'
    priority: 190
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '3268-3269'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'Global Catalog'
  }
  {
    name: 'Allow-AD-NTP'
    priority: 200
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Udp'
    sourceAddressPrefix: 'VirtualNetwork'
    destinationPortRange: '123'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'NTP'
  }
  // Allow RDP from management
  {
    name: 'Allow-RDP-Management'
    priority: 210
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: managementSourceCidr
    destinationPortRange: '3389'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'RDP from management range'
  }
  // Deny everything else inbound
  {
    name: 'Deny-All-Inbound'
    priority: 4096
    direction: 'Inbound'
    access: 'Deny'
    protocol: '*'
    sourceAddressPrefix: '*'
    destinationPortRange: '*'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'Default deny inbound'
  }
] : []

var appNsgRules = hardenNsg ? [
  {
    name: 'Allow-RDP-Management'
    priority: 100
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: managementSourceCidr
    destinationPortRange: '3389'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'RDP from management range'
  }
  {
    name: 'Deny-All-Inbound'
    priority: 4096
    direction: 'Inbound'
    access: 'Deny'
    protocol: '*'
    sourceAddressPrefix: '*'
    destinationPortRange: '*'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'Default deny inbound'
  }
] : []

var avdNsgRules = hardenNsg ? [
  {
    name: 'Allow-RDP-Management'
    priority: 100
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: managementSourceCidr
    destinationPortRange: '3389'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'RDP from management range'
  }
  {
    name: 'Deny-All-Inbound'
    priority: 4096
    direction: 'Inbound'
    access: 'Deny'
    protocol: '*'
    sourceAddressPrefix: '*'
    destinationPortRange: '*'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'Default deny inbound'
  }
] : []

var fslogixNsgRules = hardenNsg ? [
  {
    name: 'Deny-All-Inbound'
    priority: 4096
    direction: 'Inbound'
    access: 'Deny'
    protocol: '*'
    sourceAddressPrefix: '*'
    destinationPortRange: '*'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    description: 'Default deny inbound'
  }
] : []

module dcNsg 'modules/nsg.bicep' = {
  name: 'dcNsg'
  scope: infraRg
  params: {
    name: 'nsg-${prefixSafe}-dc'
    location: location
    securityRules: dcNsgRules
  }
}

module appNsg 'modules/nsg.bicep' = {
  name: 'appNsg'
  scope: infraRg
  params: {
    name: 'nsg-${prefixSafe}-app'
    location: location
    securityRules: appNsgRules
  }
}

module avdNsg 'modules/nsg.bicep' = {
  name: 'avdNsg'
  scope: avdRg
  params: {
    name: 'nsg-${prefixSafe}-avd'
    location: location
    securityRules: avdNsgRules
  }
}

module fslogixNsg 'modules/nsg.bicep' = {
  name: 'fslogixNsg'
  scope: avdRg
  params: {
    name: 'nsg-${prefixSafe}-fslogix'
    location: location
    securityRules: fslogixNsgRules
  }
}

// ----
// VNets (mit NAT & NSG)
// ----
var hubSubnets = [
  {
    name: hubSubnetName
    addressPrefix: hubSubnetPrefixes[0]
    natGatewayId: hubNat.outputs.natGatewayId
  }
]

var infraSubnets = [
  {
    name: dcSubnetName
    addressPrefix: infraSubnetPrefixes[0]
    natGatewayId: infraNat.outputs.natGatewayId
    nsgId: dcNsg.outputs.nsgId
  }
  {
    name: appSubnetName
    addressPrefix: infraSubnetPrefixes[1]
    natGatewayId: infraNat.outputs.natGatewayId
    nsgId: appNsg.outputs.nsgId
  }
]

var avdSubnets = [
  {
    name: avdSubnetName
    addressPrefix: avdSubnetPrefixes[0]
    natGatewayId: avdNat.outputs.natGatewayId
    nsgId: avdNsg.outputs.nsgId
  }
  {
    name: fslogixSubnetName
    addressPrefix: avdSubnetPrefixes[1]
    natGatewayId: avdNat.outputs.natGatewayId
    nsgId: fslogixNsg.outputs.nsgId
  }
]

module hubVnet 'modules/vnet.bicep' = {
  name: 'hubVnet'
  scope: hubRg
  params: {
    name: 'vnet-${prefixSafe}-hub'
    location: location
    addressSpace: hubVnetPrefix
    subnets: hubSubnets
  }
}

// Spoke DNS zeigt nachher auf DC-IP (nach VM-Erstellung)
module infraVnet 'modules/vnet.bicep' = {
  name: 'infraVnet'
  scope: infraRg
  params: {
    name: 'vnet-${prefixSafe}-infra'
    location: location
    addressSpace: infraVnetPrefix
    subnets: infraSubnets
    dnsServers: []
  }
}

module avdVnet 'modules/vnet.bicep' = {
  name: 'avdVnet'
  scope: avdRg
  params: {
    name: 'vnet-${prefixSafe}-avd'
    location: location
    addressSpace: avdVnetPrefix
    subnets: avdSubnets
    dnsServers: []
  }
}

// ----
// DC VM (SystemAssigned MI für FSLogix Storage Join)
// ----
var dcVmName = 'vm-${prefixSafe}-dc01'
module dcVm 'modules/windows-vm.bicep' = {
  name: 'dcVm'
  scope: infraRg
  params: {
    vmName: dcVmName
    location: location
    vmSize: dcVmSize
    subnetId: infraVnet.outputs.subnetIds[0]
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: serverImageReference
    vmIdentityType: 'SystemAssigned'
  }
}

// ----
// ADDS Setup (DSC)
// ----
module adds 'modules/vm-adds-forest.bicep' = {
  name: 'adds'
  scope: infraRg
  params: {
    vmName: dcVmName
    location: location
    domainName: domainName
    domainNetbiosName: domainNetbiosName
    domainAdminUsername: domainAdminUsername
    domainAdminPassword: domainAdminPassword
    ouPath: ouPath
    modulesUrl: addsDscModulesUrl
    configurationFunction: addsDscConfigurationFunction
  }
  dependsOn: [
    dcVm
  ]
}

// Update DNS servers after DC is up
module infraVnetDns 'modules/vnet-dns-update.bicep' = {
  name: 'infraVnetDns'
  scope: infraRg
  params: {
    vnetName: 'vnet-${prefixSafe}-infra'
    dnsServers: [ dcVm.outputs.privateIp ]
  }
  dependsOn: [
    adds
  ]
}

module avdVnetDns 'modules/vnet-dns-update.bicep' = {
  name: 'avdVnetDns'
  scope: avdRg
  params: {
    vnetName: 'vnet-${prefixSafe}-avd'
    dnsServers: [ dcVm.outputs.privateIp ]
  }
  dependsOn: [
    adds
  ]
}

// ----
// APP VM (domain join)
// ----
var appVmName = 'vm-${prefixSafe}-app01'
module appVm 'modules/windows-vm.bicep' = {
  name: 'appVm'
  scope: infraRg
  params: {
    vmName: appVmName
    location: location
    vmSize: appVmSize
    subnetId: infraVnet.outputs.subnetIds[1]
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: serverImageReference
  }
  dependsOn: [
    infraVnetDns
  ]
}

module appJoin 'modules/vm-domain-join.bicep' = {
  name: 'appJoin'
  scope: infraRg
  params: {
    vmName: appVmName
    location: location
    domainName: domainName
    domainNetbiosName: domainNetbiosName
    domainAdminUsername: domainAdminUsername
    domainAdminPassword: domainAdminPassword
    ouPath: ouPath
  }
  dependsOn: [
    appVm
    adds
  ]
}

// ----
// AVD Session Host (domain join)
// ----
var avdVmName = 'vm-${prefixSafe}-avd01'
module avdVm 'modules/windows-vm.bicep' = {
  name: 'avdVm'
  scope: avdRg
  params: {
    vmName: avdVmName
    location: location
    vmSize: avdVmSize
    subnetId: avdVnet.outputs.subnetIds[0]
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: avdImageReference
  }
  dependsOn: [
    avdVnetDns
  ]
}

module avdJoin 'modules/vm-domain-join.bicep' = {
  name: 'avdJoin'
  scope: avdRg
  params: {
    vmName: avdVmName
    location: location
    domainName: domainName
    domainNetbiosName: domainNetbiosName
    domainAdminUsername: domainAdminUsername
    domainAdminPassword: domainAdminPassword
    ouPath: ouPath
  }
  dependsOn: [
    avdVm
    adds
  ]
}

// ----
// FSLogix Storage (Azure Files)
// ----
module fslogixStorage 'modules/fslogix-storage.bicep' = {
  name: 'fslogixStorage'
  scope: avdRg
  params: {
    storageAccountName: fslogixStorageAccountName
    location: location
    shareName: fslogixShareName
    allowedSubnetIds: [
      avdVnet.outputs.subnetIds[0]
      avdVnet.outputs.subnetIds[1]
    ]
  }
  dependsOn: [
    avdVnet
  ]
}

// ----
// Peering
// ----
module peerHubToInfra 'modules/vnet-peering.bicep' = {
  name: 'peerHubToInfra'
  scope: hubRg
  params: {
    peeringName: 'peer-hub-to-infra'
    localVnetName: 'vnet-${prefixSafe}-hub'
    remoteVnetId: infraVnet.outputs.vnetId
  }
}

module peerInfraToHub 'modules/vnet-peering.bicep' = {
  name: 'peerInfraToHub'
  scope: infraRg
  params: {
    peeringName: 'peer-infra-to-hub'
    localVnetName: 'vnet-${prefixSafe}-infra'
    remoteVnetId: hubVnet.outputs.vnetId
  }
}

module peerHubToAvd 'modules/vnet-peering.bicep' = {
  name: 'peerHubToAvd'
  scope: hubRg
  params: {
    peeringName: 'peer-hub-to-avd'
    localVnetName: 'vnet-${prefixSafe}-hub'
    remoteVnetId: avdVnet.outputs.vnetId
  }
}

module peerAvdToHub 'modules/vnet-peering.bicep' = {
  name: 'peerAvdToHub'
  scope: avdRg
  params: {
    peeringName: 'peer-avd-to-hub'
    localVnetName: 'vnet-${prefixSafe}-avd'
    remoteVnetId: hubVnet.outputs.vnetId
  }
}

// ----
// Punkt 8: Log Analytics + Diagnostics + Alerts
// ----
module law 'modules/log-analytics.bicep' = if (enableOps) {
  name: 'logAnalytics'
  scope: infraRg
  params: {
    name: 'law-${prefixSafe}'
    location: location
    retentionInDays: logAnalyticsRetentionInDays
  }
}

// Existing resources for diagnostics
resource dcVmExisting 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: dcVmName
  scope: infraRg
}

resource appVmExisting 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: appVmName
  scope: infraRg
}

resource avdVmExisting 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: avdVmName
  scope: avdRg
}

resource fslogixSaExisting 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: fslogixStorageAccountName
  scope: avdRg
}

resource diagDcVm 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableOps) {
  name: 'diag-${dcVmName}'
  scope: dcVmExisting
  properties: {
    workspaceId: law.outputs.workspaceId
    logs: []
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource diagAppVm 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableOps) {
  name: 'diag-${appVmName}'
  scope: appVmExisting
  properties: {
    workspaceId: law.outputs.workspaceId
    logs: []
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource diagAvdVm 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableOps) {
  name: 'diag-${avdVmName}'
  scope: avdVmExisting
  properties: {
    workspaceId: law.outputs.workspaceId
    logs: []
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource diagFslogixSa 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableOps) {
  name: 'diag-${fslogixStorageAccountName}'
  scope: fslogixSaExisting
  properties: {
    workspaceId: law.outputs.workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Optional Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableOps && !empty(alertEmail)) {
  name: 'ag-${prefixSafe}-ops'
  location: 'global'
  properties: {
    groupShortName: 'ops'
    enabled: true
    emailReceivers: [
      {
        name: 'opsMail'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource alertCpuDc 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableOps && !empty(alertEmail)) {
  name: 'alert-${dcVmName}-cpu'
  location: 'global'
  scope: infraRg
  properties: {
    description: 'CPU > 80% (Average / 15m)'
    severity: 2
    enabled: true
    scopes: [
      dcVmExisting.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          timeAggregation: 'Average'
          operator: 'GreaterThan'
          threshold: 80
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

resource alertCpuApp 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableOps && !empty(alertEmail)) {
  name: 'alert-${appVmName}-cpu'
  location: 'global'
  scope: infraRg
  properties: {
    description: 'CPU > 80% (Average / 15m)'
    severity: 2
    enabled: true
    scopes: [
      appVmExisting.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          timeAggregation: 'Average'
          operator: 'GreaterThan'
          threshold: 80
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

resource alertCpuAvd 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableOps && !empty(alertEmail)) {
  name: 'alert-${avdVmName}-cpu'
  location: 'global'
  scope: infraRg
  properties: {
    description: 'CPU > 80% (Average / 15m)'
    severity: 2
    enabled: true
    scopes: [
      avdVmExisting.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          timeAggregation: 'Average'
          operator: 'GreaterThan'
          threshold: 80
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ----
// Punkt 6: FSLogix Auth/ACL Setup (AzFilesHybrid + NTFS ACLs)
// ----
// 1) DC MI bekommt Contributor auf Storage Account
resource dcMiStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(fslogixSaExisting.id, dcVm.outputs.principalId, 'contributor')
  scope: fslogixSaExisting
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: dcVm.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// 2) RunCommand auf DC: Storage Account domain-join + ACLs setzen
resource fslogixAuthAndAcls 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  name: 'SetupFslogixFilesAuthAcls'
  parent: dcVmExisting
  location: location
  properties: {
    runAsUser: '${domainNetbiosName}\\${domainAdminUsername}'
    runAsPassword: domainAdminPassword
    timeoutInSeconds: 3600
    treatFailureAsDeploymentFailure: true
    source: {
      script: '''
param(
  [Parameter(Mandatory=$true)][string]$SubscriptionId,
  [Parameter(Mandatory=$true)][string]$StorageAccountName,
  [Parameter(Mandatory=$true)][string]$StorageResourceGroup,
  [Parameter(Mandatory=$true)][string]$ShareName,
  [string]$OuDistinguishedName,
  [Parameter(Mandatory=$true)][string]$AzFilesHybridZipUrl,
  [Parameter(Mandatory=$true)][string]$FslogixUsersGroup,
  [Parameter(Mandatory=$true)][string]$FslogixAdminsGroup
)

$ErrorActionPreference = 'Stop'

Write-Host 'Connect to Azure using Managed Identity...'
try {
  if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Install-Module Az -Force -AllowClobber -Scope AllUsers
  }
  Import-Module Az.Accounts -Force
  Import-Module Az.Resources -Force
  Import-Module Az.Storage -Force
  Connect-AzAccount -Identity | Out-Null
  Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null
}
catch {
  Write-Error $_
  throw
}

$base = 'C:\AzFilesHybrid'
if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base | Out-Null }
$zip = Join-Path $base 'AzFilesHybrid.zip'

Write-Host "Downloading AzFilesHybrid from $AzFilesHybridZipUrl"
Invoke-WebRequest -Uri $AzFilesHybridZipUrl -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $base -Force

# Module liegt im Repo unter .\AzFilesHybrid\AzFilesHybrid.psd1
$modulePath = Join-Path $base 'AzFilesHybrid\AzFilesHybrid.psd1'
if (-not (Test-Path $modulePath)) {
  # fallback (manche Releases packen unter einem Unterordner)
  $modulePath = (Get-ChildItem -Path $base -Filter 'AzFilesHybrid.psd1' -Recurse | Select-Object -First 1).FullName
}
Import-Module $modulePath -Force

Write-Host 'Joining Storage Account to AD for Azure Files authentication...'
$joinParams = @{
  ResourceGroupName = $StorageResourceGroup
  StorageAccountName = $StorageAccountName
  DomainAccountType = 'ComputerAccount'
}
if ($OuDistinguishedName -and $OuDistinguishedName.Trim().Length -gt 0) {
  $joinParams['OrganizationalUnitDistinguishedName'] = $OuDistinguishedName
}

Join-AzStorageAccountForAuth @joinParams

# SMB share mount + NTFS ACLs
$sharePath = "\\\\$StorageAccountName.file.core.windows.net\\$ShareName"
Write-Host "Mapping share: $sharePath"
cmd /c "net use Z: $sharePath /persistent:no" | Out-Null

New-Item -ItemType Directory -Path 'Z:\\Profiles' -Force | Out-Null

Write-Host 'Setting NTFS ACLs...'
icacls 'Z:\\Profiles' /inheritance:r | Out-Null
icacls 'Z:\\Profiles' /grant 'SYSTEM:(OI)(CI)(F)' | Out-Null
icacls 'Z:\\Profiles' /grant "${FslogixAdminsGroup}:(OI)(CI)(F)" | Out-Null
icacls 'Z:\\Profiles' /grant 'CREATOR OWNER:(OI)(CI)(IO)(F)' | Out-Null
icacls 'Z:\\Profiles' /grant "${FslogixUsersGroup}:(OI)(CI)(M)" | Out-Null

cmd /c 'net use Z: /delete' | Out-Null
Write-Host 'FSLogix Files Auth/ACL setup finished.'
'''
    }
    parameters: [
      {
        name: 'SubscriptionId'
        value: subscription().subscriptionId
      }
      {
        name: 'StorageAccountName'
        value: fslogixStorageAccountName
      }
      {
        name: 'StorageResourceGroup'
        value: avdRgName
      }
      {
        name: 'ShareName'
        value: fslogixShareName
      }
      {
        name: 'OuDistinguishedName'
        value: ouPath
      }
      {
        name: 'AzFilesHybridZipUrl'
        value: azFilesHybridZipUrl
      }
      {
        name: 'FslogixUsersGroup'
        value: fslogixUsersGroupName
      }
      {
        name: 'FslogixAdminsGroup'
        value: fslogixAdminsGroupName
      }
    ]
  }
  dependsOn: [
    adds
    fslogixStorage
    dcMiStorageContributor
  ]
}

output dcPrivateIp string = dcVm.outputs.privateIp
output fslogixFileEndpoint string = fslogixStorage.outputs.fileEndpoint

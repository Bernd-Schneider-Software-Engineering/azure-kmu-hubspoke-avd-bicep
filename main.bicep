// main.bicep
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

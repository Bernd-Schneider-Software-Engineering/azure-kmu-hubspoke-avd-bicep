# KMU Hub-Spoke IaC (Bicep)


## Fixes (2/3/5/6/7/8/9)


### 2) AVD Image SKU nicht hardcoded
- Die AVD-Image-Referenz ist jetzt parametriert (`avdImagePublisher/Offer/Sku/Version`).
- **Vor Deploy** in der Zielregion verifizieren:


```bash
az vm image list-publishers -l westeurope -o table
az vm image list-offers -l westeurope -p MicrosoftWindowsDesktop -o table
az vm image list-skus -l westeurope -p MicrosoftWindowsDesktop -f windows-11 -o table
az vm image list -l westeurope -p MicrosoftWindowsDesktop -f windows-11 -s win11-23h2-avd --all -o table
) Supply-Chain für ADDS DSC Artefakte

addsDscModulesUrl ist jetzt Parameter.

Empfehlung: eigene Artefakt-URL nutzen (Storage Blob / Release / Commit-pinned raw URL) statt master.

5) NSGs pro Subnet

Subnets bekommen NSGs. Mit hardenNsg=true gilt: Default-Deny inbound.

Erlaubt sind nur:

DC-Subnet: AD/DNS/Kerberos/LDAP/SMB/RPC + RDP aus managementSourceCidr

App-Subnet: nur RDP aus managementSourceCidr

AVD-Subnet: nur RDP aus managementSourceCidr

FSLogix-Subnet: deny all inbound

Wenn eure App zusätzliche Ports braucht: NSG-Regeln ergänzen.

6) FSLogix – saubere Auth/ACLs (Azure Files + AD DS)

Storage Account: SharedKey-Zugriff deaktiviert (allowSharedKeyAccess=false) und VNet-Firewall via Service Endpoints.

Nach Provisioning läuft ein RunCommand auf dem DC:

Join-AzStorageAccountForAuth (AzFilesHybrid, pinned Release URL) → Azure Files nutzt AD DS Auth

File Share Mount + NTFS ACLs auf \\<sa>.file.core.windows.net\<share>\Profiles

Parameter:

fslogixUsersGroupName (Default Domain Users)

fslogixAdminsGroupName (Default Domain Admins)

7) Prefix-Validierung

In Bicep ohne Regex: String wird auf erlaubte Zeichen „leer-ersetzt“. Wenn Reste übrig bleiben → fail().

8) Observability

Log Analytics Workspace (Infra RG)

Diagnostic Settings:

VMs: Metrics (AllMetrics)

FSLogix Storage Account: allLogs + AllMetrics

Optional Alerts: alertEmail setzen → ActionGroup + CPU Alerts.

9) Default Outbound Access / Egress

Dieses Template nutzt NAT Gateways pro VNet/Subnet für explizite Outbound-Konnektivität.

Hintergrund: „Default outbound access“ wird/ist je nach Zeitplan nicht mehr als Standardverhalten nutzbar; explizite Egress-Architektur (NAT/LB/Public IP/Firewall) ist Best Practice.

## Hinweis
Unveränderte Dateien (z.B. `modules/vnet-peering.bicep`, `modules/nat-gateway.bicep`, `modules/vnet-dns-update.bicep`, `modules/vm-domain-join.bicep`) bleiben wie bei dir – hier nicht erneut dupliziert.

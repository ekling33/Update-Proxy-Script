# VM ID (hostname/IP for labeling)
$VMID = $env:COMPUTERNAME

# 1. NetBIOS config per adapter (0/1=enabled exposes users, 2=disabled)
Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, @{N='NetBIOS';E={if ((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\$($_.InterfaceIndex)" -EA SilentlyContinue).NetbiosOptions -eq 2) {'Disabled'} else {'Enabled'}}}

# 2. Listening ports (NetBIOS/SMB/SNMP triggers)
netstat -an | Select-String ":137 :138 :139 :445 :161"

# 3. Firewall rules for key ports (Enabled=block?)
netsh advfirewall firewall show rule name=all | Select-String "137|138|139|445|161"

# 4. Local users (enumerated list)
net user

# 5. Services exposing info (running?)
Get-Service | Where-Object {$_.Name -match "LanmanServer|SNMP|NetBT"}

# Output labeled file
$_ | Out-File "C:\temp\$VMID_QID45002_check.txt"

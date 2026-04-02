# Create TLS 1.2 Client keys if missing
$clientPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client"
if (!(Test-Path $clientPath)) { 
  New-Item $clientPath -Force | Out-Null 
}

# Enable TLS 1.2 Client
Set-ItemProperty $clientPath -Name "Enabled" -Value 1 -Type DWord
Set-ItemProperty $clientPath -Name "DisabledByDefault" -Value 0 -Type DWord

# Disable legacy (optional, safer)
$legacy = @('TLS 1.0', 'TLS 1.1', 'SSL 2.0', 'SSL 3.0')
foreach ($proto in $legacy) {
  $path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto\Client"
  if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
  Set-ItemProperty $path -Name "Enabled" -Value 0 -Type DWord
  Set-ItemProperty $path -Name "DisabledByDefault" -Value 1 -Type DWord
}

gpupdate /force
Write-Host "TLS 1.2 Client enabled. Restart Blue Prism Runtime Resource connection."

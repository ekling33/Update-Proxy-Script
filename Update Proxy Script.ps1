\$pathClient = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client"
\$pathServer = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server"

foreach (\$p in @(\$pathClient, \$pathServer)) {
  if (-not (Test-Path \$p)) { New-Item -Path \$p -Force | Out-Null }
  Set-ItemProperty -Path \$p -Name "Enabled"    -Value 0 -Type DWord
  Set-ItemProperty -Path \$p -Name "DisabledByDefault" -Value 1 -Type DWord
}

Restart-Computer -Force

################################################################################

Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value 1 -Type DWord
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value 1 -Type DWord

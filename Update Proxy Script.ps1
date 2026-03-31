# Cipher suites + order (key for handshake)
Get-TlsCipherSuite | Select-Object Name, ProtocolsSupported | Format-Table -AutoSize | Out-File ciphers.txt

# Or if no Get-TlsCipherSuite (older Win):
Get-ChildItem HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers | ForEach { Get-ItemProperty $_.PSPath } | Select PSChildName, Enabled | Format-Table

# TLS protocols
Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS*\Server | Select PSChildName, Enabled, DisabledByDefault | Format-Table

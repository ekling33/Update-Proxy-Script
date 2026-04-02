# On GOOD server
Get-TlsCipherSuite | Select-Object -ExpandProperty Name | Out-File "GoodCiphers.txt"

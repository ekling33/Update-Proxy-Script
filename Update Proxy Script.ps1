# GOOD server
Get-TlsCipherSuite | ForEach-Object { $_.Name } | Out-File "GoodCiphers.txt"

# List all certs in Personal store with thumbprint, subject, expiry
Get-ChildItem Cert:\LocalMachine\My | 
  Select-Object Thumbprint, Subject, NotAfter, Issuer |
  Sort-Object NotAfter |
  Format-Table -AutoSize

# Export cert list to file for comparison
Get-ChildItem Cert:\LocalMachine\My | Export-Clixml "C:\BP_Certs_$env:COMPUTERNAME.xml"

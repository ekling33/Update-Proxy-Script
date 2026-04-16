Import-Module ActiveDirectory
Get-ADUser -Identity "bp-service" -Properties msDS-SupportedEncryptionTypes |
Select-Object Name, SamAccountName, msDS-SupportedEncryptionTypes

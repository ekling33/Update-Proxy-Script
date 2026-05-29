$err = $null
Update-MpSignature -Verbose -ErrorAction Continue -ErrorVariable err 2>&1 | Tee-Object C:\Temp\defender-update.log
$err

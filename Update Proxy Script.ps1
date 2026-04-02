# Copy-paste this on BAD server, save output to BadServer_TLS.txt
# Then run on GOOD server, save to GoodServer_TLS.txt
$protocols = @('TLS 1.2', 'TLS 1.1', 'TLS 1.0', 'SSL 3.0', 'SSL 2.0')
$roles = @('Client', 'Server')

$result = @()
foreach ($proto in $protocols) {
  foreach ($role in $roles) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto\$role"
    $enabled = (Get-ItemProperty -Path $path -Name Enabled -ErrorAction SilentlyContinue).Enabled
    $disabled = (Get-ItemProperty -Path $path -Name DisabledByDefault -ErrorAction SilentlyContinue).'DisabledByDefault'
    $result += [PSCustomObject]@{ Protocol=$proto; Role=$role; Enabled=$enabled; DisabledByDefault=$disabled }
  }
}
$result | Format-Table -AutoSize
$result | Export-Csv "TLS_Compare_$env:COMPUTERNAME.csv" -NoTypeInformation

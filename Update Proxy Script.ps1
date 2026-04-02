$paths = @(
  "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319",
  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319"
)

foreach ($path in $paths) {
  New-Item $path -Force -ErrorAction SilentlyContinue | Out-Null
  Set-ItemProperty $path -Name "SchUseStrongCrypto" -Value 1 -Type DWord -Force
  Set-ItemProperty $path -Name "SystemDefaultTlsVersions" -Value 1 -Type DWord -Force
  Write-Host "Fixed $path"
}

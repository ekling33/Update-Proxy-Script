# .NET TLS 1.2 modern ciphers (KB5078752 compatible)
$paths = @(
  "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319",
  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319"
)

foreach ($path in $paths) {
  if (!(Test-Path $path)) { New-Item $path -Force | Out-Null }
  Set-ItemProperty $path -Name "SchUseStrongCrypto" -Value 1 -Type DWord -Force
  Set-ItemProperty $path -Name "SystemDefaultTlsVersions" -Value 1 -Type DWord -Force
}

gpupdate /force
Write-Host ".NET strong crypto enabled. Restart Runtime Resource."

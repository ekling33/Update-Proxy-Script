# Disable TLS 1.3 and enable strong crypto for .NET Framework
# Run in an elevated PowerShell session

$ErrorActionPreference = 'Stop'

Write-Host "Configuring TLS settings..." -ForegroundColor Cyan

$paths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client",
    "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server"
)

foreach ($path in $paths) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    New-ItemProperty -Path $path -Name "Enabled" -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name "DisabledByDefault" -Value 1 -PropertyType DWord -Force | Out-Null
}

$dotNetPaths = @(
    "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319"
)

foreach ($path in $dotNetPaths) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    New-ItemProperty -Path $path -Name "SchUseStrongCrypto" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name "SystemDefaultTlsVersions" -Value 1 -PropertyType DWord -Force | Out-Null
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "TLS 1.3 disabled for Schannel client/server." -ForegroundColor Yellow
Write-Host ".NET Framework strong crypto enabled." -ForegroundColor Yellow
Write-Host ""
Write-Host "Reboot the VM before testing Blue Prism again." -ForegroundColor Cyan

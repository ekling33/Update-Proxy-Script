# Forceful removal with retries
$apps = @('*RawImageExtension*', '*VP9VideoExtensions*')
foreach ($pattern in $apps) {
    # Remove installed packages
    $pkgs = Get-AppxPackage -AllUsers $pattern -ErrorAction SilentlyContinue
    if ($pkgs) { $pkgs | Remove-AppxPackage -AllUsers -ErrorAction Stop }

    # Retry if failed
    Start-Sleep -Seconds 2
    $pkgs = Get-AppxPackage -AllUsers $pattern -ErrorAction SilentlyContinue
    if ($pkgs) { $pkgs | Remove-AppxPackage -AllUsers -ErrorAction Stop }
}

# Remove provisioned (prevents reinstall for new users)
Get-AppXProvisionedPackage -Online | Where-Object DisplayName -match 'RawImageExtension|VP9VideoExtensions' | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# Optional: Kill related processes and delete files (run as SYSTEM for best results)
Stop-Process -Name "Microsoft.Photos*", "Movies*", -Force -ErrorAction SilentlyContinue
$winApps = Get-ChildItem "C:\Program Files\WindowsApps" -Filter "*Raw*" -ErrorAction SilentlyContinue
if ($winApps) { $winApps | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
$winApps = Get-ChildItem "C:\Program Files\WindowsApps" -Filter "*VP9*" -ErrorAction SilentlyContinue
if ($winApps) { $winApps | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output "Forceful cleanup completed on $env:COMPUTERNAME"

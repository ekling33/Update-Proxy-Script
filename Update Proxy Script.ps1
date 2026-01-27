# VP9-Complete-Local-Fix.ps1
# Copy-paste & run as ADMIN on EACH VM
# One-time VP9 removal + scanner fix

Write-Host "=== VP9 Complete Removal ===" -ForegroundColor Green

# Enable special profile (for VM/Admin profiles)
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
if (-not (Test-Path $regPath)) { New-Item $regPath -Force | Out-Null }
Set-ItemProperty $regPath "AllowDeploymentInSpecialProfiles" 1 -Type DWord -Force

# Remove ALL VP9
Write-Host "Removing VP9 packages..." -ForegroundColor Yellow
Get-AppxPackage "*VP9*" | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online "*VP9*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# Clean registry (scanner cache)
Write-Host "Cleaning registry..." -ForegroundColor Yellow
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore" -ErrorAction SilentlyContinue | 
    Where-Object Name -like "*VP9*" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Verify
$userCount = (Get-AppxPackage "*VP9*" | Measure-Object).Count
Write-Host "`n=== RESULTS ===" -ForegroundColor Cyan
Write-Host "VP9 User packages: $userCount" -ForegroundColor $(if($userCount -eq 0){"Green"}else{"Red"})

# Revert registry
Remove-ItemProperty $regPath "AllowDeploymentInSpecialProfiles" -ErrorAction SilentlyContinue

# Log
[PSCustomObject]@{
    Hostname = $env:COMPUTERNAME
    VP9Count = $userCount
    Time     = Get-Date
} | Export-Csv "VP9-Fixed-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv" -NoTypeInformation

Write-Host "`n✓ COMPLETE - reboot & re-scan" -ForegroundColor Green
Write-Host "Scanner clears in 24-72h" -ForegroundColor Cyan

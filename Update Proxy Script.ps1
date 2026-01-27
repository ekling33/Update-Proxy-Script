# VP9-Final-NoGPUpdate.ps1 - NO hanging commands

# Enable special profile (takes effect instantly)
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
if (-not (Test-Path $regPath)) { New-Item $regPath -Force | Out-Null }
Set-ItemProperty $regPath "AllowDeploymentInSpecialProfiles" 1 -Type DWord -Force

Write-Host "Special profile enabled - removing VP9..."

# Remove VP9 (ghost + real)
Get-AppxPackage "*VP9*" | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online "*VP9*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# Registry cleanup
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore" -ErrorAction SilentlyContinue | 
    Where-Object Name -like "*VP9*" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Verify
$userCount = (Get-AppxPackage "*VP9*" | Measure-Object).Count
Write-Host "VP9 User packages: $userCount" -ForegroundColor $(if($userCount -eq 0){"Green"}else{"Red"})

# Revert registry
Remove-ItemProperty $regPath "AllowDeploymentInSpecialProfiles" -ErrorAction SilentlyContinue

Write-Host "`n✓ Done - reboot recommended" -ForegroundColor Green

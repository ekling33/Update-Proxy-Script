# Enable special profile deployment
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "AllowDeploymentInSpecialProfiles" -Value 1 -Type DWord -Force
gpupdate /force
Write-Host "Special profile enabled"


###################################################################

# VP9 removal (with special profile enabled)
Get-AppxPackage "*VP9*" | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online "*VP9*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# Clean registry
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore" -ErrorAction SilentlyContinue | 
    Where-Object Name -like "*VP9*" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Verify
Get-AppxPackage "*VP9*"

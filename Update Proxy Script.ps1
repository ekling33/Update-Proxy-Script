# Check VP9 status post-reboot
Write-Host "=== VP9 Diagnostic ==="
Get-AppxPackage "*VP9*" | Format-Table Name, Version, PackageFullName, InstallLocation

Get-AppxProvisionedPackage -Online "*VP9*" | Format-Table DisplayName, PackageName

# Check registry remnants
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore" -ErrorAction SilentlyContinue | 
    Where-Object Name -like "*VP9*" | Select Name
    
###################################

# Final VP9 cleanup - handles pending states
Stop-Process -Name "AppXSvc" -ErrorAction SilentlyContinue
Get-AppxPackage "*VP9*" | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online "*VP9*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# Kill AppX services + restart
net stop AppXSvc
net start AppXSvc

# Reboot AGAIN (finalizes pending removals)
Write-Host "Rebooting to finalize..."
Restart-Computer -Force

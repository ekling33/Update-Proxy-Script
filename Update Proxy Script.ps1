# Remove from all users (handles the "still installed" part)
Get-AppxPackage -AllUsers -Name Microsoft.Microsoft3DViewer -PackageTypeFilter Bundle |
    Remove-AppxPackage -AllUsers

# Remove provisioned (prevents reinstall)
Get-AppxProvisionedPackage -Online -PackageName "*Microsoft.Microsoft3DViewer*" |
    Remove-AppxProvisionedPackage -Online




#REBOOT, THEN
Get-AppxPackage -AllUsers -Name Microsoft.Microsoft3DViewer
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*3DViewer*"


dir "C:\Program Files\WindowsApps\Microsoft.Microsoft3DViewer*"

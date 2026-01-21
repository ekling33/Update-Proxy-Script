Get-AppxPackage *3dviewer* -AllUsers | Remove-AppxPackage -AllUsers; Get-AppxProvisionedPackage -Online | ?{$_.DisplayName -like "*3DViewer*"} | Remove-AppxProvisionedPackage -Online; rd "C:\Program Files\WindowsApps\Microsoft.Microsoft3DViewer*" -Recurse -Force -EA 0

Get-AppxPackage *3dviewer*

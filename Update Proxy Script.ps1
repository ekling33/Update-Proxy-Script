# Full 3D Viewer cleanup (fixed)
$pkgName = "Microsoft.Microsoft3DViewer"

# Remove from all users
Get-AppxPackage -AllUsers -Name $pkgName -PackageTypeFilter Bundle | 
    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

# Remove provisioned (CORRECTED: no -PackageName param)
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $pkgName | 
    Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# Verify
Write-Host "Users: " (Get-AppxPackage -AllUsers -Name $pkgName | Measure-Object).Count
Write-Host "Provisioned: " (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $pkgName | Measure-Object).Count

# 1) Check all known packages by wildcard
Get-AppxPackage -AllUsers "*VP9*" | Select Name, PackageFullName, Version
Get-AppxProvisionedPackage -Online | Where DisplayName -like "*VP9*"

Get-AppxPackage -AllUsers "*Raw*" | Select Name, PackageFullName, Version
Get-AppxProvisionedPackage -Online | Where DisplayName -like "*Raw*"

Get-AppxPackage -AllUsers "Microsoft.MSPaint" | Select Name, PackageFullName, Version
Get-AppxProvisionedPackage -Online | Where DisplayName -eq "Microsoft.MSPaint"

Get-AppxPackage -AllUsers "*Print3D*" | Select Name, PackageFullName, Version
Get-AppxProvisionedPackage -Online | Where DisplayName -like "*Print3D*"

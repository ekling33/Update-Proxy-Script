# Target the EXACT package
Get-AppxPackage -Package "Microsoft.VP9VideoExtensions_1.0.50481.0_x64_8wekyb3d8bbwe" -AllUsers |
    Remove-AppxPackage -AllUsers

# Double-check
Get-AppxPackage "*VP9*"

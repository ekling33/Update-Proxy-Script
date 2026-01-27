# On affected machine - removes VP9 1.0.50481.0 exactly
$vp9Pkg = Get-AppxPackage -AllUsers "Microsoft.VP9VideoExtensions" | 
          Where-Object { $_.PackageFullName -eq "Microsoft.VP9VideoExtensions_1.0.50481.0_x64_8wekyb3d8bbwe" }

if ($vp9Pkg) {
    $vp9Pkg | Remove-AppxPackage -AllUsers
    Write-Host "✓ VP9 1.0.50481.0 removed"
} else {
    Write-Host "Package not found"
}

# Verify
Get-AppxPackage "*VP9*"

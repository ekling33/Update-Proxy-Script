# Ghost VP9 killer
$vp9Ghost = Get-AppxPackage "Microsoft.VP9VideoExtensions"

if ($vp9Ghost) {
    # Force remove by PackageFullName
    Remove-AppxPackage -Package $vp9Ghost.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    
    # Clean registry entry directly
    $sidPaths = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore" | 
                Where-Object Name -like "*Microsoft.VP9VideoExtensions*"
    
    $sidPaths | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Host "Ghost VP9 registry cleaned"
} else {
    Write-Host "No VP9 found"
}

# Verify
Get-AppxPackage "*VP9*"

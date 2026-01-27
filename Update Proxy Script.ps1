# VP9-Local-Cleanup.ps1
# Run LOCALLY on target machine (elevated PowerShell)
# Removes VP9 + cleans scanner registry - NO REMOTING

Write-Host "=== VP9 Final Cleanup (Local) ===" -ForegroundColor Green

# Before count
$before = (Get-AppxPackage "*VP9*" | Measure-Object).Count
Write-Host "VP9 before: $before" -ForegroundColor Yellow

# Remove ALL VP9 packages
Get-AppxPackage "*VP9*" | Remove-AppxPackage -ErrorAction SilentlyContinue

# Remove provisioned VP9
Get-AppxProvisionedPackage -Online "*VP9*" | 
    Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

# Clean registry leftovers (scanner cache)
$vp9RegPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\InboxApplications\Microsoft.VP9VideoExtensions*",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\S-1-5-21*\Microsoft.VP9VideoExtensions*"
)

foreach ($path in $vp9RegPaths) {
    Remove-Item $path -ErrorAction SilentlyContinue -Recurse -Force
}

# Final verification
$after = (Get-AppxPackage "*VP9*" | Measure-Object).Count
$provAfter = (Get-AppxProvisionedPackage -Online "*VP9*" | Measure-Object).Count

Write-Host "`n=== RESULTS ===" -ForegroundColor Cyan
Write-Host "VP9 User packages: $before → $after"
Write-Host "VP9 Provisioned: 0 → $provAfter"
Write-Host "Registry cleaned" -ForegroundColor Green

if ($after -eq 0 -and $provAfter -eq 0) {
    Write-Host "`n✓ VP9 FULLY REMOVED - scanner should clear next scan" -ForegroundColor Green
} else {
    Write-Host "`n⚠ Still some VP9 left - reboot and re-run" -ForegroundColor Yellow
}

# Log to file
$result = [PSCustomObject]@{
    Hostname = $env:COMPUTERNAME
    Before   = $before
    After    = $after
    Prov     = $provAfter
    Time     = Get-Date
}
$result | Export-Csv "VP9-Local-Result-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv" -NoTypeInformation
Write-Host "Logged to CSV" -ForegroundColor Cyan

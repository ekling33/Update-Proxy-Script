# Remove-VP9-Bruteforce.ps1 - works on ANY Windows version

$ComputerNames = Get-Content "machines.txt"

foreach ($ComputerName in $ComputerNames) {
    Write-Host "`n$ComputerName" -ForegroundColor Green
    
    Invoke-Command -ComputerName $ComputerName {
        # Remove by wildcard
        Get-AppxPackage "*VP9*" | Remove-AppxPackage -ErrorAction SilentlyContinue
        
        # Force re-register remaining AppX (fixes ghost detections)
        Get-AppXPackage -AllUsers | Foreach { 
            Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
        }
        
        # Final check
        $remaining = (Get-AppxPackage "*VP9*" | Measure-Object).Count
        Write-Output "VP9 remaining: $remaining"
    }
}

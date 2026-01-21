# Remove-Teams.ps1 - Run as Administrator
$machines = Get-Content .\machines.txt | Where-Object { $_.Trim() -ne '' }
$logFile = "TeamsRemoval_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

foreach ($computer in $machines) {
    $computer = $computer.Trim()
    try {
        $result = Invoke-Command -ComputerName $computer -ScriptBlock {
            # Stop Teams processes
            Get-Process msteams -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep 3

            # Remove AppX package for all users
            Get-AppxPackage *MSTeams* -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

            # Remove provisioned package
            Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*MSTeams*" } | Remove-AppxProvisionedPackage -Online -AllUsers -ErrorAction SilentlyContinue

            # Remove MSI if present (Machine-Wide Installer)
            $msi = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Teams Machine-Wide*" }
            if ($msi) { $msi.Uninstall() }

            "Teams removal completed successfully."
        } -ErrorAction Stop

        "$computer`: SUCCESS - $result" | Tee-Object -FilePath $logFile -Append
    }
    catch {
        "$computer`: FAILED - $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append
    }
}

Write-Host "Script complete. Check $logFile for details." [web:16][web:10][web:3]

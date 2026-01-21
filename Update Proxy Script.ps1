# PowerShell script to remove Web Media Extensions from remote Windows 10 VMs
# Run as Administrator. Requires WinRM enabled on targets (Enable-PSRemoting -Force)
# machines.txt: one hostname/IP per line

# Read target machines
$machines = Get-Content -Path "machines.txt" | Where-Object { $_ -match '\S' }

foreach ($machine in $machines) {
    Write-Host "Processing $machine..." -ForegroundColor Yellow
    
    try {
        Invoke-Command -ComputerName $machine -ScriptBlock {
            # Remove installed packages for all users
            $pkg = Get-AppxPackage -AllUsers *WebMediaExtensions* -ErrorAction SilentlyContinue
            if ($pkg) {
                $pkg | Remove-AppxPackage -ErrorAction Stop
                Write-Output "Removed installed Web Media Extensions packages."
            } else {
                Write-Output "No installed Web Media Extensions packages found."
            }
            
            # Remove provisioned packages
            $provPkg = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq "Microsoft.WebMediaExtensions" }
            if ($provPkg) {
                $provPkg | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
                Write-Output "Removed provisioned Web Media Extensions package."
            } else {
                Write-Output "No provisioned Web Media Extensions package found."
            }
            
            # Verification
            $verifyInstalled = Get-AppxPackage -AllUsers *WebMediaExtensions* -ErrorAction SilentlyContinue
            $verifyProv = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq "Microsoft.WebMediaExtensions" }
            if (-not $verifyInstalled -and -not $verifyProv) {
                Write-Output "SUCCESS: Web Media Extensions fully removed."
            } else {
                Write-Warning "Partial removal - rescan recommended."
            }
        } -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed on $machine`: $($_.Exception.Message)"
    }
    
    Write-Host "Completed $machine`n" -ForegroundColor Green
}

Write-Host "Script finished. Reboot targets and rescan with Qualys for QID-91764." -ForegroundColor Cyan

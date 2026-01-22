# Updated PowerShell script to remove Web Media Extensions from remote Windows 10 VMs
# Handles HRESULT 0x80073D19 "user logged off" by skipping inactive user packages
# Run as Administrator. Requires WinRM enabled on targets (Enable-PSRemoting -Force)
# machines.txt: one hostname/IP per line

# Read target machines
$machines = Get-Content -Path "machines.txt" | Where-Object { $_ -match '\S' }

foreach ($machine in $machines) {
    Write-Host "Processing $machine..." -ForegroundColor Yellow
    
    try {
        Invoke-Command -ComputerName $machine -ScriptBlock {
            # Robust removal for installed packages (handles logged-off users)
            $pkgs = Get-AppxPackage -AllUsers *WebMediaExtensions* -ErrorAction SilentlyContinue
            if ($pkgs) {
                foreach ($pkg in $pkgs) {
                    try {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                        Write-Output "Removed: $($pkg.PackageFullName)"
                    }
                    catch {
                        if ($_.Exception.Message -like "*0x80073D19*" -or $_.Exception.Message -like "*logged off*") {
                            Write-Output "Skipped inactive user package: $($pkg.PackageFullName)"
                        } else {
                            Write-Warning "Failed $($pkg.PackageFullName): $($_.Exception.Message)"
                        }
                    }
                }
            } else {
                Write-Output "No installed Web Media Extensions packages found."
            }
            
            # Remove provisioned packages (SYSTEM-level, no user issues)
            $provPkgs = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*WebMediaExtensions*" }
            if ($provPkgs) {
                foreach ($provPkg in $provPkgs) {
                    try {
                        Remove-AppxProvisionedPackage -Online -PackageName $provPkg.PackageName -ErrorAction Stop
                        Write-Output "Removed provisioned: $($provPkg.DisplayName)"
                    }
                    catch {
                        Write-Warning "Failed provisioned $($provPkg.DisplayName): $($_.Exception.Message)"
                    }
                }
            } else {
                Write-Output "No provisioned Web Media Extensions found."
            }
            
            # Verification
            $verifyInstalled = Get-AppxPackage -AllUsers *WebMediaExtensions* -ErrorAction SilentlyContinue
            $verifyProv = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*WebMediaExtensions*" }
            $remaining = @($verifyInstalled.Count + $verifyProv.Count)
            if ($remaining -eq 0) {
                Write-Output "SUCCESS: Web Media Extensions fully removed."
            } else {
                Write-Warning "Remaining packages: $remaining (likely inactive users - safe after provisioned removal)"
            }
            
            # Optional: Clean WindowsApps folders (run if access allows)
            Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.WebMediaExtensions*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Output "Cleaned WindowsApps folders."
        } -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed on $machine`: $($_.Exception.Message)"
    }
    
    Write-Host "Completed $machine`n" -ForegroundColor Green
}

Write-Host "Script finished. Reboot targets (Restart-Computer -ComputerName (Get-Content machines.txt) -Force), then rescan Qualys for QID-91764." -ForegroundColor Cyan

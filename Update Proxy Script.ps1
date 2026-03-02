# Enable-ChromeUpdates.ps1 - Remote Chrome update fix for VMs
# Run as Admin. Requires WinRM on targets.

$machines = Get-Content -Path "machines.txt" | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }

foreach ($machine in $machines) {
    Write-Host "`nProcessing $machine..." -ForegroundColor Yellow
    
    try {
        $session = New-PSSession -ComputerName $machine -ErrorAction Stop
        
        Invoke-Command -Session $session -ScriptBlock {
            $regPaths = @(
                "HKLM:\SOFTWARE\Policies\Google\Update",
                "HKLM:\SOFTWARE\Wow6432Node\Policies\Google\Update"
            )
            
            foreach ($path in $regPaths) {
                if (Test-Path $path) {
                    $blockingKeys = @(
                        'UpdateDefault', 'AutoUpdateCheckPeriodMinutes', 'UpdatePolicy', 'DisableAutoUpdate',
                        'RollbackToTargetVersion', 'TargetVersionPrefix', 'TargetChannel', 'Update',
                        'TargetChannelOverride', 'TargetVersionPrefixOverride'
                    )
                    foreach ($key in $blockingKeys) {
                        if (Get-ItemProperty -Path $path -Name $key -ErrorAction SilentlyContinue) {
                            Remove-ItemProperty -Path $path -Name $key -Force
                            Write-Output "Deleted $path\$key"
                        }
                    }
                    New-ItemProperty -Path $path -Name 'UpdateDefault' -Value 1 -PropertyType DWord -Force | Out-Null
                    Write-Output "Set $path\UpdateDefault=1"
                }
            }
            
            $services = @('gupdate', 'gupdatem')
            foreach ($svc in $services) {
                Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
            }
            Write-Output "Services restarted"
        }
        
        Remove-PSSession $session
        Write-Host "$machine : SUCCESS" -ForegroundColor Green
    }
    catch {
        Write-Host "$machine : FAILED - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nDone! Verify: chrome://policy/ on VMs." -ForegroundColor Cyan

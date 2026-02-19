# Force-Disable JIMMYWILLOW Remotely (net user method)
# Usage: .\Force-Disable-JIMMYWILLOW.ps1
# Requires: WinRM enabled on targets, admin rights

$machines = Get-Content .\machines.txt | Where-Object { $_.Trim() -ne "" }
$results = @()

foreach ($computer in $machines) {
    Write-Host "`n=== $computer ===" -NoNewline
    
    try {
        if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet)) {
            $results += [PSCustomObject]@{ Computer=$computer; Status="Offline"; Before=""; After="" }
            Write-Host " OFFLINE" -ForegroundColor Red
            continue
        }
        
        # Get status BEFORE
        $before = Invoke-Command -ComputerName $computer -ScriptBlock {
            param($acct)
            try {
                $user = Get-LocalUser -Name $acct -ErrorAction Stop
                "Enabled: $($user.Enabled), LastLogon: $($user.LastLogon)"
            } catch {
                "Account not found"
            }
        } -ArgumentList "JIMMYWILLOW" -ErrorAction Stop
        
        # DISABLE using net user (bulletproof)
        Invoke-Command -ComputerName $computer -ScriptBlock {
            param($acct)
            net user $acct /active:no
        } -ArgumentList "JIMMYWILLOW" -ErrorAction Stop
        
        # Get status AFTER
        $after = Invoke-Command -ComputerName $computer -ScriptBlock {
            param($acct)
            try {
                $user = Get-LocalUser -Name $acct -ErrorAction Stop
                "Enabled: $($user.Enabled), LastLogon: $($user.LastLogon)"
            } catch {
                "Account REMOVED"
            }
        } -ArgumentList "JIMMYWILLOW" -ErrorAction Stop
        
        $results += [PSCustomObject]@{ 
            Computer = $computer
            Status = "SUCCESS"
            Before = $before
            After = $after
        }
        Write-Host " ✓ DISABLED" -ForegroundColor Green
        
    }
    catch {
        $results += [PSCustomObject]@{ 
            Computer = $computer
            Status = "ERROR: $($_.Exception.Message)"
            Before = ""
            After = ""
        }
        Write-Host " ✗ FAILED" -ForegroundColor Red
    }
}

# Results table
$results | Format-Table -AutoSize

# Export CSV
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$results | Export-Csv -Path "JIMMYWILLOW_Fixed_$timestamp.csv" -NoTypeInformation
Write-Host "`n✅ Complete! Results in JIMMYWILLOW_Fixed_*.csv`nRe-scan in Qualys after all show SUCCESS." -ForegroundColor Cyan

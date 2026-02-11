# Disable JIMMYWILLOW on multiple VMs - Fixed for all PowerShell versions
# Usage: .\Disable-JIMMYWILLOW.ps1

$AccountName = "JIMMYWILLOW"
$machines = Get-Content .\machines.txt | Where-Object { $_.Trim() -ne "" }

$results = @()

foreach ($computer in $machines) {
    try {
        if (Test-Connection -ComputerName $computer -Count 1 -Quiet) {
            $result = Invoke-Command -ComputerName $computer -ScriptBlock {
                param($acct)
                try {
                    $user = Get-LocalUser -Name $acct -ErrorAction Stop
                    if ($user.Enabled) {
                        Disable-LocalUser -Name $acct
                        return @{
                            Computer = $env:COMPUTERNAME
                            Status = "JIMMYWILLOW disabled (was enabled)"
                        }
                    } else {
                        return @{
                            Computer = $env:COMPUTERNAME
                            Status = "JIMMYWILLOW already disabled"
                        }
                    }
                }
                catch {
                    return @{
                        Computer = $env:COMPUTERNAME
                        Status = "Error: $($_.Exception.Message)"
                    }
                }
            } -ArgumentList $AccountName -ErrorAction Stop
            
            $results += $result
            Write-Host "✓ $computer`: $($result.Status)"
            
        } else {
            Write-Warning "✗ $computer`: Offline"
        }
    }
    catch {
        Write-Error "✗ $computer`: Remoting failed - $($_.Exception.Message)"
    }
}

# Results summary
$results | Format-Table -AutoSize
$results | Export-Csv -Path "JIMMYWILLOW_Disabled_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" -NoTypeInformation

Write-Host "`n✅ Done! Check CSV. Re-scan in Qualys after verifying no service issues."

# Remote-VP9-Complete-Fix.ps1
# Run as ADMIN locally; targets machines.txt list via WinRM
# Assumes PSRemoting enabled on targets (Enable-PSRemoting)

# Read machine list
$machines = Get-Content .\machines.txt | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }

# Results log
$results = @()
$logPath = "Remote-VP9-Fixed-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

Write-Host " =-- Remote VP9 Removal on $($machines.Count) machines --- " -ForegroundColor Green

foreach ($machine in $machines) {
    Write-Host "Processing $machine ..." -ForegroundColor Yellow
    
    try {
        $result = Invoke-Command -ComputerName $machine -ScriptBlock {
            # [Paste the entire fixed local script block here]
            $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
            if (-not (Test-Path $regPath)) { 
                New-Item $regPath -Force | Out-Null 
            }
            Set-ItemProperty $regPath "AllowDeploymentInSpecialProfiles" -Value 1 -Type DWord -Force

            Get-AppxPackage "*VP9*" | Remove-AppxPackage -ErrorAction SilentlyContinue
            Get-AppxProvisionedPackage -Online "*VP9*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

            Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*VP9*" } | 
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            $userCount = (Get-AppxPackage "*VP9*" | Measure-Object).Count

            Remove-ItemProperty $regPath "AllowDeploymentInSpecialProfiles" -ErrorAction SilentlyContinue

            [PSCustomObject]@{
                Hostname = $env:COMPUTERNAME
                VP9Count = $userCount
                Time     = Get-Date
                Status   = "Success"
            }
        } -ErrorAction Stop

        $results += $result
        Write-Host "  $machine : $($result.VP9Count) VP9 packages remaining" -ForegroundColor Green
    }
    catch {
        $errorMsg = $_.Exception.Message
        $results += [PSCustomObject]@{
            Hostname = $machine
            VP9Count = "N/A"
            Time     = Get-Date
            Status   = "Failed: $errorMsg"
        }
        Write-Host "  $machine : FAILED - $errorMsg" -ForegroundColor Red
    }
}

# Export full log
$results | Export-Csv $logPath -NoTypeInformation
Write-Host "`nCOMPLETE - Results in $logPath" -ForegroundColor Green
Write-Host "Reboot targets & re-scan after 24-72h" -ForegroundColor Cyan

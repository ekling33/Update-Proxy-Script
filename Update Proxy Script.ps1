# Remote Program Scan Script
# Assumes WinRM/PSRemoting enabled on targets; run as admin.

# Prompt for program name
$programName = Read-Host "Enter the program name to search for (e.g., 'Notepad++')"

# Read VM list from machines.txt (one hostname per line)
$machines = Get-Content -Path "machines.txt" | Where-Object { $_.Trim() -ne "" }

Write-Host "Scanning $($machines.Count) VMs for '$programName'..." -ForegroundColor Green

foreach ($machine in $machines) {
    Write-Host "`n--- Scanning $machine ---" -ForegroundColor Yellow
    
    try {
        $result = Invoke-Command -ComputerName $machine -ScriptBlock {
            param($prog)
            $keys = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )
            $found = $false
            foreach ($key in $keys) {
                $apps = Get-ItemProperty $key -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -like "*$prog*" }
                if ($apps) {
                    $found = $true
                    $apps | Select-Object DisplayName, DisplayVersion, Publisher | Format-Table -AutoSize
                }
            }
            if (-not $found) { "Program '$prog' not found." }
        } -ArgumentList $programName -ErrorAction Stop
        
        $result
    }
    catch {
        Write-Host "ERROR: Failed to connect/query $machine ($_)" -ForegroundColor Red
    }
}

Write-Host "`nScan complete!" -ForegroundColor Green

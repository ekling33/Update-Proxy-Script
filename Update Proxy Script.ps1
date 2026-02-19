# Read list of target machines
$machines = Get-Content -Path "machines.txt" | Where-Object { $_ -match '\S' }

# Path to the EXE (update if needed)
$exePath = ".\VSCodeSetup-x64-1.109.4.exe"
$remoteDir = "C:\Temp"

foreach ($machine in $machines) {
    Write-Host "Processing $machine..." -ForegroundColor Yellow
    
    try {
        # Test connection
        if (-not (Test-WSMan -ComputerName $machine -ErrorAction SilentlyContinue)) {
            Write-Warning "WinRM not reachable on $machine"
            continue
        }

        # Create remote session
        $session = New-PSSession -ComputerName $machine -ErrorAction Stop

        # Copy EXE to remote temp dir
        $remotePath = "\\$machine\$remoteDir\VSCodeSetup-x64-1.109.4.exe"
        New-Item -Path "\\$machine\$remoteDir" -ItemType Directory -Force | Out-Null
        Copy-Item -Path $exePath -Destination $remotePath -Force

        # Install silently (Inno Setup: /VERYSILENT /MERGETASKS=!runcode to avoid launch)
        Invoke-Command -Session $session -ScriptBlock {
            param($installer)
            Start-Process -FilePath $installer -ArgumentList "/VERYSILENT", "/MERGETASKS=!runcode" -Wait -NoNewWindow
        } -ArgumentList $remotePath

        # Cleanup
        Invoke-Command -Session $session -ScriptBlock {
            param($installer)
            Remove-Item $installer -Force -ErrorAction SilentlyContinue
        } -ArgumentList $remotePath

        Remove-PSSession $session
        Write-Host "Successfully installed on $machine" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed on $machine : $($_.Exception.Message)"
        if ($session) { Remove-PSSession $session -ErrorAction SilentlyContinue }
    }
}

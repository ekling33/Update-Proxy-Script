# Remove QID-92030 Vulns (Raw Image & VP9 Extensions) - Forceful Remote Script (No Credential Prompts)
# Usage: .\RemoveVulns.ps1  (machines.txt in same dir, run as DOMAIN Admin)

$machines = Get-Content .\machines.txt | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$logFile = "RemovalResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$usePsExec = $true  # Set $false to force Invoke-Command with current creds (no prompt)

$scriptBlock = {
    # Forceful removal with retries (same as before)
    $apps = @('*RawImageExtension*', '*VP9VideoExtensions*')
    foreach ($pattern in $apps) {
        for ($i = 1; $i -le 3; $i++) {
            $pkgs = Get-AppxPackage -AllUsers $pattern -ErrorAction SilentlyContinue
            if ($pkgs) { 
                $pkgs | Remove-AppxPackage -AllUsers -ErrorAction Stop 
                Write-Output "Retry $i: Removed installed $pattern"
            }
            Start-Sleep -Seconds 3
        }
    }
    Get-AppXProvisionedPackage -Online | Where-Object DisplayName -match 'RawImageExtension|VP9VideoExtensions' | 
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    Write-Output "Removed provisioned packages"

    # Kill processes and delete files
    Stop-Process -Name "Microsoft.Photos*", "Movies*", "*Store*", -Force -ErrorAction SilentlyContinue
    $winAppsPath = "C:\Program Files\WindowsApps"
    if (Test-Path $winAppsPath) {
        Get-ChildItem $winAppsPath -Filter "*Raw*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem $winAppsPath -Filter "*VP9*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "Cleaned WindowsApps folder remnants"
    }

    # Verification
    $remaining = Get-AppxPackage -AllUsers '*Raw*|*VP9*' -ErrorAction SilentlyContinue
    if ($remaining) {
        Write-Warning "REMNANTS FOUND: $($remaining.Name)"
    } else {
        Write-Output "SUCCESS: No Raw/VP9 packages remaining on $env:COMPUTERNAME"
    }
}

foreach ($machine in $machines) {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    try {
        if ($usePsExec -and (Test-Path '.\PsExec.exe')) {
            # SYSTEM context via PsExec (no creds needed if local admin)
            $result = & .\PsExec.exe \\$machine -s -nobanner powershell.exe -ExecutionPolicy Bypass -Command "& { $scriptBlock }" 2>&1
            if ($LASTEXITCODE -ne 0) { throw $result }
        } else {
            # Invoke-Command with CURRENT creds (no prompt, assumes admin on targets)
            if (Test-WSMan -ComputerName $machine -ErrorAction SilentlyContinue) {
                $result = Invoke-Command -ComputerName $machine -ScriptBlock $scriptBlock -ErrorAction Stop 2>&1
            } else {
                throw "WinRM not available on $machine"
            }
        }
        "[$timestamp] SUCCESS $machine`n$result`n" | Tee-Object -FilePath $logFile -Append
    } catch {
        $errorMsg = "[$timestamp] FAILED $machine`n$($_.Exception.Message)`n"
        $errorMsg | Tee-Object -FilePath $logFile -Append
    }
}

Write-Output "Script complete. Check $logFile for details."

# Remove QID-92030 Vulns (Raw Image & VP9 Extensions) - Forceful Remote Script
# Usage: .\RemoveVulns.ps1  (machines.txt in same dir)

$machines = Get-Content .\machines.txt | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$logFile = "RemovalResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$usePsExec = $true  # Set to $false to use Invoke-Command instead

$scriptBlock = {
    # Forceful removal with retries
    $apps = @('*RawImageExtension*', '*VP9VideoExtensions*')
    foreach ($pattern in $apps) {
        # Remove installed packages (3 retries)
        for ($i = 1; $i -le 3; $i++) {
            $pkgs = Get-AppxPackage -AllUsers $pattern -ErrorAction SilentlyContinue
            if ($pkgs) { 
                $pkgs | Remove-AppxPackage -AllUsers -ErrorAction Stop 
                Write-Output "Retry $i: Removed installed $pattern"
            }
            Start-Sleep -Seconds 3
        }
    }

    # Remove provisioned packages
    Get-AppXProvisionedPackage -Online | Where-Object DisplayName -match 'RawImageExtension|VP9VideoExtensions' | 
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    Write-Output "Removed provisioned packages"

    # Kill processes and delete files forcefully
    Stop-Process -Name "Microsoft.Photos*", "Movies*", "*Store*", -Force -ErrorAction SilentlyContinue
    $winAppsPath = "C:\Program Files\WindowsApps"
    if (Test-Path $winAppsPath) {
        Get-ChildItem $winAppsPath -Filter "*Raw*" -Recurse -ErrorAction SilentlyContinue | 
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem $winAppsPath -Filter "*VP9*" -Recurse -ErrorAction SilentlyContinue | 
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
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
            # SYSTEM context via PsExec (most forceful)
            $result = & .\PsExec.exe \\$machine -s -nobanner powershell.exe -ExecutionPolicy Bypass -Command "& { $scriptBlock }" 2>&1
        } else {
            # Standard WinRM (ensure Enable-PSRemoting done)
            if (Test-WSMan -ComputerName $machine -ErrorAction SilentlyContinue) {
                $cred = Get-Credential -Message "Enter admin creds for $machine" -UserName "DOMAIN\AdminUser"
                $result = Invoke-Command -ComputerName $machine -Credential $cred -ScriptBlock $scriptBlock -ErrorAction Stop 2>&1
            } else {
                throw "WinRM not available"
            }
        }
        "[$timestamp] SUCCESS $machine`n$result`n" | Tee-Object -FilePath $logFile -Append
    } catch {
        $errorMsg = "[$timestamp] FAILED $machine`n$($_.Exception.Message)`n"
        $errorMsg | Tee-Object -FilePath $logFile -Append
    }
}

Write-Output "Script complete. Check $logFile for details."

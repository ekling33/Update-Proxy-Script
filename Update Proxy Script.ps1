# Clear O365 caches and registry for all profiles - Run as Administrator
# Logs to C:\O365Cleanup.log

$LogPath = "C:\temp\O365Cleanup.log"
function Write-Log { param([string]$Message); "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $Message" | Out-File -FilePath $LogPath -Append; Write-Host $Message }

Write-Log "Starting O365 cleanup for all profiles."

# Get all profiles from registry
$ProfileList = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue
foreach ($ProfileKey in $ProfileList) {
    $ProfilePath = (Get-ItemProperty -Path $ProfileKey.PSPath -Name ProfileImagePath).ProfileImagePath
    if ($ProfilePath -match 'Default|Public|All Users|Temp') { continue }
    
    $UserName = Split-Path $ProfilePath -Leaf
    $SID = $ProfileKey.PSChildName
    $Loaded = Test-Path "HKU:\$SID"
    
    Write-Log "Processing profile: $UserName ($SID) - Loaded: $Loaded"
    
    # Clear files/caches (always safe, skips locked)
    $CachePaths = @(
        "$ProfilePath\AppData\Local\Microsoft\IdentityCache",
        "$ProfilePath\AppData\Local\Microsoft\OneAuth",
        "$ProfilePath\AppData\Local\Microsoft\Office\16.0\OfficeFileCache",
        "$ProfilePath\AppData\Local\Microsoft\Outlook"
    )
    foreach ($CachePath in $CachePaths) {
        if (Test-Path $CachePath) {
            try {
                Remove-Item -Path $CachePath -Recurse -Force -ErrorAction Stop
                Write-Log "Deleted: $CachePath"
            } catch {
                Write-Log "Skipped locked: $CachePath"
            }
        }
    }
    
    # Clear registry if unloaded
    if (-not $Loaded) {
        $HivePath = "HKEY_USERS\$SID"
        if (Test-Path $HivePath) {
            Remove-Item "$HivePath\SOFTWARE\Microsoft\Office\16.0\Common\Identity" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "$HivePath\SOFTWARE\Microsoft\Office\16.0\Outlook\Profiles" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Cleared registry Identity/Profiles for unloaded profile."
        }
    } else {
        Write-Log "Skipped registry for loaded profile $SID (logoff user first)."
    }
    
    # Clear credentials (system-wide where applicable)
    cmdkey /list:$SID | Out-Null
    cmdkey /delete:$SID 2>$null
}

# System-wide credentials for O365
cmd /c "cmdkey /list | findstr /I o365 microsoftoffice outlook | for /F %i in ('cmdkey /list ^| findstr /I o365 microsoftoffice outlook') do cmdkey /delete %i" 2>$null

Write-Log "Cleanup complete. Review log and restart."

# Run as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Run as Administrator"
    exit 1
}

# 1. Clean C:\Windows\CCMCache
$ccmPath = "C:\Windows\CCMCache"
if (Test-Path $ccmPath) {
    Get-ChildItem -Path $ccmPath -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "Cleaned CCMCache"
}

# 2. Clean C:\Windows\Temp
$tempPath = "C:\Windows\Temp"
Get-ChildItem -Path $tempPath -Recurse -Force | Remove-Item -Force -ErrorAction SilentlyContinue
Write-Output "Cleaned Windows Temp"

# 3. Clean Outlook .nst and .ost files for all users
$users = Get-ChildItem "C:\Users" -Directory
foreach ($user in $users) {
    if ($user.Name -eq "Public" -or $user.Name -eq "Default") { continue }
    $outlookPath = Join-Path $user.FullName "\AppData\Local\Microsoft\Outlook"
    if (Test-Path $outlookPath) {
        Get-ChildItem -Path $outlookPath -Filter "*.nst" -Recurse -Force | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $outlookPath -Filter "*.ost" -Recurse -Force | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Output "Cleaned Outlook files for $($user.Name)"
    }
}

# 4. Clear all Event Viewer logs
Get-WinEvent -ListLog * | Where-Object { $_.RecordCount -gt 0 } | ForEach-Object {
    try {
        wevtutil cl $_.LogName
        Write-Output "Cleared $($_.LogName)"
    } catch {
        Write-Warning "Failed to clear $($_.LogName): $_"
    }
}

# 5a. Clear Recycle Bin (system-wide)
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Output "Cleared Recycle Bin"

# 5b. Clear user temp files for all users
foreach ($user in $users) {
    if ($user.Name -eq "Public" -or $user.Name -eq "Default") { continue }
    $localTemp = Join-Path $user.FullName "AppData\Local\Temp"
    $recent = Join-Path $user.FullName "AppData\Roaming\Microsoft\Windows\Recent"
    $temps = @($localTemp, $recent)
    foreach ($dir in $temps) {
        if (Test-Path $dir) {
            Get-ChildItem -Path $dir -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Output "Cleaned temp files for $($user.Name)"
}

Write-Output "Cleanup complete."

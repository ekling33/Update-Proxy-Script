# Run as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Run as Administrator"
    exit 1
}

# Function to safely remove directory contents (no popups)
function Remove-DirContents {
    param([string]$Path)
    if (Test-Path $Path) {
        Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        # Cleanup any remaining top-level
        Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# 1. Clean C:\Windows\CCMCache
Remove-DirContents "C:\Windows\CCMCache"
Write-Output "Cleaned CCMCache"

# 2. Clean C:\Windows\Temp
Remove-DirContents "C:\Windows\Temp"
Write-Output "Cleaned Windows Temp"

# 3. Clean Outlook .nst/.ost for all users
$users = Get-ChildItem "C:\Users" -Directory
foreach ($user in $users) {
    if ($user.Name -eq "Public" -or $user.Name -eq "Default" -or $user.Name -eq "All Users") { continue }
    $outlookPath = Join-Path $user.FullName "AppData\Local\Microsoft\Outlook"
    if (Test-Path $outlookPath) {
        Get-ChildItem -Path $outlookPath -Filter "*.nst" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Get-ChildItem -Path $outlookPath -Filter "*.ost" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Output "Cleaned Outlook files for $($user.Name)"
    }
}

# 4. Clear Event Viewer logs silently
Get-WinEvent -ListLog * | Where-Object { $_.RecordCount -gt 0 } | ForEach-Object {
    try {
        wevtutil cl $_.LogName 2>$null
        Write-Output "Cleared $($_.LogName)"
    } catch { }
}

# 5a. Clear Recycle Bin
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Output "Cleared Recycle Bin"

# 5b. Clear user temps
foreach ($user in $users) {
    if ($user.Name -eq "Public" -or $user.Name -eq "Default" -or $user.Name -eq "All Users") { continue }
    $localTemp = Join-Path $user.FullName "AppData\Local\Temp"
    $recent = Join-Path $user.FullName "AppData\Roaming\Microsoft\Windows\Recent"
    Remove-DirContents $localTemp
    Remove-DirContents $recent
    Write-Output "Cleaned temp files for $($user.Name)"
}

Write-Output "Cleanup complete - no popups."

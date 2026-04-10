param(
    [string]$workDir = "C:\Temp\WinREPatch",
    [string]$packagePath = ""
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $Message"
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Run-Cmd {
    param(
        [string]$FilePath,
        [string]$Arguments
    )
    Write-Log "$FilePath $Arguments"
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "Command failed with exit code $($p.ExitCode): $FilePath $Arguments"
    }
}

if (-not (Test-Admin)) {
    throw "Run this script in an elevated PowerShell session."
}

if (-not (Test-Path $workDir)) {
    New-Item -Path $workDir -ItemType Directory -Force | Out-Null
}

$mountDir = Join-Path $workDir "Mount"
if (-not (Test-Path $mountDir)) {
    New-Item -Path $mountDir -ItemType Directory -Force | Out-Null
}

Write-Log "Getting WinRE configuration"
$reagentInfo = & reagentc /info 2>&1
$reagentText = $reagentInfo | Out-String
$reagentText | Write-Host

if ($reagentText -notmatch "Windows RE status:\s+Enabled") {
    Write-Log "WinRE is not enabled. Attempting to enable it."
    & reagentc /enable
    $reagentInfo = & reagentc /info 2>&1
    $reagentText = $reagentInfo | Out-String
}

if ($reagentText -notmatch "Windows RE location:\s+(.*)") {
    throw "Could not determine Windows RE location from reagentc /info"
}

$winreLocation = $matches[1].Trim()
Write-Log "WinRE location: $winreLocation"

$normalizedPath = $winreLocation -replace '^\\\\\?\\GLOBALROOT\\device\\harddisk\d+\\partition\d+', ''
if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
    $normalizedPath = "\Recovery\WindowsRE"
}

$localCandidates = @(
    "C:\Recovery\WindowsRE\winre.wim",
    "$env:SystemRoot\System32\Recovery\winre.wim"
)

$winreWim = $null
foreach ($candidate in $localCandidates) {
    if (Test-Path $candidate) {
        $winreWim = $candidate
        break
    }
}

if (-not $winreWim) {
    Write-Log "Could not directly access WinRE path from GLOBALROOT reference."
    Write-Log "Trying common local WinRE paths."
}

if (-not $winreWim) {
    throw "Could not find winre.wim in common paths. Check reagentc /info and recovery partition."
}

Write-Log "Using WinRE image: $winreWim"

Write-Log "Disabling WinRE"
& reagentc /disable | Out-Host

Write-Log "Mounting WinRE image"
Run-Cmd -FilePath "dism.exe" -Arguments "/Mount-Image /ImageFile:`"$winreWim`" /Index:1 /MountDir:`"$mountDir`""

if (-not [string]::IsNullOrWhiteSpace($packagePath)) {
    if (-not (Test-Path $packagePath)) {
        Write-Log "Package path provided but file not found: $packagePath"
        Write-Log "Continuing without package."
    }
    else {
        Write-Log "Applying package: $packagePath"
        Run-Cmd -FilePath "dism.exe" -Arguments "/Image:`"$mountDir`" /Add-Package /PackagePath:`"$packagePath`""
    }
}
else {
    Write-Log "No packagePath provided. Skipping Add-Package step."
}

Write-Log "Running component cleanup"
try {
    Run-Cmd -FilePath "dism.exe" -Arguments "/Image:`"$mountDir`" /Cleanup-Image /StartComponentCleanup"
}
catch {
    Write-Log "Cleanup step failed or is not applicable. Continuing."
}

Write-Log "Committing and unmounting image"
Run-Cmd -FilePath "dism.exe" -Arguments "/Unmount-Image /MountDir:`"$mountDir`" /Commit"

Write-Log "Re-enabling WinRE"
& reagentc /enable | Out-Host

Write-Log "Final WinRE status"
& reagentc /info | Out-Host

Write-Log "Checking WinREVersion registry value"
try {
    reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v WinREVersion
}
catch {
    Write-Log "WinREVersion registry value is still missing."
}

Write-Log "Script completed"

# PatchWinREScript_2004plus.ps1
# This script is for Windows 10, version 2004 and later versions, including Windows 11.
param(
    [string]$workDir = $env:TEMP,
    [Parameter(Mandatory=$true)]
    [string]$packagePath
)

# Check if running as admin
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Must run as administrator."
    exit 1
}

# Get WinRE info
$reagentInfo = reagentc /info
if ($LASTEXITCODE -ne 0) {
    Write-Error "reagentc /info failed."
    exit 1
}

if ($reagentInfo -match "Windows RE status: *Enabled") {
    # Disable WinRE
    reagentc /disable
    if ($LASTEXITCODE -ne 0) {
        Write-Error "reagentc /disable failed."
        exit 1
    }
}

# Find WinRE.wim
$winrePartition = $null
$winreMountDir = "$workDir\WinREMountDir"
if (!(Test-Path $winreMountDir)) {
    New-Item -Path $winreMountDir -ItemType Directory -Force | Out-Null
}

$winreWimPath = reagentc /info | Select-String "Windows RE image location:" | ForEach-Object { $_.Line -replace ".*:\s+", "" }
if ([string]::IsNullOrEmpty($winreWimPath)) {
    Write-Error "WinRE image location not found."
    exit 1
}

# Mount WinRE
Write-Host "Mounting WinRE image at $winreWimPath to $winreMountDir"
Dism /Mount-Image /ImageFile:$winreWimPath /index:1 /MountDir:$winreMountDir /readonly:no
if ($LASTEXITCODE -ne 0) {
    Write-Error "Mount failed."
    exit 1
}

# Apply package
Write-Host "Applying package $packagePath"
Dism /Add-Package /Image:$winreMountDir /PackagePath:$packagePath
if ($LASTEXITCODE -ne 0) {
    Write-Error "Add-Package failed."
    Dism /Unmount-Image /MountDir:$winreMountDir /Discard
    exit 1
}

# Commit
Dism

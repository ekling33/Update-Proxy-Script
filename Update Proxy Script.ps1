#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ExcludeAppPools = @(
        '.NET v4.5',
        '.NET v4.5 Classic',
        'DefaultAppPool'
    ),

    [switch]$RecycleUpdatedPools,

    [switch]$SkipConfigBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

    return $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function ConvertTo-PlainText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)

    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated Windows PowerShell session: Run as Administrator.'
}

try {
    Import-Module WebAdministration -ErrorAction Stop
}
catch {
    throw "Could not load the WebAdministration module. Verify IIS Management Scripts and Tools is installed. Original error: $($_.Exception.Message)"
}

$UserName = Read-Host 'Enter the IIS application-pool identity username (example: DOMAIN\svc_iis)'

if ([string]::IsNullOrWhiteSpace($UserName)) {
    throw 'A username is required.'
}

$NewPassword = Read-Host 'Enter the new password' -AsSecureString

if ($null -eq $NewPassword -or $NewPassword.Length -eq 0) {
    throw 'A non-empty password is required.'
}

$applicationHostConfig = Join-Path $env:WINDIR 'System32\inetsrv\config\applicationHost.config'

if (-not (Test-Path -LiteralPath $applicationHostConfig)) {
    throw "IIS configuration was not found at: $applicationHostConfig"
}

if (-not $SkipConfigBackup) {
    $backupDirectory = Join-Path `
        (Split-Path -Parent $applicationHostConfig) `
        'PasswordUpdateBackups'

    if (-not (Test-Path -LiteralPath $backupDirectory)) {
        New-Item -Path $backupDirectory -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path `
        $backupDirectory `
        "applicationHost.config.$timestamp.bak"

    if ($PSCmdlet.ShouldProcess(
        $applicationHostConfig,
        "Create backup at $backupFile"
    )) {
        Copy-Item `
            -LiteralPath $applicationHostConfig `
            -Destination $backupFile `
            -Force

        Write-Host "Created IIS configuration backup: $backupFile" -ForegroundColor Cyan
    }
}

$plainTextPassword = ConvertTo-PlainText -SecureString $NewPassword
$updatedPools = @()

try {
    $targetPools = @(
        Get-ChildItem IIS:\AppPools | Where-Object {
            $_.Name -notin $ExcludeAppPools -and
            $_.processModel.identityType -eq 'SpecificUser' -and
            $_.processModel.userName -ieq $UserName
        }
    )

    if ($targetPools.Count -eq 0) {
        Write-Warning "No non-excluded application pools using '$UserName' were found. No changes were made."
        return
    }

    Write-Host ""
    Write-Host "Matching application pools for '$UserName':" -ForegroundColor Cyan

    foreach ($pool in $targetPools) {
        Write-Host "  - $($pool.Name)"
    }

    Write-Host ""

    foreach ($pool in $targetPools) {
        $poolName = $pool.Name
        $poolPath = "IIS:\AppPools\$poolName"

        if ($PSCmdlet.ShouldProcess(
            "IIS application pool '$poolName'",
            "Update password for '$UserName'"
        )) {
            Set-ItemProperty `
                -Path $poolPath `
                -Name 'processModel.password' `
                -Value $plainTextPassword

            $updatedPools += $poolName

            Write-Host "Updated: $poolName" -ForegroundColor Green
        }
    }
}
finally {
    $plainTextPassword = $null
}

if ($RecycleUpdatedPools -and $updatedPools.Count -gt 0 -and -not $WhatIfPreference) {
    Write-Host ""

    foreach ($poolName in $updatedPools) {
        if ($PSCmdlet.ShouldProcess(
            "IIS application pool '$poolName'",
            'Recycle application pool'
        )) {
            Restart-WebAppPool -Name $poolName

            Write-Host "Recycled: $poolName" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host 'Completed.' -ForegroundColor Green

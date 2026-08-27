#requires -Version 5.1
<#+
.SYNOPSIS
    Updates the password for IIS application-pool identities that use a prompted username,
    excluding the built-in .NET v4.5, .NET v4.5 Classic, and DefaultAppPool pools.

.DESCRIPTION
    Run locally on an IIS server from an elevated Windows PowerShell 5.1 session.
    The script prompts for the IIS identity username and its new password, then updates only
    non-excluded pools whose process-model identity is SpecificUser and whose username matches.

    A timestamped backup of applicationHost.config is created by default. Use -WhatIf for a
    dry run, and use -RecycleUpdatedPools to recycle only the pools that were changed.

.EXAMPLE
    .\Update-IISAppPoolIdentityPassword.ps1 -WhatIf

.EXAMPLE
    .\Update-IISAppPoolIdentityPassword.ps1 -RecycleUpdatedPools
#>

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
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-PlainText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated Windows PowerShell session (Run as Administrator).'
}

$UserName = Read-Host 'Enter the IIS application-pool identity username (for example, DOMAIN\\svc_iis)'
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

try {
    Add-Type -AssemblyName 'Microsoft.Web.Administration' -ErrorAction Stop
}
catch {
    throw 'Could not load Microsoft.Web.Administration. Confirm that IIS Management Scripts and Tools/IIS are installed on this server.'
}

if (-not $SkipConfigBackup) {
    $backupDirectory = Join-Path (Split-Path -Parent $applicationHostConfig) 'PasswordUpdateBackups'
    if (-not (Test-Path -LiteralPath $backupDirectory)) {
        New-Item -Path $backupDirectory -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $backupDirectory "applicationHost.config.$timestamp.bak"

    if ($PSCmdlet.ShouldProcess($applicationHostConfig, "Create configuration backup at $backupFile")) {
        Copy-Item -LiteralPath $applicationHostConfig -Destination $backupFile -Force
        Write-Verbose "Created backup: $backupFile"
    }
}

$plainTextPassword = ConvertTo-PlainText -SecureString $NewPassword
$updatedPools = New-Object 'System.Collections.Generic.List[string]'
$serverManager = $null

try {
    $serverManager = New-Object Microsoft.Web.Administration.ServerManager

    $targetPools = @(
        $serverManager.ApplicationPools | Where-Object {
            $_.Name -notin $ExcludeAppPools -and
            $_.ProcessModel.IdentityType -eq [Microsoft.Web.Administration.ProcessModelIdentityType]::SpecificUser -and
            $_.ProcessModel.UserName -ieq $UserName
        }
    )

    if ($targetPools.Count -eq 0) {
        Write-Warning "No non-excluded application pools using the specific identity '$UserName' were found. No changes were made."
        return
    }

    Write-Host "Matching application pools for '$UserName':" -ForegroundColor Cyan
    $targetPools | ForEach-Object { Write-Host "  - $($_.Name)" }

    $changed = $false
    foreach ($pool in $targetPools) {
        if ($PSCmdlet.ShouldProcess("IIS application pool '$($pool.Name)'", "Update password for identity '$UserName'")) {
            $pool.ProcessModel.Password = $plainTextPassword
            $updatedPools.Add($pool.Name)
            $changed = $true
        }
    }

    if ($changed) {
        $serverManager.CommitChanges()
        Write-Host "Updated password in IIS configuration for $($updatedPools.Count) application pool(s)." -ForegroundColor Green
    }
    else {
        Write-Host 'No configuration changes were committed.' -ForegroundColor Yellow
    }
}
finally {
    $plainTextPassword = $null
    if ($null -ne $serverManager) {
        $serverManager.Dispose()
    }
}

if ($RecycleUpdatedPools -and $updatedPools.Count -gt 0 -and -not $WhatIfPreference) {
    $serverManager = New-Object Microsoft.Web.Administration.ServerManager
    try {
        foreach ($poolName in $updatedPools) {
            $pool = $serverManager.ApplicationPools[$poolName]
            if ($null -ne $pool -and $PSCmdlet.ShouldProcess("IIS application pool '$poolName'", 'Recycle application pool')) {
                $pool.Recycle()
                Write-Host "Recycled: $poolName" -ForegroundColor Green
            }
        }
    }
    finally {
        $serverManager.Dispose()
    }
}

Write-Host 'Completed.' -ForegroundColor Green

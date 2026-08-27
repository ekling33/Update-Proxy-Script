#requires -Version 5.1
<#+
.SYNOPSIS
    Stops IIS, waits for confirmation, updates a prompted IIS app-pool identity password,
    starts IIS, and reports the final status of every application pool.

.DESCRIPTION
    Run locally on an IIS server from an elevated Windows PowerShell 5.1 session.

    IMPORTANT: -WhatIf is a simulation mode. It intentionally does NOT stop IIS, does NOT pause
    at the IIS-stopped prompt, does NOT create a backup, does NOT change passwords, and does NOT
    start IIS. Run without -WhatIf during the maintenance window to perform the actual sequence.

    The following pools are never modified:
      - .NET v4.5
      - .NET v4.5 Classic
      - DefaultAppPool
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ExcludeAppPools = @(
        '.NET v4.5',
        '.NET v4.5 Classic',
        'DefaultAppPool'
    ),

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

function Wait-ServiceStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [System.ServiceProcess.ServiceControllerStatus]$DesiredStatus,

        [int]$TimeoutSeconds = 90
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        $service = Get-Service -Name $Name
        $service.Refresh()

        if ($service.Status -eq $DesiredStatus) {
            return
        }

        Start-Sleep -Seconds 2
    }
    while ((Get-Date) -lt $deadline)

    throw "Service '$Name' did not reach '$DesiredStatus' within $TimeoutSeconds seconds. Current state: $($service.Status)."
}

function Show-AppPoolStatus {
    Write-Host ''
    Write-Host 'Final IIS application-pool status:' -ForegroundColor Cyan

    $status = foreach ($pool in Get-ChildItem IIS:\AppPools | Sort-Object Name) {
        $runtimeState = 'Unknown'

        try {
            $runtimeState = (Get-WebAppPoolState -Name $pool.Name).Value
        }
        catch {
            $runtimeState = 'Unavailable'
        }

        [PSCustomObject]@{
            Name         = $pool.Name
            State        = $runtimeState
            IdentityType = $pool.processModel.identityType
            UserName     = $pool.processModel.userName
        }
    }

    $status | Format-Table -AutoSize

    Write-Host ''
    Write-Host ("Summary: Started={0}; Stopped={1}; Other/Unavailable={2}" -f `
        @($status | Where-Object State -eq 'Started').Count, `
        @($status | Where-Object State -eq 'Stopped').Count, `
        @($status | Where-Object { $_.State -notin @('Started', 'Stopped') }).Count) -ForegroundColor Cyan
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated Windows PowerShell session (Run as Administrator).'
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

Write-Host ''
Write-Host "Matching application pools for '$UserName':" -ForegroundColor Cyan
$targetPools | ForEach-Object { Write-Host "  - $($_.Name)" }

$runningPoolsBeforeStop = @(
    Get-ChildItem IIS:\AppPools | Where-Object {
        (Get-WebAppPoolState -Name $_.Name).Value -eq 'Started'
    } | Select-Object -ExpandProperty Name
)

Write-Host ''
Write-Host "Application pools running before IIS is stopped: $($runningPoolsBeforeStop.Count)" -ForegroundColor Cyan

if ($WhatIfPreference) {
    Write-Host ''
    Write-Host 'WHATIF MODE: IIS will not be stopped, no pause will occur, no passwords will be changed, and IIS will not be started.' -ForegroundColor Yellow
    Write-Host 'Run the script without -WhatIf during the maintenance window to stop IIS and reach the Enter prompt.' -ForegroundColor Yellow
}

$plainTextPassword = ConvertTo-PlainText -SecureString $NewPassword
$iisStopped = $false

try {
    if (-not $SkipConfigBackup) {
        $backupDirectory = Join-Path (Split-Path -Parent $applicationHostConfig) 'PasswordUpdateBackups'
        if (-not (Test-Path -LiteralPath $backupDirectory)) {
            if ($PSCmdlet.ShouldProcess($backupDirectory, 'Create directory')) {
                New-Item -Path $backupDirectory -ItemType Directory -Force | Out-Null
            }
        }

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupFile = Join-Path $backupDirectory "applicationHost.config.$timestamp.bak"

        if ($PSCmdlet.ShouldProcess($applicationHostConfig, "Create backup at $backupFile")) {
            Copy-Item -LiteralPath $applicationHostConfig -Destination $backupFile -Force
            Write-Host "Created IIS configuration backup: $backupFile" -ForegroundColor Cyan
        }
    }

    if ($PSCmdlet.ShouldProcess('IIS services (W3SVC and WAS)', 'Stop IIS before updating application-pool passwords')) {
        Write-Host ''
        Write-Host 'Stopping IIS services...' -ForegroundColor Yellow

        $w3svc = Get-Service -Name W3SVC
        if ($w3svc.Status -ne 'Stopped') {
            Stop-Service -Name W3SVC -Force
            Wait-ServiceStatus -Name W3SVC -DesiredStatus Stopped
        }

        $was = Get-Service -Name WAS
        if ($was.Status -ne 'Stopped') {
            Stop-Service -Name WAS -Force
            Wait-ServiceStatus -Name WAS -DesiredStatus Stopped
        }

        $iisStopped = $true
        Write-Host ''
        Write-Host 'IIS STOPPED. Press Enter to continue...' -ForegroundColor Yellow
        [void](Read-Host)
    }

    foreach ($pool in $targetPools) {
        $poolName = $pool.Name
        $poolPath = "IIS:\AppPools\$poolName"

        if ($PSCmdlet.ShouldProcess("IIS application pool '$poolName'", "Update password for '$UserName'")) {
            Set-ItemProperty -Path $poolPath -Name 'processModel.password' -Value $plainTextPassword
            Write-Host "Updated password: $poolName" -ForegroundColor Green
        }
    }
}
finally {
    $plainTextPassword = $null

    if ($iisStopped -and -not $WhatIfPreference) {
        Write-Host ''
        Write-Host 'Starting IIS services...' -ForegroundColor Yellow

        try {
            $was = Get-Service -Name WAS
            if ($was.Status -ne 'Running') {
                Start-Service -Name WAS
                Wait-ServiceStatus -Name WAS -DesiredStatus Running
            }

            $w3svc = Get-Service -Name W3SVC
            if ($w3svc.Status -ne 'Running') {
                Start-Service -Name W3SVC
                Wait-ServiceStatus -Name W3SVC -DesiredStatus Running
            }

            Write-Host 'IIS services are running.' -ForegroundColor Green

            foreach ($poolName in $runningPoolsBeforeStop) {
                try {
                    $currentState = (Get-WebAppPoolState -Name $poolName).Value
                    if ($currentState -ne 'Started') {
                        Start-WebAppPool -Name $poolName
                    }
                }
                catch {
                    Write-Warning "Could not restore application pool '$poolName' to Started: $($_.Exception.Message)"
                }
            }
        }
        catch {
            Write-Error "IIS was stopped, but the script could not fully start IIS again: $($_.Exception.Message)"
            throw
        }
    }
}

if (-not $WhatIfPreference) {
    Show-AppPoolStatus
}

Write-Host ''
Write-Host 'Completed.' -ForegroundColor Green

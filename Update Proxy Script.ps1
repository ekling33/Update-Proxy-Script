#requires -Version 5.1
<#+
.SYNOPSIS
    Stops IIS and two services, updates their credentials plus IIS application-pool credentials,
    then starts the services and IIS and reports the resulting states.

.DESCRIPTION
    Run from an elevated Windows PowerShell 5.1 session on the target server, or invoke remotely
    through your existing PowerShell remoting method as an administrator. No admin credentials are
    requested by this script.

    The script performs this order:
      1. Prompts for a service account and password.
      2. Stops IIS (W3SVC) and waits for it to stop.
      3. Stops AuditService and SubmitFormManager and waits for both to stop.
      4. Updates both service logon accounts and passwords.
      5. Updates every IIS app pool that currently uses SpecificUser to the supplied account/password.
      6. Starts the two services and waits for their final status.
      7. Starts IIS (W3SVC), starts IIS application pools, and reports final pool states.
#>

[CmdletBinding()]
param(
    [int]$StopTimeoutSeconds = 120,
    [int]$StartTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'

$TargetServices = @(
    'AuditService',
    'SubmitFormManager'
)

$IISServiceName = 'W3SVC'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-SecureStringToPlainText {
    param(
        [Parameter(Mandatory)]
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

function Wait-ForServiceStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Running', 'Stopped')]
        [string]$DesiredStatus,

        [Parameter(Mandatory)]
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $service = Get-Service -Name $Name -ErrorAction Stop
        if ($service.Status.ToString() -eq $DesiredStatus) {
            return $service
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    $finalService = Get-Service -Name $Name -ErrorAction Stop
    throw "Timed out waiting for service '$Name' to reach '$DesiredStatus'. Current status: $($finalService.Status)."
}

function Get-ServiceResult {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Action,

        [string]$Detail = ''
    )

    try {
        $service = Get-Service -Name $Name -ErrorAction Stop
        [pscustomobject]@{
            Item        = $Name
            Type        = 'Windows Service'
            Action      = $Action
            FinalStatus = $service.Status.ToString()
            Detail      = $Detail
        }
    }
    catch {
        [pscustomobject]@{
            Item        = $Name
            Type        = 'Windows Service'
            Action      = $Action
            FinalStatus = 'Not found'
            Detail      = $_.Exception.Message
        }
    }
}

if (-not (Test-IsAdministrator)) {
    throw 'This script must be run in an elevated Windows PowerShell session as an administrator.'
}

$ServiceAccount = Read-Host -Prompt 'Enter the service account (for example, PROD\serviceaccount)'
if ([string]::IsNullOrWhiteSpace($ServiceAccount)) {
    throw 'A service account is required.'
}

$SecurePassword = Read-Host -Prompt "Enter the password for $ServiceAccount" -AsSecureString
$PlainTextPassword = Convert-SecureStringToPlainText -SecureString $SecurePassword

$ServiceStartResults = @()
$AppPoolStartResults = @()

try {
    Import-Module WebAdministration -ErrorAction Stop

    # Verify all required Windows services exist before stopping IIS or applying any changes.
    $missingServices = @($TargetServices | Where-Object {
        -not (Get-Service -Name $_ -ErrorAction SilentlyContinue)
    })
    if ($missingServices.Count -gt 0) {
        throw "Required service(s) not found: $($missingServices -join ', '). No changes were made."
    }

    Write-Host "Stopping IIS service ($IISServiceName)..." -ForegroundColor Cyan
    $iisService = Get-Service -Name $IISServiceName -ErrorAction Stop
    if ($iisService.Status -ne 'Stopped') {
        Stop-Service -Name $IISServiceName -Force -ErrorAction Stop
        Wait-ForServiceStatus -Name $IISServiceName -DesiredStatus Stopped -TimeoutSeconds $StopTimeoutSeconds | Out-Null
    }
    Write-Host "IIS service status: $((Get-Service -Name $IISServiceName).Status)" -ForegroundColor Green

    foreach ($ServiceName in $TargetServices) {
        Write-Host "Stopping service $ServiceName..." -ForegroundColor Cyan
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        if ($service.Status -ne 'Stopped') {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            Wait-ForServiceStatus -Name $ServiceName -DesiredStatus Stopped -TimeoutSeconds $StopTimeoutSeconds | Out-Null
        }
        Write-Host "$ServiceName status: $((Get-Service -Name $ServiceName).Status)" -ForegroundColor Green
    }

    foreach ($ServiceName in $TargetServices) {
        Write-Host "Updating logon credentials for $ServiceName..." -ForegroundColor Cyan
        $scOutput = & "$env:SystemRoot\System32\sc.exe" config $ServiceName obj= $ServiceAccount password= $PlainTextPassword 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to update service '$ServiceName'. sc.exe output: $($scOutput -join ' ')"
        }
    }

    $UpdatedAppPools = @()
    $SkippedAppPools = @()

    foreach ($appPool in Get-ChildItem -Path IIS:\AppPools) {
        $poolName = $appPool.Name
        $identityType = [string]$appPool.processModel.identityType

        if ($identityType -eq 'SpecificUser') {
            Write-Host "Updating IIS application pool credentials: $poolName" -ForegroundColor Cyan
            Set-ItemProperty -Path "IIS:\AppPools\$poolName" -Name processModel -Value @{
                identityType = 'SpecificUser'
                userName     = $ServiceAccount
                password     = $PlainTextPassword
            } -ErrorAction Stop
            $UpdatedAppPools += $poolName
        }
        else {
            $SkippedAppPools += [pscustomobject]@{
                Item        = $poolName
                Type        = 'IIS Application Pool'
                Action      = 'Not updated or started'
                FinalStatus = $appPool.State.ToString()
                Detail      = "Skipped because identity type is $identityType, not SpecificUser."
            }
        }
    }

    # Start the two Windows services first, as requested, and record final state even if a start fails.
    foreach ($ServiceName in $TargetServices) {
        try {
            Write-Host "Starting service $ServiceName..." -ForegroundColor Cyan
            $service = Get-Service -Name $ServiceName -ErrorAction Stop
            if ($service.Status -ne 'Running') {
                Start-Service -Name $ServiceName -ErrorAction Stop
                Wait-ForServiceStatus -Name $ServiceName -DesiredStatus Running -TimeoutSeconds $StartTimeoutSeconds | Out-Null
            }
            $ServiceStartResults += Get-ServiceResult -Name $ServiceName -Action 'Started' -Detail "Configured logon account: $ServiceAccount"
        }
        catch {
            $ServiceStartResults += Get-ServiceResult -Name $ServiceName -Action 'Start failed' -Detail $_.Exception.Message
        }
    }

    # Start IIS after the two services, as requested.
    $iisStartDetail = ''
    try {
        Write-Host "Starting IIS service ($IISServiceName)..." -ForegroundColor Cyan
        $iisService = Get-Service -Name $IISServiceName -ErrorAction Stop
        if ($iisService.Status -ne 'Running') {
            Start-Service -Name $IISServiceName -ErrorAction Stop
            Wait-ForServiceStatus -Name $IISServiceName -DesiredStatus Running -TimeoutSeconds $StartTimeoutSeconds | Out-Null
        }
        $iisStartDetail = 'IIS service started successfully.'
    }
    catch {
        $iisStartDetail = "IIS service start failed: $($_.Exception.Message)"
    }

    # Explicitly start each updated pool and capture each final state. This is done after IIS starts.
    foreach ($poolName in $UpdatedAppPools) {
        try {
            Write-Host "Starting IIS application pool $poolName..." -ForegroundColor Cyan
            $pool = Get-Item -Path "IIS:\AppPools\$poolName" -ErrorAction Stop
            if ($pool.State -ne 'Started') {
                Start-WebAppPool -Name $poolName -ErrorAction Stop
            }

            Start-Sleep -Seconds 2
            $finalPool = Get-Item -Path "IIS:\AppPools\$poolName" -ErrorAction Stop
            $AppPoolStartResults += [pscustomobject]@{
                Item        = $poolName
                Type        = 'IIS Application Pool'
                Action      = 'Started'
                FinalStatus = $finalPool.State.ToString()
                Detail      = "Configured identity: $ServiceAccount. $iisStartDetail"
            }
        }
        catch {
            $finalStatus = 'Unknown'
            try { $finalStatus = (Get-Item -Path "IIS:\AppPools\$poolName" -ErrorAction Stop).State.ToString() } catch { }
            $AppPoolStartResults += [pscustomobject]@{
                Item        = $poolName
                Type        = 'IIS Application Pool'
                Action      = 'Start failed'
                FinalStatus = $finalStatus
                Detail      = $_.Exception.Message
            }
        }
    }

    Write-Host "`nService start results:" -ForegroundColor Yellow
    $ServiceStartResults | Format-Table -AutoSize

    Write-Host "`nIIS application pool start results (pools updated to SpecificUser):" -ForegroundColor Yellow
    if ($AppPoolStartResults.Count -gt 0) {
        $AppPoolStartResults | Format-Table -AutoSize
    }
    else {
        Write-Host 'No IIS application pools using SpecificUser were found.' -ForegroundColor DarkYellow
    }

    if ($SkippedAppPools.Count -gt 0) {
        Write-Host "`nIIS application pools skipped (built-in/non-SpecificUser identities):" -ForegroundColor Yellow
        $SkippedAppPools | Format-Table -AutoSize
    }

    Write-Host "`nFinal IIS service status:" -ForegroundColor Yellow
    Get-Service -Name $IISServiceName | Select-Object Name, DisplayName, Status | Format-Table -AutoSize
}
finally {
    # Do not retain a plaintext password longer than necessary.
    $PlainTextPassword = $null
}

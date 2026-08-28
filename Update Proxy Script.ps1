#requires -Version 5.1
<#+
.SYNOPSIS
    Stops IIS and two Windows services, pauses, prompts for credentials, updates IIS app pools
    and service logon passwords, pauses again, starts services and IIS, then reports final status.

.DESCRIPTION
    Required sequence:
      1. Stops AuditService, SubmitFormManager, and IIS; confirms each is stopped.
      2. Prompts: "Press Enter to continue..."
      3. Prompts for the service-account username and the new password.
      4. Updates matching IIS app-pool identity passwords and both Windows-service logon passwords.
      5. Prompts: "Press Enter to continue..."
      6. Starts AuditService and SubmitFormManager.
      7. Starts IIS (WAS, then W3SVC) and restores pools that were running before maintenance.
      8. Waits one minute and reports all IIS app-pool and managed-service statuses.

    IIS app pools excluded from password updates:
      - .NET v4.5
      - .NET v4.5 Classic
      - DefaultAppPool

    -WhatIf is simulation only. It does not stop/start anything, pause, make a backup, or change passwords.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string[]]$ExcludeAppPools = @(
        '.NET v4.5',
        '.NET v4.5 Classic',
        'DefaultAppPool'
    ),

    [string[]]$ManagedServiceNames = @(
        'AuditService',
        'SubmitFormManager'
    ),

    [ValidateRange(0, 3600)]
    [int]$PostStartWaitSeconds = 60,

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

function Get-WindowsServiceInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = $Name.Replace("'", "''")
    $service = Get-WmiObject -Class Win32_Service -Filter "Name='$escapedName'"

    if ($null -eq $service) {
        throw "Windows service '$Name' was not found."
    }

    return $service
}

function Set-WindowsServicePassword {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedUserName,

        [Parameter(Mandatory = $true)]
        [string]$Password
    )

    $service = Get-WindowsServiceInfo -Name $Name

    if ($service.StartName -ine $ExpectedUserName) {
        throw "Service '$Name' is configured to run as '$($service.StartName)', not '$ExpectedUserName'. Password was not changed."
    }

    # Win32_Service.Change: only StartName and StartPassword are provided; all other values are unchanged.
    $result = $service.Change(
        $null, $null, $null, $null, $null, $null,
        $ExpectedUserName, $Password,
        $null, $null, $null
    )

    if ($result.ReturnValue -ne 0) {
        throw "Could not update the logon password for service '$Name'. Win32_Service.Change returned code $($result.ReturnValue)."
    }
}

function Show-StopConfirmation {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ServiceNames
    )

    Write-Host ''
    Write-Host 'Stop-status confirmation:' -ForegroundColor Cyan

    $items = @()
    foreach ($serviceName in $ServiceNames + @('W3SVC', 'WAS')) {
        $service = Get-Service -Name $serviceName
        $items += [PSCustomObject]@{
            Service = $service.Name
            Status  = $service.Status
        }
    }

    $items | Format-Table -AutoSize

    $notStopped = @($items | Where-Object Status -ne 'Stopped')
    if ($notStopped.Count -gt 0) {
        throw "One or more required services did not stop: $($notStopped.Service -join ', ')."
    }

    Write-Host 'Confirmed: AuditService, SubmitFormManager, W3SVC, and WAS are stopped.' -ForegroundColor Green
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
    Write-Host ("App-pool summary: Started={0}; Stopped={1}; Other/Unavailable={2}" -f `
        @($status | Where-Object State -eq 'Started').Count, `
        @($status | Where-Object State -eq 'Stopped').Count, `
        @($status | Where-Object { $_.State -notin @('Started', 'Stopped') }).Count) -ForegroundColor Cyan
}

function Show-ManagedServiceStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ServiceNames
    )

    Write-Host ''
    Write-Host 'Final managed-service status:' -ForegroundColor Cyan

    $status = foreach ($serviceName in $ServiceNames) {
        $serviceController = Get-Service -Name $serviceName
        $serviceInfo = Get-WindowsServiceInfo -Name $serviceName

        [PSCustomObject]@{
            Name        = $serviceController.Name
            DisplayName = $serviceController.DisplayName
            Status      = $serviceController.Status
            StartName   = $serviceInfo.StartName
        }
    }

    $status | Format-Table -AutoSize
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated Windows PowerShell session (Run as Administrator).'
}

if ($ManagedServiceNames.Count -ne 2 -or
    $ManagedServiceNames -notcontains 'AuditService' -or
    $ManagedServiceNames -notcontains 'SubmitFormManager') {
    throw "ManagedServiceNames must include exactly 'AuditService' and 'SubmitFormManager'."
}

try {
    Import-Module WebAdministration -ErrorAction Stop
}
catch {
    throw "Could not load the WebAdministration module. Verify IIS Management Scripts and Tools is installed. Original error: $($_.Exception.Message)"
}

$applicationHostConfig = Join-Path $env:WINDIR 'System32\inetsrv\config\applicationHost.config'
if (-not (Test-Path -LiteralPath $applicationHostConfig)) {
    throw "IIS configuration was not found at: $applicationHostConfig"
}

$runningPoolsBeforeStop = @(
    Get-ChildItem IIS:\AppPools | Where-Object {
        (Get-WebAppPoolState -Name $_.Name).Value -eq 'Started'
    } | Select-Object -ExpandProperty Name
)

$wasRunningBeforeStop = (Get-Service -Name WAS).Status -eq 'Running'
$w3svcRunningBeforeStop = (Get-Service -Name W3SVC).Status -eq 'Running'

if ($WhatIfPreference) {
    Write-Host ''
    Write-Host 'WHATIF MODE: The script will not stop IIS, stop services, prompt at either pause, update passwords, create a backup, or start anything.' -ForegroundColor Yellow
    Write-Host 'Run without -WhatIf during the maintenance window to perform the actual sequence.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'What the actual run will do, in order:' -ForegroundColor Cyan
    Write-Host '  1. Stop AuditService and SubmitFormManager.'
    Write-Host '  2. Stop IIS (W3SVC, then WAS) and confirm all four services are stopped.'
    Write-Host '  3. Pause for Enter.'
    Write-Host '  4. Prompt for username and new password.'
    Write-Host '  5. Update matching IIS app pools and both Windows-service logon passwords.'
    Write-Host '  6. Pause for Enter.'
    Write-Host '  7. Start AuditService and SubmitFormManager.'
    Write-Host '  8. Start IIS (WAS, then W3SVC), wait 60 seconds, and show status.'
    return
}

$iisStopped = $false
$managedServicesStopped = $false
$plainTextPassword = $null

try {
    # Step 1: Stop the two application services first.
    if ($PSCmdlet.ShouldProcess(($ManagedServiceNames -join ', '), 'Stop application services')) {
        Write-Host ''
        Write-Host 'Stopping AuditService and SubmitFormManager...' -ForegroundColor Yellow

        foreach ($serviceName in $ManagedServiceNames) {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            if ($service.Status -ne 'Stopped') {
                Stop-Service -Name $serviceName -Force
                Wait-ServiceStatus -Name $serviceName -DesiredStatus Stopped
            }
        }

        $managedServicesStopped = $true
        Write-Host 'AuditService and SubmitFormManager are stopped.' -ForegroundColor Green
    }

    # Step 1: Stop IIS after the application services are stopped.
    if ($PSCmdlet.ShouldProcess('IIS services (W3SVC and WAS)', 'Stop IIS')) {
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
        Write-Host 'IIS services are stopped.' -ForegroundColor Green
    }

    # Step 1 confirmation, then Step 2 pause.
    Show-StopConfirmation -ServiceNames $ManagedServiceNames
    Write-Host ''
    Write-Host 'ALL REQUESTED SERVICES AND IIS ARE STOPPED. Press Enter to continue...' -ForegroundColor Yellow
    [void](Read-Host)

    # Step 3: Collect credentials only after the stop-and-confirmation pause.
    $UserName = Read-Host 'Enter the IIS and Windows-service identity username (example: DOMAIN\svc_iis)'
    if ([string]::IsNullOrWhiteSpace($UserName)) {
        throw 'A username is required.'
    }

    $NewPassword = Read-Host 'Enter the new password' -AsSecureString
    if ($null -eq $NewPassword -or $NewPassword.Length -eq 0) {
        throw 'A non-empty password is required.'
    }

    $targetPools = @(
        Get-ChildItem IIS:\AppPools | Where-Object {
            $_.Name -notin $ExcludeAppPools -and
            $_.processModel.identityType -eq 'SpecificUser' -and
            $_.processModel.userName -ieq $UserName
        }
    )

    if ($targetPools.Count -eq 0) {
        throw "No non-excluded application pools using '$UserName' were found. No passwords were changed."
    }

    foreach ($serviceName in $ManagedServiceNames) {
        $serviceInfo = Get-WindowsServiceInfo -Name $serviceName
        if ($serviceInfo.StartName -ine $UserName) {
            throw "Service '$serviceName' runs as '$($serviceInfo.StartName)', not '$UserName'. No passwords were changed."
        }
    }

    Write-Host ''
    Write-Host "Matching IIS application pools for '$UserName':" -ForegroundColor Cyan
    $targetPools | ForEach-Object { Write-Host "  - $($_.Name)" }

    Write-Host ''
    Write-Host "Confirmed service logon account for AuditService and SubmitFormManager: $UserName" -ForegroundColor Cyan

    $plainTextPassword = ConvertTo-PlainText -SecureString $NewPassword

    # Step 4: Back up IIS configuration, then update IIS and Windows-service passwords.
    if (-not $SkipConfigBackup) {
        $backupDirectory = Join-Path (Split-Path -Parent $applicationHostConfig) 'PasswordUpdateBackups'
        if (-not (Test-Path -LiteralPath $backupDirectory)) {
            New-Item -Path $backupDirectory -ItemType Directory -Force | Out-Null
        }

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupFile = Join-Path $backupDirectory "applicationHost.config.$timestamp.bak"
        Copy-Item -LiteralPath $applicationHostConfig -Destination $backupFile -Force
        Write-Host "Created IIS configuration backup: $backupFile" -ForegroundColor Cyan
    }

    foreach ($pool in $targetPools) {
        $poolPath = "IIS:\AppPools\$($pool.Name)"
        Set-ItemProperty -Path $poolPath -Name 'processModel.password' -Value $plainTextPassword
        Write-Host "Updated IIS app-pool password: $($pool.Name)" -ForegroundColor Green
    }

    foreach ($serviceName in $ManagedServiceNames) {
        Set-WindowsServicePassword -Name $serviceName -ExpectedUserName $UserName -Password $plainTextPassword
        Write-Host "Updated Windows-service password: $serviceName" -ForegroundColor Green
    }

    # Step 5 pause after all password updates but before anything is started.
    Write-Host ''
    Write-Host 'PASSWORD UPDATES COMPLETED. Press Enter to start AuditService and SubmitFormManager, then IIS...' -ForegroundColor Yellow
    [void](Read-Host)
}
finally {
    $plainTextPassword = $null

    # Steps 6 and 7: start the two services first, then IIS.
    if ($managedServicesStopped) {
        Write-Host ''
        Write-Host 'Starting AuditService and SubmitFormManager...' -ForegroundColor Yellow

        foreach ($serviceName in $ManagedServiceNames) {
            try {
                $service = Get-Service -Name $serviceName
                if ($service.Status -ne 'Running') {
                    Start-Service -Name $serviceName
                    Wait-ServiceStatus -Name $serviceName -DesiredStatus Running
                }
                Write-Host "Started: $serviceName" -ForegroundColor Green
            }
            catch {
                Write-Warning "Could not start service '$serviceName': $($_.Exception.Message)"
            }
        }
    }

    if ($iisStopped) {
        Write-Host ''
        Write-Host 'Starting IIS services...' -ForegroundColor Yellow

        try {
            $was = Get-Service -Name WAS
            if ($wasRunningBeforeStop -and $was.Status -ne 'Running') {
                Start-Service -Name WAS
                Wait-ServiceStatus -Name WAS -DesiredStatus Running
            }

            $w3svc = Get-Service -Name W3SVC
            if ($w3svcRunningBeforeStop -and $w3svc.Status -ne 'Running') {
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
        }
    }
}

# Step 8: Wait after service/IIS startup, then report final states.
Write-Host ''
Write-Host "Waiting $PostStartWaitSeconds seconds before collecting final status..." -ForegroundColor Yellow
Start-Sleep -Seconds $PostStartWaitSeconds

Show-AppPoolStatus
Show-ManagedServiceStatus -ServiceNames $ManagedServiceNames

Write-Host ''
Write-Host 'Completed.' -ForegroundColor Green

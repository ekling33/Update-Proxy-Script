#requires -Version 5.1
<#+
.SYNOPSIS
    Remotely updates Windows service and IIS application-pool credentials on a target server.

.DESCRIPTION
    Prompts for a target server, service account, and service-account password. Using the current
    Windows identity (no credential prompt), it connects over PowerShell remoting and performs:

      1. Stop IIS (W3SVC).
      2. Stop AuditService and SubmitFormManager.
      3. Update the logon account and password for both services.
      4. Update IIS application pools already configured with a SpecificUser identity.
      5. Start both services.
      6. Start IIS (W3SVC).
      7. Start updated IIS application pools and return service/pool start results.

    Requirements:
      - Run this script from an elevated Windows PowerShell 5.1 session.
      - PowerShell remoting/WinRM must be enabled and reachable on the target server.
      - Your current Windows identity must be an administrator on the target server.
      - IIS and the WebAdministration module must be installed on the target server.
#>

[CmdletBinding()]
param(
    [int]$StopTimeoutSeconds = 120,
    [int]$StartTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated Windows PowerShell 5.1 session as an administrator.'
}

$ComputerName = Read-Host -Prompt 'Enter the target server name (for example, APP-SERVER-01 or APP-SERVER-01.contoso.com)'
if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    throw 'A target server name is required.'
}

$ServiceAccount = Read-Host -Prompt 'Enter the service account (for example, PROD\serviceaccount)'
if ([string]::IsNullOrWhiteSpace($ServiceAccount)) {
    throw 'A service account is required.'
}

$SecurePassword = Read-Host -Prompt "Enter the password for $ServiceAccount" -AsSecureString

$RemoteScript = {
    param(
        [string]$ServiceAccount,
        [System.Security.SecureString]$SecurePassword,
        [int]$StopTimeoutSeconds,
        [int]$StartTimeoutSeconds
    )

    $ErrorActionPreference = 'Stop'
    $TargetServices = @('AuditService', 'SubmitFormManager')
    $IISServiceName = 'W3SVC'

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

    function New-Result {
        param(
            [string]$Item,
            [string]$Type,
            [string]$Action,
            [string]$FinalStatus,
            [string]$Detail
        )

        [pscustomobject]@{
            Server      = $env:COMPUTERNAME
            Item        = $Item
            Type        = $Type
            Action      = $Action
            FinalStatus = $FinalStatus
            Detail      = $Detail
        }
    }

    $PlainTextPassword = $null

    try {
        Import-Module WebAdministration -ErrorAction Stop

        $missingServices = @($TargetServices | Where-Object {
            -not (Get-Service -Name $_ -ErrorAction SilentlyContinue)
        })
        if ($missingServices.Count -gt 0) {
            throw "Required service(s) not found: $($missingServices -join ', '). No changes were made."
        }

        if (-not (Get-Service -Name $IISServiceName -ErrorAction SilentlyContinue)) {
            throw "IIS service '$IISServiceName' was not found. Verify IIS is installed. No changes were made."
        }

        $PlainTextPassword = Convert-SecureStringToPlainText -SecureString $SecurePassword

        Write-Host "[$env:COMPUTERNAME] Stopping IIS service ($IISServiceName)..." -ForegroundColor Cyan
        $iisService = Get-Service -Name $IISServiceName -ErrorAction Stop
        if ($iisService.Status -ne 'Stopped') {
            Stop-Service -Name $IISServiceName -Force -ErrorAction Stop
            Wait-ForServiceStatus -Name $IISServiceName -DesiredStatus Stopped -TimeoutSeconds $StopTimeoutSeconds | Out-Null
        }

        foreach ($ServiceName in $TargetServices) {
            Write-Host "[$env:COMPUTERNAME] Stopping $ServiceName..." -ForegroundColor Cyan
            $service = Get-Service -Name $ServiceName -ErrorAction Stop
            if ($service.Status -ne 'Stopped') {
                Stop-Service -Name $ServiceName -Force -ErrorAction Stop
                Wait-ForServiceStatus -Name $ServiceName -DesiredStatus Stopped -TimeoutSeconds $StopTimeoutSeconds | Out-Null
            }
        }

        foreach ($ServiceName in $TargetServices) {
            Write-Host "[$env:COMPUTERNAME] Updating credentials for $ServiceName..." -ForegroundColor Cyan
            $scOutput = & "$env:SystemRoot\System32\sc.exe" config $ServiceName obj= $ServiceAccount password= $PlainTextPassword 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to update service '$ServiceName'. sc.exe output: $($scOutput -join ' ')"
            }
        }

        $updatedAppPools = @()
        $skippedAppPoolResults = @()

        foreach ($appPool in Get-ChildItem -Path IIS:\AppPools) {
            $poolName = $appPool.Name
            $identityType = [string]$appPool.processModel.identityType

            if ($identityType -eq 'SpecificUser') {
                Write-Host "[$env:COMPUTERNAME] Updating application-pool credentials: $poolName" -ForegroundColor Cyan
                Set-ItemProperty -Path "IIS:\AppPools\$poolName" -Name processModel -Value @{
                    identityType = 'SpecificUser'
                    userName     = $ServiceAccount
                    password     = $PlainTextPassword
                } -ErrorAction Stop
                $updatedAppPools += $poolName
            }
            else {
                $skippedAppPoolResults += New-Result -Item $poolName -Type 'IIS Application Pool' -Action 'Skipped' -FinalStatus $appPool.State.ToString() -Detail "Identity type is $identityType; only SpecificUser pools are changed."
            }
        }

        $serviceStartResults = @()
        foreach ($ServiceName in $TargetServices) {
            try {
                Write-Host "[$env:COMPUTERNAME] Starting $ServiceName..." -ForegroundColor Cyan
                $service = Get-Service -Name $ServiceName -ErrorAction Stop
                if ($service.Status -ne 'Running') {
                    Start-Service -Name $ServiceName -ErrorAction Stop
                    Wait-ForServiceStatus -Name $ServiceName -DesiredStatus Running -TimeoutSeconds $StartTimeoutSeconds | Out-Null
                }
                $finalStatus = (Get-Service -Name $ServiceName).Status.ToString()
                $serviceStartResults += New-Result -Item $ServiceName -Type 'Windows Service' -Action 'Started' -FinalStatus $finalStatus -Detail "Logon account configured as $ServiceAccount."
            }
            catch {
                $finalStatus = 'Unknown'
                try { $finalStatus = (Get-Service -Name $ServiceName -ErrorAction Stop).Status.ToString() } catch { }
                $serviceStartResults += New-Result -Item $ServiceName -Type 'Windows Service' -Action 'Start failed' -FinalStatus $finalStatus -Detail $_.Exception.Message
            }
        }

        $iisStartResult = $null
        try {
            Write-Host "[$env:COMPUTERNAME] Starting IIS service ($IISServiceName)..." -ForegroundColor Cyan
            $iisService = Get-Service -Name $IISServiceName -ErrorAction Stop
            if ($iisService.Status -ne 'Running') {
                Start-Service -Name $IISServiceName -ErrorAction Stop
                Wait-ForServiceStatus -Name $IISServiceName -DesiredStatus Running -TimeoutSeconds $StartTimeoutSeconds | Out-Null
            }
            $iisStartResult = New-Result -Item $IISServiceName -Type 'Windows Service' -Action 'Started' -FinalStatus (Get-Service -Name $IISServiceName).Status.ToString() -Detail 'IIS web service started successfully.'
        }
        catch {
            $finalStatus = 'Unknown'
            try { $finalStatus = (Get-Service -Name $IISServiceName -ErrorAction Stop).Status.ToString() } catch { }
            $iisStartResult = New-Result -Item $IISServiceName -Type 'Windows Service' -Action 'Start failed' -FinalStatus $finalStatus -Detail $_.Exception.Message
        }

        $appPoolStartResults = @()
        foreach ($poolName in $updatedAppPools) {
            try {
                Write-Host "[$env:COMPUTERNAME] Starting application pool $poolName..." -ForegroundColor Cyan
                $pool = Get-Item -Path "IIS:\AppPools\$poolName" -ErrorAction Stop
                if ($pool.State -ne 'Started') {
                    Start-WebAppPool -Name $poolName -ErrorAction Stop
                }

                Start-Sleep -Seconds 2
                $finalPool = Get-Item -Path "IIS:\AppPools\$poolName" -ErrorAction Stop
                $appPoolStartResults += New-Result -Item $poolName -Type 'IIS Application Pool' -Action 'Started' -FinalStatus $finalPool.State.ToString() -Detail "Identity configured as $ServiceAccount."
            }
            catch {
                $finalStatus = 'Unknown'
                try { $finalStatus = (Get-Item -Path "IIS:\AppPools\$poolName" -ErrorAction Stop).State.ToString() } catch { }
                $appPoolStartResults += New-Result -Item $poolName -Type 'IIS Application Pool' -Action 'Start failed' -FinalStatus $finalStatus -Detail $_.Exception.Message
            }
        }

        # Return structured objects to the calling session for final reporting.
        $serviceStartResults
        $iisStartResult
        $appPoolStartResults
        $skippedAppPoolResults
    }
    finally {
        $PlainTextPassword = $null
    }
}

try {
    Write-Host "Testing PowerShell remoting connection to $ComputerName..." -ForegroundColor Cyan
    Test-WSMan -ComputerName $ComputerName -ErrorAction Stop | Out-Null

    Write-Host "Connected. Running update on $ComputerName using your current Windows credentials..." -ForegroundColor Green
    $results = Invoke-Command -ComputerName $ComputerName -ScriptBlock $RemoteScript -ArgumentList $ServiceAccount, $SecurePassword, $StopTimeoutSeconds, $StartTimeoutSeconds -ErrorAction Stop

    $serviceResults = @($results | Where-Object { $_.Type -eq 'Windows Service' -and $_.Item -in @('AuditService', 'SubmitFormManager') })
    $iisResult = @($results | Where-Object { $_.Type -eq 'Windows Service' -and $_.Item -eq 'W3SVC' })
    $appPoolResults = @($results | Where-Object { $_.Type -eq 'IIS Application Pool' -and $_.Action -ne 'Skipped' })
    $skippedPoolResults = @($results | Where-Object { $_.Type -eq 'IIS Application Pool' -and $_.Action -eq 'Skipped' })

    Write-Host "`nService start results:" -ForegroundColor Yellow
    $serviceResults | Format-Table Server, Item, Action, FinalStatus, Detail -AutoSize

    Write-Host "`nIIS service start result:" -ForegroundColor Yellow
    $iisResult | Format-Table Server, Item, Action, FinalStatus, Detail -AutoSize

    Write-Host "`nIIS application-pool start results (SpecificUser pools updated):" -ForegroundColor Yellow
    if ($appPoolResults.Count -gt 0) {
        $appPoolResults | Format-Table Server, Item, Action, FinalStatus, Detail -AutoSize
    }
    else {
        Write-Host 'No application pools using SpecificUser were found to update and start.' -ForegroundColor DarkYellow
    }

    if ($skippedPoolResults.Count -gt 0) {
        Write-Host "`nApplication pools skipped (non-SpecificUser identities):" -ForegroundColor Yellow
        $skippedPoolResults | Format-Table Server, Item, FinalStatus, Detail -AutoSize
    }
}
catch {
    throw "Remote update failed for '$ComputerName': $($_.Exception.Message)"
}

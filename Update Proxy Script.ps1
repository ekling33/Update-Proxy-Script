#requires -Version 5.1
<#+
.SYNOPSIS
    Remotely updates only the passwords for two Windows services and IIS application pools.

.DESCRIPTION
    Prompts for a target server and one new password. It uses the service account already configured
    on each target service and IIS application pool; it does not change any usernames or identities.

    Using the current Windows identity (no admin credential prompt), the script performs:
      1. Stop IIS (W3SVC).
      2. Stop AuditService and SubmitFormManager.
      3. Read the existing configured service account for each service and update only its password.
      4. Read each IIS app pool. For pools using SpecificUser, retain the current username and update
         only its password. Other pool identity types are skipped.
      5. Start the two services.
      6. Start IIS (W3SVC).
      7. Start updated IIS application pools and return final start/status results.

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

$SecurePassword = Read-Host -Prompt 'Enter the new password to apply to existing service and IIS application-pool accounts' -AsSecureString

$RemoteScript = {
    param(
        [System.Security.SecureString]$SecurePassword,
        [int]$StopTimeoutSeconds,
        [int]$StartTimeoutSeconds
    )

    $ErrorActionPreference = 'Stop'
    $TargetServices = @('AuditService', 'SubmitFormManager')
    $IISServiceName = 'W3SVC'
    $PlainTextPassword = $null

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
            [string]$Account,
            [string]$Detail
        )

        [pscustomobject]@{
            Server      = $env:COMPUTERNAME
            Item        = $Item
            Type        = $Type
            Action      = $Action
            FinalStatus = $FinalStatus
            Account     = $Account
            Detail      = $Detail
        }
    }

    try {
        Import-Module WebAdministration -ErrorAction Stop

        # Confirm prerequisites before changing or stopping anything.
        $missingServices = @($TargetServices | Where-Object {
            -not (Get-Service -Name $_ -ErrorAction SilentlyContinue)
        })
        if ($missingServices.Count -gt 0) {
            throw "Required service(s) not found: $($missingServices -join ', '). No changes were made."
        }

        if (-not (Get-Service -Name $IISServiceName -ErrorAction SilentlyContinue)) {
            throw "IIS service '$IISServiceName' was not found. Verify IIS is installed. No changes were made."
        }

        # Read the existing service accounts before stopping services or modifying configuration.
        $serviceAccounts = @{}
        foreach ($ServiceName in $TargetServices) {
            $serviceConfig = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
            $startName = [string]$serviceConfig.StartName

            if ([string]::IsNullOrWhiteSpace($startName)) {
                throw "Could not determine the configured logon account for service '$ServiceName'. No changes were made."
            }

            # Password updates are applicable to user-managed service accounts, not built-in service identities.
            if ($startName -match '^(LocalSystem|NT AUTHORITY\\(LocalService|NetworkService))$') {
                throw "Service '$ServiceName' uses built-in account '$startName'. A password cannot be updated for this identity. No changes were made."
            }

            $serviceAccounts[$ServiceName] = $startName
        }

        # Snapshot the IIS pools that use SpecificUser. Their usernames will remain unchanged.
        $specificUserPools = @()
        $skippedAppPoolResults = @()
        foreach ($appPool in Get-ChildItem -Path IIS:\AppPools) {
            $poolName = $appPool.Name
            $identityType = [string]$appPool.processModel.identityType

            if ($identityType -eq 'SpecificUser') {
                $userName = [string]$appPool.processModel.userName
                if ([string]::IsNullOrWhiteSpace($userName)) {
                    throw "Application pool '$poolName' is configured as SpecificUser but has no username. No changes were made."
                }

                $specificUserPools += [pscustomobject]@{
                    Name     = $poolName
                    UserName = $userName
                }
            }
            else {
                $skippedAppPoolResults += New-Result -Item $poolName -Type 'IIS Application Pool' -Action 'Skipped' -FinalStatus $appPool.State.ToString() -Account '' -Detail "Identity type is $identityType; no password exists to update."
            }
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

        # sc.exe needs obj= and password= together. Passing the current StartName preserves the account;
        # only the stored password is changed.
        foreach ($ServiceName in $TargetServices) {
            $existingAccount = $serviceAccounts[$ServiceName]
            Write-Host "[$env:COMPUTERNAME] Updating password for $ServiceName (account remains $existingAccount)..." -ForegroundColor Cyan
            $scOutput = & "$env:SystemRoot\System32\sc.exe" config $ServiceName obj= $existingAccount password= $PlainTextPassword 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to update password for service '$ServiceName'. sc.exe output: $($scOutput -join ' ')"
            }
        }

        # Update only the password property of each existing SpecificUser application pool.
        foreach ($pool in $specificUserPools) {
            Write-Host "[$env:COMPUTERNAME] Updating password for application pool $($pool.Name) (account remains $($pool.UserName))..." -ForegroundColor Cyan
            Set-ItemProperty -Path "IIS:\AppPools\$($pool.Name)" -Name processModel.password -Value $PlainTextPassword -ErrorAction Stop
        }

        $serviceStartResults = @()
        foreach ($ServiceName in $TargetServices) {
            $existingAccount = $serviceAccounts[$ServiceName]
            try {
                Write-Host "[$env:COMPUTERNAME] Starting $ServiceName..." -ForegroundColor Cyan
                $service = Get-Service -Name $ServiceName -ErrorAction Stop
                if ($service.Status -ne 'Running') {
                    Start-Service -Name $ServiceName -ErrorAction Stop
                    Wait-ForServiceStatus -Name $ServiceName -DesiredStatus Running -TimeoutSeconds $StartTimeoutSeconds | Out-Null
                }
                $finalStatus = (Get-Service -Name $ServiceName).Status.ToString()
                $serviceStartResults += New-Result -Item $ServiceName -Type 'Windows Service' -Action 'Started' -FinalStatus $finalStatus -Account $existingAccount -Detail 'Existing account retained; password updated.'
            }
            catch {
                $finalStatus = 'Unknown'
                try { $finalStatus = (Get-Service -Name $ServiceName -ErrorAction Stop).Status.ToString() } catch { }
                $serviceStartResults += New-Result -Item $ServiceName -Type 'Windows Service' -Action 'Start failed' -FinalStatus $finalStatus -Account $existingAccount -Detail $_.Exception.Message
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
            $iisStartResult = New-Result -Item $IISServiceName -Type 'Windows Service' -Action 'Started' -FinalStatus (Get-Service -Name $IISServiceName).Status.ToString() -Account '' -Detail 'IIS web service started successfully.'
        }
        catch {
            $finalStatus = 'Unknown'
            try { $finalStatus = (Get-Service -Name $IISServiceName -ErrorAction Stop).Status.ToString() } catch { }
            $iisStartResult = New-Result -Item $IISServiceName -Type 'Windows Service' -Action 'Start failed' -FinalStatus $finalStatus -Account '' -Detail $_.Exception.Message
        }

        $appPoolStartResults = @()
        foreach ($pool in $specificUserPools) {
            try {
                Write-Host "[$env:COMPUTERNAME] Starting application pool $($pool.Name)..." -ForegroundColor Cyan
                $appPool = Get-Item -Path "IIS:\AppPools\$($pool.Name)" -ErrorAction Stop
                if ($appPool.State -ne 'Started') {
                    Start-WebAppPool -Name $pool.Name -ErrorAction Stop
                }

                Start-Sleep -Seconds 2
                $finalPool = Get-Item -Path "IIS:\AppPools\$($pool.Name)" -ErrorAction Stop
                $appPoolStartResults += New-Result -Item $pool.Name -Type 'IIS Application Pool' -Action 'Started' -FinalStatus $finalPool.State.ToString() -Account $pool.UserName -Detail 'Existing identity retained; password updated.'
            }
            catch {
                $finalStatus = 'Unknown'
                try { $finalStatus = (Get-Item -Path "IIS:\AppPools\$($pool.Name)" -ErrorAction Stop).State.ToString() } catch { }
                $appPoolStartResults += New-Result -Item $pool.Name -Type 'IIS Application Pool' -Action 'Start failed' -FinalStatus $finalStatus -Account $pool.UserName -Detail $_.Exception.Message
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

    Write-Host "Connected. Updating passwords on $ComputerName using your current Windows credentials..." -ForegroundColor Green
    $results = Invoke-Command -ComputerName $ComputerName -ScriptBlock $RemoteScript -ArgumentList $SecurePassword, $StopTimeoutSeconds, $StartTimeoutSeconds -ErrorAction Stop

    $serviceResults = @($results | Where-Object { $_.Type -eq 'Windows Service' -and $_.Item -in @('AuditService', 'SubmitFormManager') })
    $iisResult = @($results | Where-Object { $_.Type -eq 'Windows Service' -and $_.Item -eq 'W3SVC' })
    $appPoolResults = @($results | Where-Object { $_.Type -eq 'IIS Application Pool' -and $_.Action -ne 'Skipped' })
    $skippedPoolResults = @($results | Where-Object { $_.Type -eq 'IIS Application Pool' -and $_.Action -eq 'Skipped' })

    Write-Host "`nService start results:" -ForegroundColor Yellow
    $serviceResults | Format-Table Server, Item, Action, FinalStatus, Account, Detail -AutoSize

    Write-Host "`nIIS service start result:" -ForegroundColor Yellow
    $iisResult | Format-Table Server, Item, Action, FinalStatus, Detail -AutoSize

    Write-Host "`nIIS application-pool start results (SpecificUser pools with passwords updated):" -ForegroundColor Yellow
    if ($appPoolResults.Count -gt 0) {
        $appPoolResults | Format-Table Server, Item, Action, FinalStatus, Account, Detail -AutoSize
    }
    else {
        Write-Host 'No application pools using SpecificUser were found to update and start.' -ForegroundColor DarkYellow
    }

    if ($skippedPoolResults.Count -gt 0) {
        Write-Host "`nApplication pools skipped (identities without a managed password):" -ForegroundColor Yellow
        $skippedPoolResults | Format-Table Server, Item, FinalStatus, Detail -AutoSize
    }
}
catch {
    throw "Remote password update failed for '$ComputerName': $($_.Exception.Message)"
}

#requires -Version 5.1
<#+
.SYNOPSIS
    Remotely updates the RabbitMQ Windows service logon password and verifies startup.

.DESCRIPTION
    Prompts for a target server and the password for the RabbitMQ service account.
    The script discovers the RabbitMQ Windows service on the remote server, stops it,
    updates its existing Log On As account with the new password, starts it, waits one
    minute, and reports the service status.

.NOTES
    Run from an elevated Windows PowerShell 5.1 session with administrative rights on
    the target server. PowerShell remoting (WinRM) must be enabled and reachable.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-TargetServer {
    do {
        $server = Read-Host 'Enter the target server hostname'
        if ([string]::IsNullOrWhiteSpace($server)) {
            Write-Warning 'A target server hostname is required.'
        }
    } until (-not [string]::IsNullOrWhiteSpace($server))

    return $server.Trim()
}

function Get-RabbitMQService {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )

    $services = Get-CimInstance -ClassName Win32_Service -ComputerName $ComputerName |
        Where-Object {
            $_.Name -match 'rabbitmq' -or
            $_.DisplayName -match 'rabbitmq'
        }

    if (-not $services) {
        throw "No RabbitMQ Windows service was found on '$ComputerName'."
    }

    if (@($services).Count -gt 1) {
        $details = ($services | ForEach-Object { "Name='$($_.Name)', DisplayName='$($_.DisplayName)'" }) -join '; '
        throw "More than one RabbitMQ-related service was found on '$ComputerName': $details"
    }

    return @($services)[0]
}

$targetServer = Read-TargetServer

try {
    Write-Host "Validating access to $targetServer..." -ForegroundColor Cyan
    Test-WSMan -ComputerName $targetServer -ErrorAction Stop | Out-Null

    $rabbitService = Get-RabbitMQService -ComputerName $targetServer
    $serviceName = $rabbitService.Name
    $serviceAccount = $rabbitService.StartName

    if ([string]::IsNullOrWhiteSpace($serviceAccount) -or
        $serviceAccount -match '^(LocalSystem|LocalService|NetworkService)$') {
        throw "RabbitMQ service '$serviceName' on '$targetServer' is configured to run as '$serviceAccount'. A password cannot be updated for a built-in service account."
    }

    Write-Host "RabbitMQ service found: $($rabbitService.DisplayName) ($serviceName)" -ForegroundColor Green
    Write-Host "Configured service account: $serviceAccount" -ForegroundColor Green

    $remoteScript = {
        param(
            [string]$ServiceName,
            [string]$ServiceAccount,
            [securestring]$NewPassword
        )

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'"
        if (-not $service) {
            throw "Service '$ServiceName' was not found."
        }

        if ($service.State -ne 'Stopped') {
            Write-Host "Stopping service '$ServiceName'..." -ForegroundColor Cyan
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            (Get-Service -Name $ServiceName).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromMinutes(2))
        }

        Write-Host "Updating the logon password for '$ServiceAccount'..." -ForegroundColor Cyan
        $changeResult = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{
            StartName     = $ServiceAccount
            StartPassword = $NewPassword
        }

        if ($changeResult.ReturnValue -ne 0) {
            throw "Win32_Service.Change failed with return value $($changeResult.ReturnValue)."
        }

        Write-Host "Starting service '$ServiceName'..." -ForegroundColor Cyan
        Start-Service -Name $ServiceName -ErrorAction Stop

        Write-Host 'Waiting 60 seconds before checking status...' -ForegroundColor Cyan
        Start-Sleep -Seconds 60

        $finalService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'"
        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            ServiceName  = $finalService.Name
            DisplayName  = $finalService.DisplayName
            Status       = $finalService.State
            StartMode    = $finalService.StartMode
            StartName    = $finalService.StartName
            ExitCode     = $finalService.ExitCode
            ProcessId    = $finalService.ProcessId
        }
    }

    $newPassword = Read-Host "Enter the new password for '$serviceAccount'" -AsSecureString
    if ($null -eq $newPassword) {
        throw 'No password was supplied.'
    }

    $result = Invoke-Command -ComputerName $targetServer -ScriptBlock $remoteScript -ArgumentList $serviceName, $serviceAccount, $newPassword -ErrorAction Stop

    Write-Host "`nRabbitMQ service status after one minute:" -ForegroundColor Cyan
    $result | Format-List ComputerName, ServiceName, DisplayName, Status, StartMode, StartName, ExitCode, ProcessId

    if ($result.Status -eq 'Running') {
        Write-Host "RabbitMQ is running on $targetServer." -ForegroundColor Green
    }
    else {
        Write-Warning "RabbitMQ is not running on $targetServer. Reported status: $($result.Status); ExitCode: $($result.ExitCode)."
    }
}
catch {
    Write-Error "RabbitMQ service account update failed on '$targetServer': $($_.Exception.Message)"
    exit 1
}

# Run this script in an elevated PowerShell session.
# Sequence:
# 1. Stop RabbitMQ service(s)
# 2. Prompt: Press Enter to Continue
# 3. Prompt for service account username and new password
# 4. Update RabbitMQ service credentials
# 5. Prompt: Press Enter to Continue
# 6. Start RabbitMQ service(s)
# 7. Wait 60 seconds and display final status

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw 'Run this script from an elevated PowerShell session (Run as Administrator).'
}

$services = Get-CimInstance Win32_Service -Filter "DisplayName LIKE '%RabbitMQ%'" |
    Sort-Object Name

if (-not $services) {
    throw "No services were found with a display name containing 'RabbitMQ'. Verify the RabbitMQ service display name and update the script filter if needed."
}

Write-Host "RabbitMQ service(s) found:" -ForegroundColor Cyan
$services | Select-Object Name, DisplayName, State, StartName | Format-Table -AutoSize

Write-Host "Stopping RabbitMQ service(s)..." -ForegroundColor Yellow
foreach ($service in $services) {
    if ($service.State -ne 'Stopped') {
        Stop-Service -Name $service.Name -Force
        (Get-Service -Name $service.Name).WaitForStatus('Stopped', [TimeSpan]::FromMinutes(2))
    }
}

Write-Host "`nRabbitMQ service(s) have been stopped." -ForegroundColor Green
Read-Host 'Press Enter to Continue'

$serviceAccount = Read-Host 'Enter the service account username (for example: DOMAIN\RabbitMQSvc or .\LocalAccount)'
if ([string]::IsNullOrWhiteSpace($serviceAccount)) {
    throw 'A service account username is required.'
}

$newPassword = Read-Host 'Enter the new service account password' -AsSecureString
if ($newPassword.Length -eq 0) {
    throw 'A password is required.'
}

$plainPassword = [System.Net.NetworkCredential]::new('', $newPassword).Password

try {
    Write-Host "`nUpdating the RabbitMQ service account and password..." -ForegroundColor Yellow
    foreach ($service in $services) {
        $result = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{
            StartName     = $serviceAccount
            StartPassword = $plainPassword
        }

        if ($result.ReturnValue -ne 0) {
            throw "Could not update '$($service.DisplayName)' ($($service.Name)). Win32_Service.Change returned code $($result.ReturnValue)."
        }
    }

    Write-Host "RabbitMQ service credentials have been updated for: $serviceAccount" -ForegroundColor Green
    Read-Host 'Press Enter to Continue'

    Write-Host "`nStarting RabbitMQ service(s)..." -ForegroundColor Yellow
    foreach ($service in $services) {
        Start-Service -Name $service.Name
    }

    Write-Host 'RabbitMQ service(s) started. Waiting 60 seconds before checking status...' -ForegroundColor Yellow
    Start-Sleep -Seconds 60

    Write-Host "`nFinal RabbitMQ service status:" -ForegroundColor Cyan
    Get-CimInstance Win32_Service -Filter "DisplayName LIKE '%RabbitMQ%'" |
        Sort-Object Name |
        Select-Object Name, DisplayName, State, StartMode, StartName, ProcessId |
        Format-Table -AutoSize
}
finally {
    $plainPassword = $null
}

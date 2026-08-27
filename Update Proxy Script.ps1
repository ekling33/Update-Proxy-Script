#requires -Version 5.1
<#+
.SYNOPSIS
    Updates a service-account password for Interact, RabbitMQ, and Blue Prism remotely.

.DESCRIPTION
    Expected files in the same directory as this script:
      - Interact.txt  : one Interact hostname (first nonblank, non-comment line)
      - RabbitMQ.txt  : one RabbitMQ hostname (first nonblank, non-comment line)
      - BluePrism.txt : one Blue Prism hostname per line

    Requirements:
      - Run this script in an elevated Windows PowerShell 5.1 session.
      - PowerShell remoting (WinRM) must be enabled and accessible on all target servers.
      - The account running this script must have administrative rights on every target.
      - The supplied service account must have required service-logon and IIS permissions.
      - IIS administration components must be installed on the Interact server.

    IMPORTANT:
      - The script prompts for the service account name and new password at runtime.
      - Confirm the actual Windows service names below. Display names and service names can differ.
      - The script intentionally pauses at the requested change-control points.
#>

[CmdletBinding()]
param(
    # The exact service name. Do not use the display name unless it is also the service name.
    [Parameter(Mandatory = $false)]
    [string]$RabbitMqServiceName = 'RabbitMQ',

    [Parameter(Mandatory = $false)]
    [string[]]$InteractServiceNames = @('AuditService', 'SubmitFormManager'),

    [Parameter(Mandatory = $false)]
    [string]$BluePrismServiceName = 'Blue Prism Server',

    # Requested start-service wording can differ from the actual Windows service name.
    # Change this if the service that must be started is not $BluePrismServiceName.
    [Parameter(Mandatory = $false)]
    [string]$BluePrismStartServiceName = 'Blue Prism Server',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 60)]
    [int]$PostStartWaitMinutes = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# These built-in IIS application pools are excluded from identity/password changes.
# They are still included in the final IIS app-pool status report and will be started if stopped.
$ExcludedIisAppPools = @(
    '.NET v4.5',
    '.NET v4.5 Classic',
    'DefaultAppPool'
)

function Get-HostNamesFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MinimumCount,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaximumCount
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required $Description file was not found: $Path"
    }

    $hosts = @(
        Get-Content -LiteralPath $Path | ForEach-Object { $_.Trim() } | Where-Object {
            $_ -and -not $_.StartsWith('#')
        } | Select-Object -Unique
    )

    if ($hosts.Count -lt $MinimumCount -or $hosts.Count -gt $MaximumCount) {
        throw "$Description must contain between $MinimumCount and $MaximumCount nonblank hostname(s). Found: $($hosts.Count). File: $Path"
    }

    return $hosts
}

function Confirm-Continue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Read-Host $Message | Out-Null
}

function Test-RemoteConnectivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ComputerName
    )

    foreach ($computer in $ComputerName) {
        Write-Host "Testing PowerShell remoting to $computer ..." -ForegroundColor Cyan
        try {
            Test-WSMan -ComputerName $computer -ErrorAction Stop | Out-Null
            Write-Host "  Connected: $computer" -ForegroundColor Green
        }
        catch {
            throw "Cannot connect to $computer through WinRM/PowerShell remoting. $($_.Exception.Message)"
        }
    }
}

function Stop-RemoteServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string[]]$ServiceName
    )

    Invoke-Command -ComputerName $ComputerName -ArgumentList (, $ServiceName) -ScriptBlock {
        param([string[]]$Names)

        foreach ($name in $Names) {
            $service = Get-Service -Name $name -ErrorAction Stop
            if ($service.Status -ne 'Stopped') {
                Stop-Service -Name $name -Force -ErrorAction Stop
                $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromMinutes(2))
            }

            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                ServiceName  = $name
                Status       = (Get-Service -Name $name).Status.ToString()
            }
        }
    }
}

function Start-RemoteServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string[]]$ServiceName
    )

    Invoke-Command -ComputerName $ComputerName -ArgumentList (, $ServiceName) -ScriptBlock {
        param([string[]]$Names)

        foreach ($name in $Names) {
            $service = Get-Service -Name $name -ErrorAction Stop
            if ($service.Status -ne 'Running') {
                Start-Service -Name $name -ErrorAction Stop
            }

            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                ServiceName  = $name
                Status       = (Get-Service -Name $name).Status.ToString()
            }
        }
    }
}

function Get-RemoteServiceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string[]]$ServiceName
    )

    Invoke-Command -ComputerName $ComputerName -ArgumentList (, $ServiceName) -ScriptBlock {
        param([string[]]$Names)

        foreach ($name in $Names) {
            $service = Get-Service -Name $name -ErrorAction Stop
            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                ServiceName  = $service.Name
                DisplayName  = $service.DisplayName
                Status       = $service.Status.ToString()
                StartType    = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$($service.Name.Replace("'", "''"))'" -ErrorAction Stop).StartMode
            }
        }
    }
}

function Set-RemoteServiceLogonPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string[]]$ServiceName,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$Password
    )

    Invoke-Command -ComputerName $ComputerName -ArgumentList (, $ServiceName), $UserName, $Password -ScriptBlock {
        param(
            [string[]]$Names,
            [string]$AccountName,
            [System.Security.SecureString]$SecurePassword
        )

        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        try {
            $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

            foreach ($name in $Names) {
                $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($name.Replace("'", "''"))'" -ErrorAction Stop
                $result = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{
                    StartName     = $AccountName
                    StartPassword = $plainPassword
                } -ErrorAction Stop

                if ($result.ReturnValue -ne 0) {
                    throw "Win32_Service.Change returned $($result.ReturnValue) for service '$name'."
                }

                [pscustomobject]@{
                    ComputerName = $env:COMPUTERNAME
                    ServiceName  = $name
                    StartName    = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$($name.Replace("'", "''"))'").StartName
                    Result       = 'Password updated'
                }
            }
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
            Remove-Variable -Name plainPassword -ErrorAction SilentlyContinue
        }
    }
}

function Stop-RemoteIis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )

    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        $was = Get-Service -Name 'WAS' -ErrorAction Stop
        if ($was.Status -ne 'Stopped') {
            Stop-Service -Name 'WAS' -Force -ErrorAction Stop
            $was.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromMinutes(2))
        }

        Get-Service -Name 'WAS', 'W3SVC' -ErrorAction SilentlyContinue | Select-Object @{
            Name = 'ComputerName'; Expression = { $env:COMPUTERNAME }
        }, Name, DisplayName, Status
    }
}

function Set-RemoteIisAppPoolPasswords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$Password,

        [Parameter(Mandatory = $true)]
        [string[]]$ExcludedAppPoolNames
    )

    Invoke-Command -ComputerName $ComputerName -ArgumentList $UserName, $Password, (, $ExcludedAppPoolNames) -ScriptBlock {
        param(
            [string]$AccountName,
            [System.Security.SecureString]$SecurePassword,
            [string[]]$ExcludedNames
        )

        Import-Module WebAdministration -ErrorAction Stop

        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        try {
            $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $appPools = @(Get-ChildItem -Path 'IIS:\AppPools' | Where-Object {
                $_.processModel.identityType -eq 'SpecificUser' -and $_.Name -notin $ExcludedNames
            })

            $skippedAppPools = @(Get-ChildItem -Path 'IIS:\AppPools' | Where-Object {
                $_.Name -in $ExcludedNames
            })

            foreach ($appPool in $skippedAppPools) {
                [pscustomobject]@{
                    ComputerName = $env:COMPUTERNAME
                    AppPool      = $appPool.Name
                    IdentityType = $appPool.processModel.identityType
                    UserName     = $appPool.processModel.userName
                    Result       = 'Skipped - excluded application pool'
                }
            }

            if ($appPools.Count -eq 0) {
                Write-Warning "No non-excluded IIS application pools using SpecificUser identity were found on $env:COMPUTERNAME."
            }

            foreach ($appPool in $appPools) {
                Set-ItemProperty -Path "IIS:\AppPools\$($appPool.Name)" -Name 'processModel.userName' -Value $AccountName -ErrorAction Stop
                Set-ItemProperty -Path "IIS:\AppPools\$($appPool.Name)" -Name 'processModel.password' -Value $plainPassword -ErrorAction Stop

                [pscustomobject]@{
                    ComputerName = $env:COMPUTERNAME
                    AppPool      = $appPool.Name
                    IdentityType = 'SpecificUser'
                    UserName     = $AccountName
                    Result       = 'Password updated'
                }
            }
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
            Remove-Variable -Name plainPassword -ErrorAction SilentlyContinue
        }
    }
}

function Start-RemoteIisAndAppPools {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )

    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Import-Module WebAdministration -ErrorAction Stop

        $was = Get-Service -Name 'WAS' -ErrorAction Stop
        if ($was.Status -ne 'Running') {
            Start-Service -Name 'WAS' -ErrorAction Stop
        }

        $w3svc = Get-Service -Name 'W3SVC' -ErrorAction Stop
        if ($w3svc.Status -ne 'Running') {
            Start-Service -Name 'W3SVC' -ErrorAction Stop
        }

        Get-ChildItem -Path 'IIS:\AppPools' | ForEach-Object {
            if ($_.State -ne 'Started') {
                Start-WebAppPool -Name $_.Name -ErrorAction Stop
            }
        }
    }
}

function Get-RemoteIisAppPoolStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )

    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Import-Module WebAdministration -ErrorAction Stop

        Get-ChildItem -Path 'IIS:\AppPools' | Sort-Object Name | Select-Object @{
            Name = 'ComputerName'; Expression = { $env:COMPUTERNAME }
        }, Name, State, @{
            Name = 'IdentityType'; Expression = { $_.processModel.identityType }
        }, @{
            Name = 'UserName'; Expression = { $_.processModel.userName }
        }
    }
}

function Wait-PostStartInterval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Minutes
    )

    Write-Host "Waiting $Minutes minute(s) for services to initialize ..." -ForegroundColor Yellow
    Start-Sleep -Seconds ($Minutes * 60)
}

# Resolve the directory where this script resides, including when invoked from a different current directory.
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrWhiteSpace($ScriptDirectory)) {
    $ScriptDirectory = (Get-Location).Path
}

$InteractFile = Join-Path -Path $ScriptDirectory -ChildPath 'Interact.txt'
$RabbitMqFile = Join-Path -Path $ScriptDirectory -ChildPath 'RabbitMQ.txt'
$BluePrismFile = Join-Path -Path $ScriptDirectory -ChildPath 'BluePrism.txt'

try {
    # Steps 1-3: Read target hostnames.
    $InteractServer = (Get-HostNamesFromFile -Path $InteractFile -Description 'Interact.txt' -MinimumCount 1 -MaximumCount 1)[0]
    $RabbitMqServer = (Get-HostNamesFromFile -Path $RabbitMqFile -Description 'RabbitMQ.txt' -MinimumCount 1 -MaximumCount 1)[0]
    $BluePrismServers = @(Get-HostNamesFromFile -Path $BluePrismFile -Description 'BluePrism.txt' -MinimumCount 1 -MaximumCount 1000)

    Write-Host "`nTargets loaded:" -ForegroundColor Cyan
    Write-Host "  Interact  : $InteractServer"
    Write-Host "  RabbitMQ  : $RabbitMqServer"
    Write-Host "  Blue Prism: $($BluePrismServers -join ', ')"
    Write-Host "  Excluded IIS identity updates: $($ExcludedIisAppPools -join ', ')"

    Test-RemoteConnectivity -ComputerName @($InteractServer, $RabbitMqServer) + $BluePrismServers

    # Steps 4-7: Stop application services and IIS.
    Write-Host "`nStopping Interact services on $InteractServer ..." -ForegroundColor Cyan
    Stop-RemoteServices -ComputerName $InteractServer -ServiceName $InteractServiceNames | Format-Table -AutoSize

    Write-Host "`nStopping IIS on $InteractServer ..." -ForegroundColor Cyan
    Stop-RemoteIis -ComputerName $InteractServer | Format-Table -AutoSize

    Write-Host "`nStopping RabbitMQ service on $RabbitMqServer ..." -ForegroundColor Cyan
    Stop-RemoteServices -ComputerName $RabbitMqServer -ServiceName $RabbitMqServiceName | Format-Table -AutoSize

    Write-Host "`nStopping Blue Prism service(s) ..." -ForegroundColor Cyan
    Stop-RemoteServices -ComputerName $BluePrismServers -ServiceName $BluePrismServiceName | Format-Table -AutoSize

    # Steps 8-9: Operator checkpoint, account collection, and password collection.
    Confirm-Continue -Message 'All listed services and IIS have been stopped. Press Enter to continue'

    do {
        $ServiceAccountUserName = (Read-Host -Prompt 'Enter the service account name (DOMAIN\username or username@domain.example)').Trim()
        if ([string]::IsNullOrWhiteSpace($ServiceAccountUserName)) {
            Write-Warning 'A service account name is required.'
        }
    } until (-not [string]::IsNullOrWhiteSpace($ServiceAccountUserName))

    $NewServiceAccountPassword = Read-Host -Prompt "Enter the new password for $ServiceAccountUserName" -AsSecureString
    if ($NewServiceAccountPassword.Length -eq 0) {
        throw 'No password was entered. No password updates were performed.'
    }

    # Steps 10-11: RabbitMQ update, start, wait, report.
    Write-Host "`nUpdating RabbitMQ service logon credentials on $RabbitMqServer ..." -ForegroundColor Cyan
    Set-RemoteServiceLogonPassword -ComputerName $RabbitMqServer -ServiceName $RabbitMqServiceName -UserName $ServiceAccountUserName -Password $NewServiceAccountPassword | Format-Table -AutoSize

    Write-Host "Starting RabbitMQ service on $RabbitMqServer ..." -ForegroundColor Cyan
    Start-RemoteServices -ComputerName $RabbitMqServer -ServiceName $RabbitMqServiceName | Format-Table -AutoSize
    Wait-PostStartInterval -Minutes $PostStartWaitMinutes
    Write-Host "RabbitMQ service status:" -ForegroundColor Cyan
    Get-RemoteServiceStatus -ComputerName $RabbitMqServer -ServiceName $RabbitMqServiceName | Format-Table -AutoSize

    # Step 12.
    Confirm-Continue -Message 'Review RabbitMQ status. Press Enter to continue'

    # Steps 13-14: Interact Windows services update, start, wait, report.
    Write-Host "`nUpdating Interact service logon credentials on $InteractServer ..." -ForegroundColor Cyan
    Set-RemoteServiceLogonPassword -ComputerName $InteractServer -ServiceName $InteractServiceNames -UserName $ServiceAccountUserName -Password $NewServiceAccountPassword | Format-Table -AutoSize

    Write-Host "Starting Interact services on $InteractServer ..." -ForegroundColor Cyan
    Start-RemoteServices -ComputerName $InteractServer -ServiceName $InteractServiceNames | Format-Table -AutoSize
    Wait-PostStartInterval -Minutes $PostStartWaitMinutes
    Write-Host "Interact service status:" -ForegroundColor Cyan
    Get-RemoteServiceStatus -ComputerName $InteractServer -ServiceName $InteractServiceNames | Format-Table -AutoSize

    # Step 15.
    Confirm-Continue -Message 'Review Interact service status. Press Enter to continue'

    # Steps 16-17: IIS specific-user app pools update, start, wait, report.
    Write-Host "`nUpdating IIS application pool identity passwords on $InteractServer ..." -ForegroundColor Cyan
    Set-RemoteIisAppPoolPasswords -ComputerName $InteractServer -UserName $ServiceAccountUserName -Password $NewServiceAccountPassword -ExcludedAppPoolNames $ExcludedIisAppPools | Format-Table -AutoSize

    Write-Host "Starting IIS and all IIS application pools on $InteractServer ..." -ForegroundColor Cyan
    Start-RemoteIisAndAppPools -ComputerName $InteractServer
    Wait-PostStartInterval -Minutes $PostStartWaitMinutes
    Write-Host "IIS application pool status:" -ForegroundColor Cyan
    Get-RemoteIisAppPoolStatus -ComputerName $InteractServer | Format-Table -AutoSize

    # Step 18.
    Confirm-Continue -Message 'Review IIS application pool status. Press Enter to continue'

    # Steps 19-20: Blue Prism update, start, wait, report.
    Write-Host "`nUpdating Blue Prism service logon credentials ..." -ForegroundColor Cyan
    Set-RemoteServiceLogonPassword -ComputerName $BluePrismServers -ServiceName $BluePrismServiceName -UserName $ServiceAccountUserName -Password $NewServiceAccountPassword | Format-Table -AutoSize

    Write-Host "Starting Blue Prism service(s) ..." -ForegroundColor Cyan
    Start-RemoteServices -ComputerName $BluePrismServers -ServiceName $BluePrismStartServiceName | Format-Table -AutoSize
    Wait-PostStartInterval -Minutes $PostStartWaitMinutes
    Write-Host "Blue Prism service status:" -ForegroundColor Cyan
    Get-RemoteServiceStatus -ComputerName $BluePrismServers -ServiceName $BluePrismStartServiceName | Format-Table -AutoSize

    # Step 21.
    Confirm-Continue -Message 'YOU COMPLETED THE PASSWORD UPDATES IN THIS ENVIRONMENT!!! Press Enter to continue'
}
catch {
    Write-Error "Password-update workflow stopped: $($_.Exception.Message)"
    throw
}
finally {
    if ($null -ne $NewServiceAccountPassword) {
        Remove-Variable -Name NewServiceAccountPassword -ErrorAction SilentlyContinue
    }
}

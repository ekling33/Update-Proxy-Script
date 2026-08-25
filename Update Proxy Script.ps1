<#
.SYNOPSIS
Remotely uninstalls Citrix Secure Access Endpoint Analysis from machines
listed in machines.txt.

.REQUIREMENTS
- Windows PowerShell 5.1
- Run from an elevated PowerShell console
- WinRM / PowerShell Remoting enabled on remote machines
- The account running the script must be a local administrator on targets
- machines.txt must be in the same folder as this script

.NOTES
- One computer name or IP address per line in machines.txt.
- Blank lines and lines beginning with # are ignored.
- This script targets ONLY:
  Citrix Secure Access Endpoint Analysis
#>

$ErrorActionPreference = 'Stop'

$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$MachineList  = Join-Path -Path $ScriptFolder -ChildPath 'machines.txt'
$TimeStamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile      = Join-Path -Path $ScriptFolder -ChildPath "CitrixSecureAccessEndpointAnalysis_Uninstall_$TimeStamp.csv"

if (-not (Test-Path -LiteralPath $MachineList)) {
    throw "machines.txt was not found: $MachineList"
}

$Computers = Get-Content -LiteralPath $MachineList |
    ForEach-Object { $_.Trim() } |
    Where-Object {
        $_ -and -not $_.StartsWith('#')
    } |
    Sort-Object -Unique

if (-not $Computers) {
    throw "No computer names or IP addresses were found in machines.txt."
}

$RemoteUninstall = {
    $ErrorActionPreference = 'Stop'

    $TargetProductName = 'Citrix Secure Access Endpoint Analysis'

    $UninstallRegistryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    # Exact-name match prevents removal of other Citrix components.
    $Application = Get-ItemProperty -Path $UninstallRegistryPaths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -eq $TargetProductName
        } |
        Select-Object -First 1 DisplayName, DisplayVersion, PSChildName, UninstallString

    if (-not $Application) {
        return [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Product      = $TargetProductName
            Version      = $null
            Status       = 'Not installed'
            Details      = 'No exact matching uninstall registry entry was found.'
        }
    }

    try {
        # The uninstall registry key is an MSI product code, e.g.:
        # {07E0379E-4894-4D37-82DD-260D6952858F}
        if ($Application.PSChildName -notmatch '^\{[0-9A-Fa-f-]+\}$') {
            throw "The registered product key is not a valid MSI product code: $($Application.PSChildName)"
        }

        $MsiArguments = "/x $($Application.PSChildName) /qn /norestart"

        $Process = Start-Process `
            -FilePath 'msiexec.exe' `
            -ArgumentList $MsiArguments `
            -Wait `
            -PassThru `
            -WindowStyle Hidden

        switch ($Process.ExitCode) {
            0 {
                $Status = 'Uninstalled'
            }
            3010 {
                $Status = 'Uninstalled - reboot required'
            }
            1641 {
                $Status = 'Uninstalled - reboot initiated'
            }
            1605 {
                $Status = 'Already removed / product not installed'
            }
            default {
                $Status = "Failed - MSI exit code $($Process.ExitCode)"
            }
        }

        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Product      = $Application.DisplayName
            Version      = $Application.DisplayVersion
            Status       = $Status
            Details      = "msiexec.exe $MsiArguments"
        }
    }
    catch {
        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Product      = $Application.DisplayName
            Version      = $Application.DisplayVersion
            Status       = 'Uninstall error'
            Details      = $_.Exception.Message
        }
    }
}

$Results = foreach ($Computer in $Computers) {
    Write-Host "Processing $Computer..." -ForegroundColor Cyan

    try {
        Test-WSMan -ComputerName $Computer -ErrorAction Stop | Out-Null

        Invoke-Command `
            -ComputerName $Computer `
            -ScriptBlock $RemoteUninstall `
            -ErrorAction Stop
    }
    catch {
        [PSCustomObject]@{
            ComputerName = $Computer
            Product      = 'Citrix Secure Access Endpoint Analysis'
            Version      = $null
            Status       = 'Connection/remote error'
            Details      = $_.Exception.Message
        }
    }
}

$Results | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8
$Results | Format-Table -AutoSize

Write-Host ''
Write-Host "Finished. Results log saved to: $LogFile" -ForegroundColor Green

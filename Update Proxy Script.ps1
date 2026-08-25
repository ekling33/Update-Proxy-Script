<#
.SYNOPSIS
Remotely uninstalls only Citrix Secure Access Client from computers in machines.txt.

.REQUIREMENTS
- Windows PowerShell 5.1
- Run this script from an elevated PowerShell window
- PowerShell Remoting / WinRM enabled on target computers
- Account running the script must have local administrator rights on targets
- machines.txt must be in the same folder as this script

.NOTES
- One hostname or IP address per line in machines.txt
- Blank lines and lines starting with # are ignored
- This script deliberately does NOT target Citrix Workspace App or Citrix Gateway Plug-in
- Avoids Win32_Product, which can trigger MSI repair/reconfiguration activity
#>

$ErrorActionPreference = 'Stop'

# Determine paths relative to this script
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$MachineList  = Join-Path -Path $ScriptFolder -ChildPath 'machines.txt'
$TimeStamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile      = Join-Path -Path $ScriptFolder -ChildPath "CitrixSecureAccess_Uninstall_$TimeStamp.csv"

# Confirm the machines list exists
if (-not (Test-Path -LiteralPath $MachineList)) {
    throw "Could not find machines.txt at: $MachineList"
}

# Read computer names/IPs, ignoring blank lines and comments
$Computers = Get-Content -LiteralPath $MachineList |
    ForEach-Object { $_.Trim() } |
    Where-Object {
        $_ -and -not $_.StartsWith('#')
    } |
    Sort-Object -Unique

if (-not $Computers) {
    throw "No computer names or IP addresses were found in: $MachineList"
}

# This block runs on each remote computer.
$RemoteUninstall = {
    $ErrorActionPreference = 'Stop'

    # Check standard 64-bit and 32-bit Windows uninstall registry locations.
    $UninstallRegistryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    # Match ONLY the Citrix Secure Access Client product name.
    # Do not change this to Citrix Workspace App unless that is specifically intended.
    $CitrixSecureAccess = Get-ItemProperty -Path $UninstallRegistryPaths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -and $_.DisplayName -match '^Citrix Secure Access Client(\s|$)'
        } |
        Select-Object DisplayName, DisplayVersion, PSChildName, UninstallString, QuietUninstallString

    # Product was not found.
    if (-not $CitrixSecureAccess) {
        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Product      = $null
            Version      = $null
            Status       = 'Not installed'
            Details      = 'Citrix Secure Access Client was not found.'
        }

        return
    }

    # There should normally be one matching entry, but process all matches safely.
    foreach ($Application in $CitrixSecureAccess) {
        try {
            $ProductName    = $Application.DisplayName
            $ProductVersion = $Application.DisplayVersion

            # MSI-installed product: the registry key is normally the MSI product code.
            if ($Application.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
                $MsiArguments = "/x $($Application.PSChildName) /qn /norestart"

                $Process = Start-Process `
                    -FilePath 'msiexec.exe' `
                    -ArgumentList $MsiArguments `
                    -Wait `
                    -PassThru `
                    -WindowStyle Hidden

                $Details = "msiexec.exe $MsiArguments"
            }
            else {
                # Non-MSI installation: prefer the silent command if Citrix registered one.
                if ($Application.QuietUninstallString) {
                    $UninstallCommand = $Application.QuietUninstallString
                }
                else {
                    $UninstallCommand = $Application.UninstallString
                }

                if (-not $UninstallCommand) {
                    throw "No uninstall command was found in the registry."
                }

                # cmd.exe handles quoted paths and existing command-line arguments.
                $Process = Start-Process `
                    -FilePath 'cmd.exe' `
                    -ArgumentList "/c `"$UninstallCommand`"" `
                    -Wait `
                    -PassThru `
                    -WindowStyle Hidden

                $Details = $UninstallCommand
            }

            # Common successful Windows Installer exit codes:
            # 0 = Success
            # 3010 = Success; restart required
            # 1641 = Success; installer initiated restart
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

                default {
                    $Status = "Failed - exit code $($Process.ExitCode)"
                }
            }

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                Product      = $ProductName
                Version      = $ProductVersion
                Status       = $Status
                Details      = $Details
            }
        }
        catch {
            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                Product      = $Application.DisplayName
                Version      = $Application.DisplayVersion
                Status       = 'Error'
                Details      = $_.Exception.Message
            }
        }
    }
}

# Process every machine in machines.txt.
$Results = foreach ($Computer in $Computers) {
    Write-Host "Processing $Computer..." -ForegroundColor Cyan

    try {
        # Confirm the remote computer responds to WinRM before invoking the uninstall.
        Test-WSMan -ComputerName $Computer -ErrorAction Stop | Out-Null

        Invoke-Command `
            -ComputerName $Computer `
            -ScriptBlock $RemoteUninstall `
            -ErrorAction Stop
    }
    catch {
        [PSCustomObject]@{
            ComputerName = $Computer
            Product      = $null
            Version      = $null
            Status       = 'Connection/remote error'
            Details      = $_.Exception.Message
        }
    }
}

# Export a permanent record of results.
$Results | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8

# Show results onscreen.
$Results | Format-Table -AutoSize

Write-Host ''
Write-Host "Finished. Results log: $LogFile" -ForegroundColor Green

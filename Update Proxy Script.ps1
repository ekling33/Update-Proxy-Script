<#
.SYNOPSIS
    Remotely configures Microsoft Edge Stable rollback policy on computers listed in machines.txt.

.DESCRIPTION
    Run from an elevated Windows PowerShell 5.1 console using your current administrative credentials.
    machines.txt must be in the same folder as this script, with one hostname or FQDN per line.

    The script writes Microsoft Edge Update rollback policy values for Edge Stable:
      RollbackToTargetVersion{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062} = 1
      TargetVersionPrefix{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062} = 152.0.4191.66
      Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062} = 1 (always allow updates)

    A CSV results file is created beside the script.
#>

[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [string]$TargetVersion = '152.0.4191.66',

    [string]$MachineList = (Join-Path -Path $PSScriptRoot -ChildPath 'machines.txt'),

    [switch]$RestartEdgeUpdateService
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Start Windows PowerShell 5.1 with Run as Administrator, then run this script.'
}

if (-not (Test-Path -LiteralPath $MachineList)) {
    throw "Machine list was not found: $MachineList"
}

$computers = Get-Content -LiteralPath $MachineList |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    Sort-Object -Unique

if (-not $computers) {
    throw "No computer names were found in: $MachineList"
}

$remoteScript = {
    param(
        [string]$RequestedTargetVersion,
        [bool]$RestartUpdateServices
    )

    $ErrorActionPreference = 'Stop'

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
    $stableAppGuid = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'

    $updatePolicies = @{
        'AlwaysAllow'    = 1
        'Manual'         = 2
        'AutomaticSilent' = 3
    }

    $edgeExePaths = @(
        (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path -Path $env:ProgramFiles -ChildPath 'Microsoft\Edge\Application\msedge.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $beforeVersion = $null
    if ($edgeExePaths) {
        $beforeVersion = (Get-Item -LiteralPath $edgeExePaths[0]).VersionInfo.ProductVersion
    }

    New-Item -Path $policyPath -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name ("RollbackToTargetVersion" + $stableAppGuid) -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name ("TargetVersionPrefix" + $stableAppGuid) -PropertyType String -Value $RequestedTargetVersion -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name ("Update" + $stableAppGuid) -PropertyType DWord -Value $updatePolicies['AlwaysAllow'] -Force | Out-Null

    $serviceResults = @()
    if ($RestartUpdateServices) {
        foreach ($serviceName in @('edgeupdate', 'edgeupdatem')) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($null -ne $service) {
                try {
                    if ($service.Status -eq 'Running') {
                        Restart-Service -Name $serviceName -Force -ErrorAction Stop
                        $serviceResults += "$serviceName restarted"
                    }
                    else {
                        Start-Service -Name $serviceName -ErrorAction Stop
                        $serviceResults += "$serviceName started"
                    }
                }
                catch {
                    $serviceResults += "$serviceName: $($_.Exception.Message)"
                }
            }
            else {
                $serviceResults += "$serviceName not found"
            }
        }
    }

    $policyValues = Get-ItemProperty -Path $policyPath -ErrorAction Stop

    [PSCustomObject]@{
        ComputerName       = $env:COMPUTERNAME
        InstalledVersion   = $beforeVersion
        TargetVersion      = $policyValues.("TargetVersionPrefix" + $stableAppGuid)
        RollbackEnabled    = $policyValues.("RollbackToTargetVersion" + $stableAppGuid)
        UpdatePolicy       = $policyValues.("Update" + $stableAppGuid)
        EdgeUpdateServices = ($serviceResults -join '; ')
        Status             = 'Policy configured. Edge Update must complete a successful update check before the version changes.'
    }
}

$results = foreach ($computer in $computers) {
    Write-Host "Processing $computer ..." -ForegroundColor Cyan

    try {
        $result = Invoke-Command -ComputerName $computer -ScriptBlock $remoteScript -ArgumentList $TargetVersion, [bool]$RestartEdgeUpdateService -ErrorAction Stop
        $result
    }
    catch {
        [PSCustomObject]@{
            ComputerName       = $computer
            InstalledVersion   = $null
            TargetVersion      = $TargetVersion
            RollbackEnabled    = $null
            UpdatePolicy       = $null
            EdgeUpdateServices = $null
            Status             = "FAILED: $($_.Exception.Message)"
        }
    }
}

$timeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultsFile = Join-Path -Path $PSScriptRoot -ChildPath ("EdgeRollbackResults-" + $timeStamp + '.csv')
$results | Export-Csv -Path $resultsFile -NoTypeInformation -Encoding UTF8

$results | Format-Table -AutoSize
Write-Host "`nResults written to: $resultsFile" -ForegroundColor Green

<#
Example machines.txt:
# One computer name or FQDN per line. Blank lines and # comments are ignored.
VM-EDGE-01
VM-EDGE-02.contoso.com
# VM-EDGE-03

Examples:
.\Invoke-EdgeRollback-152.0.4191.66.ps1
.\Invoke-EdgeRollback-152.0.4191.66.ps1 -RestartEdgeUpdateService
#>

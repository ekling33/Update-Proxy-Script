<#
.SYNOPSIS
    Remotely configures Microsoft Edge Stable rollback policy on computers listed in machines.txt.

.DESCRIPTION
    Windows PowerShell 5.1 compatible. Run from an elevated PowerShell session using your
    current administrative credentials. Do not use Get-Credential.

    Put machines.txt in the same folder as this script. Use one hostname or FQDN per line.
    Blank lines and lines beginning with # are ignored.
#>

[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')]
    [string]$TargetVersion = '152.0.4191.66',

    [string]$MachineList = (Join-Path -Path $PSScriptRoot -ChildPath 'machines.txt'),

    [switch]$RestartEdgeUpdateService
)

$ErrorActionPreference = 'Stop'

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
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
    $rollbackValueName = 'RollbackToTargetVersion' + $stableAppGuid
    $targetValueName = 'TargetVersionPrefix' + $stableAppGuid
    $updateValueName = 'Update' + $stableAppGuid

    $edgeExePaths = @()
    if (${env:ProgramFiles(x86)}) {
        $edgeExePaths += (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft\Edge\Application\msedge.exe')
    }
    if ($env:ProgramFiles) {
        $edgeExePaths += (Join-Path -Path $env:ProgramFiles -ChildPath 'Microsoft\Edge\Application\msedge.exe')
    }
    $edgeExePaths = $edgeExePaths | Where-Object { Test-Path -LiteralPath $_ }

    $beforeVersion = $null
    if ($edgeExePaths.Count -gt 0) {
        $beforeVersion = (Get-Item -LiteralPath $edgeExePaths[0]).VersionInfo.ProductVersion
    }

    New-Item -Path $policyPath -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name $rollbackValueName -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name $targetValueName -PropertyType String -Value $RequestedTargetVersion -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name $updateValueName -PropertyType DWord -Value 1 -Force | Out-Null

    $serviceResults = @()
    if ($RestartUpdateServices) {
        foreach ($serviceName in @('edgeupdate', 'edgeupdatem')) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($null -eq $service) {
                $serviceResults += ($serviceName + ' not found')
                continue
            }

            try {
                if ($service.Status -eq 'Running') {
                    Restart-Service -Name $serviceName -Force -ErrorAction Stop
                    $serviceResults += ($serviceName + ' restarted')
                }
                else {
                    Start-Service -Name $serviceName -ErrorAction Stop
                    $serviceResults += ($serviceName + ' started')
                }
            }
            catch {
                $serviceResults += ($serviceName + ': ' + $_.Exception.Message)
            }
        }
    }

    $policyValues = Get-ItemProperty -Path $policyPath -ErrorAction Stop

    [PSCustomObject]@{
        ComputerName       = $env:COMPUTERNAME
        InstalledVersion   = $beforeVersion
        TargetVersion      = $policyValues.$targetValueName
        RollbackEnabled    = $policyValues.$rollbackValueName
        UpdatePolicy       = $policyValues.$updateValueName
        EdgeUpdateServices = ($serviceResults -join '; ')
        Status             = 'Policy configured. Edge Update must complete a successful update check before the version changes.'
    }
}

$results = foreach ($computer in $computers) {
    Write-Host ('Processing ' + $computer + ' ...') -ForegroundColor Cyan

    try {
        Invoke-Command -ComputerName $computer -ScriptBlock $remoteScript -ArgumentList $TargetVersion, [bool]$RestartEdgeUpdateService -ErrorAction Stop
    }
    catch {
        [PSCustomObject]@{
            ComputerName       = $computer
            InstalledVersion   = $null
            TargetVersion      = $TargetVersion
            RollbackEnabled    = $null
            UpdatePolicy       = $null
            EdgeUpdateServices = $null
            Status             = ('FAILED: ' + $_.Exception.Message)
        }
    }
}

$timeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultsFile = Join-Path -Path $PSScriptRoot -ChildPath ('EdgeRollbackResults-' + $timeStamp + '.csv')
$results | Export-Csv -Path $resultsFile -NoTypeInformation -Encoding UTF8

$results | Format-Table -AutoSize
Write-Host ''
Write-Host ('Results written to: ' + $resultsFile) -ForegroundColor Green

<#
Example machines.txt:
VM-EDGE-01
VM-EDGE-02
VM-EDGE-03.domain.local

Run from an elevated Windows PowerShell 5.1 window:
.\Invoke-EdgeRollback-152.0.4191.66-Fixed.ps1 -RestartEdgeUpdateService
#>


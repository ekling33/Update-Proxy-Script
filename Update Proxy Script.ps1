# Windows PowerShell 5.1 script.
# Removes the Microsoft Edge Stable rollback / version-pinning policies remotely.
# Run from an elevated PowerShell window.
# Put machines.txt in the same folder as this script.
# One computer name or FQDN per line. Lines beginning with # are ignored.

param(
    [switch]$RestartEdgeUpdateService
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    $ScriptFolder = $PSScriptRoot
}

$MachineList = Join-Path -Path $ScriptFolder -ChildPath 'machines.txt'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    throw 'Run this script from Windows PowerShell as Administrator.'
}

if (-not (Test-Path -LiteralPath $MachineList)) {
    throw ('machines.txt was not found: ' + $MachineList)
}

$computers = @()
foreach ($line in (Get-Content -LiteralPath $MachineList)) {
    $name = $line.Trim()
    if (($name.Length -gt 0) -and (-not $name.StartsWith('#'))) {
        $computers += $name
    }
}
$computers = $computers | Sort-Object -Unique

if ($computers.Count -eq 0) {
    throw ('No computer names were found in: ' + $MachineList)
}

$remoteScript = {
    param(
        [bool]$RestartServices
    )

    $ErrorActionPreference = 'Stop'

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
    $stableGuid = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
    $valueNames = @(
        ('RollbackToTargetVersion' + $stableGuid),
        ('TargetVersionPrefix' + $stableGuid),
        ('Update' + $stableGuid)
    )

    $removed = @()
    $notPresent = @()

    if (Test-Path -LiteralPath $policyPath) {
        foreach ($valueName in $valueNames) {
            $existingValue = Get-ItemProperty -Path $policyPath -Name $valueName -ErrorAction SilentlyContinue
            if ($null -ne $existingValue) {
                Remove-ItemProperty -Path $policyPath -Name $valueName -Force -ErrorAction Stop
                $removed += $valueName
            }
            else {
                $notPresent += $valueName
            }
        }
    }
    else {
        $notPresent = $valueNames
    }

    $serviceStatus = ''
    if ($RestartServices) {
        $messages = @()
        foreach ($serviceName in @('edgeupdate', 'edgeupdatem')) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($null -eq $service) {
                $messages += ($serviceName + ' not found')
            }
            else {
                try {
                    if ($service.Status -eq 'Running') {
                        Restart-Service -Name $serviceName -Force -ErrorAction Stop
                        $messages += ($serviceName + ' restarted')
                    }
                    else {
                        Start-Service -Name $serviceName -ErrorAction Stop
                        $messages += ($serviceName + ' started')
                    }
                }
                catch {
                    $messages += ($serviceName + ' service error: ' + $_.Exception.Message)
                }
            }
        }
        $serviceStatus = $messages -join '; '
    }

    $output = New-Object PSObject
    $output | Add-Member -MemberType NoteProperty -Name ComputerName -Value $env:COMPUTERNAME
    $output | Add-Member -MemberType NoteProperty -Name RemovedValues -Value ($removed -join '; ')
    $output | Add-Member -MemberType NoteProperty -Name ValuesNotPresent -Value ($notPresent -join '; ')
    $output | Add-Member -MemberType NoteProperty -Name EdgeUpdateServices -Value $serviceStatus
    $output | Add-Member -MemberType NoteProperty -Name Status -Value 'Rollback/version-target policy values removed. Edge Update can use the effective organization/default update policy.'
    $output
}

$results = @()
foreach ($computer in $computers) {
    Write-Host ('Processing ' + $computer + ' ...') -ForegroundColor Cyan

    try {
        $result = Invoke-Command -ComputerName $computer -ScriptBlock $remoteScript -ArgumentList ([bool]$RestartEdgeUpdateService) -ErrorAction Stop
        $results += $result
    }
    catch {
        $failure = New-Object PSObject
        $failure | Add-Member -MemberType NoteProperty -Name ComputerName -Value $computer
        $failure | Add-Member -MemberType NoteProperty -Name RemovedValues -Value ''
        $failure | Add-Member -MemberType NoteProperty -Name ValuesNotPresent -Value ''
        $failure | Add-Member -MemberType NoteProperty -Name EdgeUpdateServices -Value ''
        $failure | Add-Member -MemberType NoteProperty -Name Status -Value ('FAILED: ' + $_.Exception.Message)
        $results += $failure
    }
}

$timeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultsFile = Join-Path -Path $ScriptFolder -ChildPath ('EdgeRollbackRemovalResults-' + $timeStamp + '.csv')
$results | Export-Csv -LiteralPath $resultsFile -NoTypeInformation
$results | Format-Table -AutoSize
Write-Host ''
Write-Host ('Results written to: ' + $resultsFile) -ForegroundColor Green

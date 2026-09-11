# Windows PowerShell 5.1 script.
# Run from an elevated PowerShell window.
# Put machines.txt in the same folder as this script.
# One computer name or FQDN per line. Lines beginning with # are ignored.

param(
    [string]$TargetVersion = '152.0.4191.66',
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
        [string]$RequestedTargetVersion,
        [bool]$RestartServices
    )

    $ErrorActionPreference = 'Stop'

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
    $stableGuid = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
    $rollbackName = 'RollbackToTargetVersion' + $stableGuid
    $targetName = 'TargetVersionPrefix' + $stableGuid
    $updateName = 'Update' + $stableGuid

    $edgeExe = $null
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles')

    if (-not [string]::IsNullOrEmpty($programFilesX86)) {
        $candidate = Join-Path -Path $programFilesX86 -ChildPath 'Microsoft\Edge\Application\msedge.exe'
        if (Test-Path -LiteralPath $candidate) {
            $edgeExe = $candidate
        }
    }

    if (($null -eq $edgeExe) -and (-not [string]::IsNullOrEmpty($programFiles))) {
        $candidate = Join-Path -Path $programFiles -ChildPath 'Microsoft\Edge\Application\msedge.exe'
        if (Test-Path -LiteralPath $candidate) {
            $edgeExe = $candidate
        }
    }

    $installedVersion = $null
    if ($null -ne $edgeExe) {
        $installedVersion = (Get-Item -LiteralPath $edgeExe).VersionInfo.ProductVersion
    }

    New-Item -Path $policyPath -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name $rollbackName -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name $targetName -PropertyType String -Value $RequestedTargetVersion -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name $updateName -PropertyType DWord -Value 1 -Force | Out-Null

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

    $values = Get-ItemProperty -Path $policyPath

    $output = New-Object PSObject
    $output | Add-Member -MemberType NoteProperty -Name ComputerName -Value $env:COMPUTERNAME
    $output | Add-Member -MemberType NoteProperty -Name InstalledVersion -Value $installedVersion
    $output | Add-Member -MemberType NoteProperty -Name TargetVersion -Value $values.$targetName
    $output | Add-Member -MemberType NoteProperty -Name RollbackEnabled -Value $values.$rollbackName
    $output | Add-Member -MemberType NoteProperty -Name UpdatePolicy -Value $values.$updateName
    $output | Add-Member -MemberType NoteProperty -Name EdgeUpdateServices -Value $serviceStatus
    $output | Add-Member -MemberType NoteProperty -Name Status -Value 'Policy configured. Edge Update must complete a successful update check before the version changes.'
    $output
}

$results = @()
foreach ($computer in $computers) {
    Write-Host ('Processing ' + $computer + ' ...') -ForegroundColor Cyan

    try {
        $result = Invoke-Command -ComputerName $computer -ScriptBlock $remoteScript -ArgumentList $TargetVersion, ([bool]$RestartEdgeUpdateService) -ErrorAction Stop
        $results += $result
    }
    catch {
        $failure = New-Object PSObject
        $failure | Add-Member -MemberType NoteProperty -Name ComputerName -Value $computer
        $failure | Add-Member -MemberType NoteProperty -Name InstalledVersion -Value ''
        $failure | Add-Member -MemberType NoteProperty -Name TargetVersion -Value $TargetVersion
        $failure | Add-Member -MemberType NoteProperty -Name RollbackEnabled -Value ''
        $failure | Add-Member -MemberType NoteProperty -Name UpdatePolicy -Value ''
        $failure | Add-Member -MemberType NoteProperty -Name EdgeUpdateServices -Value ''
        $failure | Add-Member -MemberType NoteProperty -Name Status -Value ('FAILED: ' + $_.Exception.Message)
        $results += $failure
    }
}

$timeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultsFile = Join-Path -Path $ScriptFolder -ChildPath ('EdgeRollbackResults-' + $timeStamp + '.csv')
$results | Export-Csv -LiteralPath $resultsFile -NoTypeInformation
$results | Format-Table -AutoSize
Write-Host ''
Write-Host ('Results written to: ' + $resultsFile) -ForegroundColor Green

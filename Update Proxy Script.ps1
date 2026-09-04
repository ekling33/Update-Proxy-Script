<#
.SYNOPSIS
    Grants Modify rights to the specified identity on the Blue Prism ProgramData folder
    and copies required DLLs to remote computers in machines.txt.

.DESCRIPTION
    Compatible with Windows PowerShell 5.1.

    Place this script, machines.txt, and these DLLs in the same folder:
      BouncyCastle.Crypto.dll
      congent.congenthome.dll
      itextsharp.dll
      PdfSharp.dll

    machines.txt must contain one computer name per line. Blank lines and lines beginning
    with # are ignored.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$MachineListPath = (Join-Path -Path $PSScriptRoot -ChildPath 'machines.txt'),

    [string]$SourcePath = $PSScriptRoot,

    # Change to an AD group or account as appropriate, for example: CONTOSO\BluePrism Users
    [string]$Identity = 'Users',

    [System.Management.Automation.PSCredential]$Credential,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProgramDataPath = 'C:\ProgramData\Blue Prism Limited'
$AutomatePath = 'C:\Program Files\Blue Prism Limited\Blue Prism Automate'
$RequiredDlls = @(
    'BouncyCastle.Crypto.dll',
    'congent.congenthome.dll',
    'itextsharp.dll',
    'PdfSharp.dll'
)

function Write-Log {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level,

        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host ('[{0}] [{1}] {2}' -f $timestamp, $Level, $Message)
}

if (-not (Test-Path -LiteralPath $MachineListPath -PathType Leaf)) {
    throw "Machine list file was not found: $MachineListPath"
}

if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
    throw "DLL source folder was not found: $SourcePath"
}

$sourceDlls = @()
foreach ($dllName in $RequiredDlls) {
    $sourceFile = Join-Path -Path $SourcePath -ChildPath $dllName

    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Required DLL was not found: $sourceFile"
    }

    $sourceDlls += Get-Item -LiteralPath $sourceFile
}

$computers = @(
    Get-Content -LiteralPath $MachineListPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        Sort-Object -Unique
)

if ($computers.Count -eq 0) {
    throw "No computer names were found in: $MachineListPath"
}

$sessionOption = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 120000
$results = @()

foreach ($computer in $computers) {
    $result = [ordered]@{
        ComputerName = $computer
        Status = 'Not started'
        PermissionChange = 'Not attempted'
        CopiedDlls = ''
        Error = ''
    }

    Write-Log -Level INFO -Message ("Processing {0}" -f $computer)

    if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        $result.Status = 'Skipped - offline or ICMP unavailable'
        $result.Error = 'Target did not respond to Test-Connection.'
        Write-Log -Level WARN -Message ("{0} did not respond to ping. Skipping." -f $computer)
        $results += [pscustomobject]$result
        continue
    }

    $session = $null

    try {
        $newSessionParams = @{
            ComputerName = $computer
            SessionOption = $sessionOption
            ErrorAction = 'Stop'
        }

        if ($PSBoundParameters.ContainsKey('Credential')) {
            $newSessionParams.Credential = $Credential
        }

        $session = New-PSSession @newSessionParams

        if ($PSCmdlet.ShouldProcess($computer, ("Grant '{0}' Modify permission on '{1}'" -f $Identity, $ProgramDataPath))) {
            $permissionResult = Invoke-Command -Session $session -ArgumentList $ProgramDataPath, $Identity -ScriptBlock {
                param(
                    [string]$FolderPath,
                    [string]$AccountName
                )

                if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
                    throw "Directory does not exist: $FolderPath"
                }

                $acl = Get-Acl -LiteralPath $FolderPath
                $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
                $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
                $rights = [System.Security.AccessControl.FileSystemRights]::Modify
                $accessType = [System.Security.AccessControl.AccessControlType]::Allow

                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $AccountName,
                    $rights,
                    $inheritanceFlags,
                    $propagationFlags,
                    $accessType
                )

                $acl.SetAccessRule($rule)
                Set-Acl -LiteralPath $FolderPath -AclObject $acl

                [pscustomobject]@{
                    Identity = $AccountName
                    Rights = 'Modify'
                }
            }

            $result.PermissionChange = ("Modify granted to {0}" -f $permissionResult.Identity)
            Write-Log -Level SUCCESS -Message ("{0}: Modify permission granted to '{1}'." -f $computer, $Identity)
        }
        else {
            $result.PermissionChange = 'WhatIf - not changed'
        }

        $destinationExists = Invoke-Command -Session $session -ArgumentList $AutomatePath -ScriptBlock {
            param([string]$FolderPath)
            Test-Path -LiteralPath $FolderPath -PathType Container
        }

        if (-not $destinationExists) {
            throw ("Destination directory does not exist on {0}: {1}" -f $computer, $AutomatePath)
        }

        $copied = @()
        foreach ($dll in $sourceDlls) {
            $remoteDestination = Join-Path -Path $AutomatePath -ChildPath $dll.Name

            if ($PSCmdlet.ShouldProcess($computer, ("Copy '{0}' to '{1}'" -f $dll.Name, $remoteDestination))) {
                Copy-Item -Path $dll.FullName -Destination $remoteDestination -ToSession $session -Force:$Force.IsPresent -ErrorAction Stop
                $copied += $dll.Name
                Write-Log -Level SUCCESS -Message ("{0}: Copied {1}." -f $computer, $dll.Name)
            }
            else {
                $copied += ("{0} (WhatIf)" -f $dll.Name)
            }
        }

        $result.CopiedDlls = $copied -join '; '
        $result.Status = 'Completed'
    }
    catch {
        $result.Status = 'Failed'
        $result.Error = $_.Exception.Message
        Write-Log -Level ERROR -Message ("{0}: {1}" -f $computer, $_.Exception.Message)
    }
    finally {
        if ($null -ne $session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }

        $results += [pscustomobject]$result
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path -Path $PSScriptRoot -ChildPath ("BluePrism-Deployment-Report-{0}.csv" -f $timestamp)
$results | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host 'Deployment summary:' -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Log -Level INFO -Message ("CSV report saved to: {0}" -f $reportPath)

if ($results.Status -contains 'Failed') {
    exit 1
}

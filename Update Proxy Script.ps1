<#
.SYNOPSIS
    Grants a chosen principal Modify rights to the Blue Prism ProgramData folder and copies required DLLs to remote machines listed in machines.txt.

.DESCRIPTION
    Reads computer names from machines.txt, validates connectivity, grants Modify permission (this folder, subfolders, and files) on:
      C:\ProgramData\Blue Prism Limited

    It then copies these DLLs from the local source folder to:
      C:\Program Files\Blue Prism Limited\Blue Prism Automate

    - BouncyCastle.Crypto.dll
    - congent.congenthome.dll
    - itextsharp.dll
    - PdfSharp.dll

    The script is compatible with Windows PowerShell 5.1. Run it from an elevated PowerShell session
    using an account that has administrative access to every target computer.

.NOTES
    Place this script, machines.txt, and the four DLLs in the same folder, or use -SourcePath.
    machines.txt should contain one computer name per line. Blank lines and lines beginning with # are ignored.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$MachineListPath = (Join-Path -Path $PSScriptRoot -ChildPath 'machines.txt'),

    [Parameter()]
    [string]$SourcePath = $PSScriptRoot,

    # Change this to the appropriate AD group or local group/account if desired.
    [Parameter()]
    [string]$Identity = 'Users',

    [Parameter()]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProgramDataPath = 'C:\ProgramData\Blue Prism Limited'
$AutomatePath    = 'C:\Program Files\Blue Prism Limited\Blue Prism Automate'
$RequiredDlls    = @(
    'BouncyCastle.Crypto.dll',
    'congent.congenthome.dll',
    'itextsharp.dll',
    'PdfSharp.dll',
	'system.security.cryptography.algorithms.dll',
	'System.Security.Cryptography.X509Certificates.dll'
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

$sourceDlls = foreach ($dll in $RequiredDlls) {
    $sourceFile = Join-Path -Path $SourcePath -ChildPath $dll
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Required DLL was not found: $sourceFile"
    }
    Get-Item -LiteralPath $sourceFile
}

$computers = Get-Content -LiteralPath $MachineListPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    Sort-Object -Unique

if (-not $computers) {
    throw "No computer names were found in: $MachineListPath"
}

$sessionOption = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 120000
$results = New-Object System.Collections.Generic.List[object]

foreach ($computer in $computers) {
    $result = [ordered]@{
        ComputerName       = $computer
        Status             = 'Not started'
        PermissionChange   = 'Not attempted'
        CopiedDlls         = ''
        Error              = ''
    }

    Write-Log INFO "Processing $computer"

    if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        $result.Status = 'Skipped - offline or ICMP unavailable'
        $result.Error = 'Target did not respond to Test-Connection.'
        Write-Log WARN "$computer did not respond to ping. Skipping."
        $results.Add([pscustomobject]$result)
        continue
    }

    $session = $null
    try {
        $newSessionParams = @{
            ComputerName  = $computer
            SessionOption = $sessionOption
            ErrorAction   = 'Stop'
        }
        if ($PSBoundParameters.ContainsKey('Credential')) {
            $newSessionParams.Credential = $Credential
        }

        $session = New-PSSession @newSessionParams

        if ($PSCmdlet.ShouldProcess($computer, "Grant '$Identity' Modify permission on '$ProgramDataPath'")) {
            $permissionResult = Invoke-Command -Session $session -ScriptBlock {
                param($FolderPath, $AccountName)

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

                # SetAccessRule replaces an equivalent explicit rule for the principal rather than adding duplicates.
                $acl.SetAccessRule($rule)
                Set-Acl -LiteralPath $FolderPath -AclObject $acl

                [pscustomobject]@{
                    Path = $FolderPath
                    Identity = $AccountName
                    Rights = 'Modify'
                }
            } -ArgumentList $ProgramDataPath, $Identity -ErrorAction Stop

            $result.PermissionChange = "Modify granted to $($permissionResult.Identity)"
            Write-Log SUCCESS "$computer: Modify permission granted to '$Identity'."
        }
        else {
            $result.PermissionChange = 'WhatIf - not changed'
        }

        $destinationExists = Invoke-Command -Session $session -ScriptBlock {
            param($FolderPath)
            Test-Path -LiteralPath $FolderPath -PathType Container
        } -ArgumentList $AutomatePath -ErrorAction Stop

        if (-not $destinationExists) {
            throw "Destination directory does not exist on $computer: $AutomatePath"
        }

        $copied = New-Object System.Collections.Generic.List[string]
        foreach ($dll in $sourceDlls) {
            $remoteDestination = Join-Path -Path $AutomatePath -ChildPath $dll.Name

            if ($PSCmdlet.ShouldProcess($computer, "Copy '$($dll.Name)' to '$remoteDestination'")) {
                $copyParams = @{
                    Path        = $dll.FullName
                    Destination = $remoteDestination
                    ToSession   = $session
                    Force       = $Force.IsPresent
                    ErrorAction = 'Stop'
                }

                Copy-Item @copyParams
                $copied.Add($dll.Name)
                Write-Log SUCCESS "$computer: Copied $($dll.Name)."
            }
            else {
                $copied.Add("$($dll.Name) (WhatIf)")
            }
        }

        $result.CopiedDlls = $copied -join '; '
        $result.Status = 'Completed'
    }
    catch {
        $result.Status = 'Failed'
        $result.Error = $_.Exception.Message
        Write-Log ERROR "$computer: $($_.Exception.Message)"
    }
    finally {
        if ($session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }

        $results.Add([pscustomobject]$result)
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path -Path $PSScriptRoot -ChildPath "BluePrism-Deployment-Report-$timestamp.csv"
$results | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host 'Deployment summary:' -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Log INFO "CSV report saved to: $reportPath"

if ($results.Status -contains 'Failed') {
    exit 1
}

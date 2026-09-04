# Windows PowerShell 5.1 script
# Put this script, machines.txt, and all four DLL files in the same folder.
# machines.txt: one computer name per line. Lines starting with # are ignored.

param(
    [string]$Identity = 'Users',
    [switch]$Overwrite,
    [System.Management.Automation.PSCredential]$Credential
)

$ErrorActionPreference = 'Stop'

$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$MachineList = Join-Path $ScriptFolder 'machines.txt'
$ProgramDataFolder = 'C:\ProgramData\Blue Prism Limited'
$DestinationFolder = 'C:\Program Files\Blue Prism Limited\Blue Prism Automate'
$DllNames = @(
    'BouncyCastle.Crypto.dll',
    'congent.congenthome.dll',
    'itextsharp.dll',
    'PdfSharp.dll'
)

if (-not (Test-Path -LiteralPath $MachineList)) {
    throw 'machines.txt was not found beside the script.'
}

$SourceFiles = @()
foreach ($DllName in $DllNames) {
    $SourceFile = Join-Path $ScriptFolder $DllName
    if (-not (Test-Path -LiteralPath $SourceFile)) {
        throw ('Required DLL file was not found: {0}' -f $SourceFile)
    }
    $SourceFiles += Get-Item -LiteralPath $SourceFile
}

$Computers = @()
Get-Content -LiteralPath $MachineList | ForEach-Object {
    $Name = $_.Trim()
    if (($Name.Length -gt 0) -and (-not $Name.StartsWith('#'))) {
        $Computers += $Name
    }
}
$Computers = $Computers | Sort-Object -Unique

if ($Computers.Count -eq 0) {
    throw 'machines.txt did not contain any computer names.'
}

$Results = @()

foreach ($ComputerName in $Computers) {
    $Result = [ordered]@{
        ComputerName = $ComputerName
        Permission = 'Not attempted'
        Files = 'Not attempted'
        Status = 'Not started'
        Error = ''
    }

    Write-Host ('Processing {0}' -f $ComputerName) -ForegroundColor Cyan
    $Session = $null

    try {
        $SessionParams = @{
            ComputerName = $ComputerName
            ErrorAction = 'Stop'
        }

        if ($null -ne $Credential) {
            $SessionParams['Credential'] = $Credential
        }

        $Session = New-PSSession @SessionParams

        Invoke-Command -Session $Session -ArgumentList $ProgramDataFolder, $Identity -ScriptBlock {
            param($FolderPath, $AccountName)

            if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
                throw ('Folder does not exist: {0}' -f $FolderPath)
            }

            $Acl = Get-Acl -LiteralPath $FolderPath
            $Rights = [System.Security.AccessControl.FileSystemRights]::Modify
            $Inheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
            $Propagation = [System.Security.AccessControl.PropagationFlags]::None
            $AccessType = [System.Security.AccessControl.AccessControlType]::Allow

            $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule($AccountName, $Rights, $Inheritance, $Propagation, $AccessType)
            $Acl.SetAccessRule($Rule)
            Set-Acl -LiteralPath $FolderPath -AclObject $Acl
        }

        $Result.Permission = ('Modify granted to {0}' -f $Identity)

        $DestinationExists = Invoke-Command -Session $Session -ArgumentList $DestinationFolder -ScriptBlock {
            param($FolderPath)
            Test-Path -LiteralPath $FolderPath -PathType Container
        }

        if (-not $DestinationExists) {
            throw ('Destination folder does not exist: {0}' -f $DestinationFolder)
        }

        $CopiedFiles = @()
        foreach ($SourceFile in $SourceFiles) {
            $RemoteFile = Join-Path $DestinationFolder $SourceFile.Name
            Copy-Item -LiteralPath $SourceFile.FullName -Destination $RemoteFile -ToSession $Session -Force:$Overwrite.IsPresent -ErrorAction Stop
            $CopiedFiles += $SourceFile.Name
        }

        $Result.Files = $CopiedFiles -join '; '
        $Result.Status = 'Completed'
        Write-Host ('Completed {0}' -f $ComputerName) -ForegroundColor Green
    }
    catch {
        $Result.Status = 'Failed'
        $Result.Error = $_.Exception.Message
        Write-Host ('Failed on {0}: {1}' -f $ComputerName, $_.Exception.Message) -ForegroundColor Red
    }
    finally {
        if ($null -ne $Session) {
            Remove-PSSession -Session $Session -ErrorAction SilentlyContinue
        }
    }

    $Results += [pscustomobject]$Result
}

$TimeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$ReportFile = Join-Path $ScriptFolder ('BluePrismDeploymentReport-{0}.csv' -f $TimeStamp)
$Results | Export-Csv -LiteralPath $ReportFile -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host 'Deployment complete.' -ForegroundColor Yellow
Write-Host ('Report: {0}' -f $ReportFile) -ForegroundColor Yellow
$Results | Format-Table -AutoSize

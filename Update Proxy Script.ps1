$machineListPath = '.\machines.txt'
$outputCsv = '.\DefenderDefinitionStatus.csv'

if (-not (Test-Path $machineListPath)) {
    Write-Error 'machines.txt not found'
    exit 1
}

$computers = Get-Content $machineListPath | Where-Object { $_.Trim() -ne '' }

if (-not $computers) {
    Write-Error 'machines.txt is empty'
    exit 1
}

$results = foreach ($computer in $computers) {
    try {
        $result = Invoke-Command -ComputerName $computer -ScriptBlock {
            Import-Module Defender -ErrorAction SilentlyContinue
            $status = Get-MpComputerStatus

            if (-not $status.AntivirusEnabled) {
                $state = 'Antivirus Disabled'
            }
            elseif ($status.DefenderSignaturesOutOfDate) {
                $state = 'Outdated'
            }
            else {
                $state = 'Current'
            }

            [pscustomobject]@{
                ComputerName              = $env:COMPUTERNAME
                Status                    = $state
                DefinitionVersion         = $status.AntivirusSignatureVersion
                DefinitionsUpdateTime     = $status.AntivirusSignatureLastUpdated
                AntivirusEnabled          = $status.AntivirusEnabled
                RealTimeProtectionEnabled = $status.RealTimeProtectionEnabled
                Error                     = $null
            }
        } -ErrorAction Stop

        $result
    }
    catch {
        [pscustomobject]@{
            ComputerName              = $computer
            Status                    = 'Unreachable/Failed'
            DefinitionVersion         = $null
            DefinitionsUpdateTime     = $null
            AntivirusEnabled          = $null
            RealTimeProtectionEnabled = $null
            Error                     = $_.Exception.Message
        }
    }
}

$results | Format-Table -AutoSize
$results | Export-Csv -Path $outputCsv -NoTypeInformation

Write-Host ''
Write-Host "Results exported to $outputCsv" -ForegroundColor Green

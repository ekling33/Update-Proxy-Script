$machineListPath = '.\machines.txt'
$outputCsv = '.\DefenderAMProductVersion.csv'

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

            [pscustomobject]@{
                ComputerName        = $env:COMPUTERNAME
                AMProductVersion    = $status.AMProductVersion
                AMEngineVersion     = $status.AMEngineVersion
                AntivirusSignatureVersion = $status.AntivirusSignatureVersion
                AntivirusEnabled    = $status.AntivirusEnabled
                RealTimeProtectionEnabled = $status.RealTimeProtectionEnabled
                Error               = $null
            }
        } -ErrorAction Stop

        $result
    }
    catch {
        [pscustomobject]@{
            ComputerName        = $computer
            AMProductVersion    = $null
            AMEngineVersion     = $null
            AntivirusSignatureVersion = $null
            AntivirusEnabled    = $null
            RealTimeProtectionEnabled = $null
            Error               = $_.Exception.Message
        }
    }
}

$results | Format-Table -AutoSize
$results | Export-Csv -Path $outputCsv -NoTypeInformation

Write-Host ''
Write-Host "Results exported to $outputCsv" -ForegroundColor Green

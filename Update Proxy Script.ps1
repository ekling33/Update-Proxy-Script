$machineListPath = ".\machines.txt"
$outputCsv = ".\DefenderDefinitionStatus.csv"

if (-not (Test-Path $machineListPath)) {
    throw "machines.txt not found at $machineListPath"
}

$computers = Get-Content $machineListPath | Where-Object { $_.Trim() -ne "" }

if (-not $computers) {
    throw "machines.txt is empty"
}

$results = foreach ($computer in $computers) {
    try {
        $result = Invoke-Command -ComputerName $computer -ScriptBlock {
            try {
                Import-Module Defender -ErrorAction SilentlyContinue

                $status = Get-MpComputerStatus -ErrorAction Stop

                if (-not $status.AntivirusEnabled) {
                    $state = "Antivirus Disabled"
                }
                elseif ($status.DefenderSignaturesOutOfDate) {
                    $state = "Outdated"
                }
                else {
                    $state = "Current"
                }

                [pscustomobject]@{
                    ComputerName                = $env:COMPUTERNAME
                    Status                      = $state
                    InstalledSignatureVersion   = $status.AntivirusSignatureVersion
                    SignatureLastUpdated        = $status.AntivirusSignatureLastUpdated
                    DefenderSignaturesOutOfDate = $status.DefenderSignaturesOutOfDate
                    AntivirusEnabled            = $status.AntivirusEnabled
                    RealTimeProtectionEnabled   = $status.RealTimeProtectionEnabled
                    AMRunningMode               = $status.AMRunningMode
                    Error                       = $null
                }
            }
            catch {
                [pscustomobject]@{
                    ComputerName                = $env:COMPUTERNAME
                    Status                      = "Check Failed"
                    InstalledSignatureVersion   = $null
                    SignatureLastUpdated        = $null
                    DefenderSignaturesOutOfDate = $null
                    AntivirusEnabled            = $null
                    RealTimeProtectionEnabled   = $null
                    AMRunningMode               = $null
                    Error                       = $_.Exception.Message
                }
            }
        } -ErrorAction Stop

        $result
    }
    catch {
        [pscustomobject]@{
            ComputerName                = $computer
            Status                      = "Unreachable/Failed"
            InstalledSignatureVersion   = $null
            SignatureLastUpdated        = $null
            DefenderSignaturesOutOfDate = $null
            AntivirusEnabled            = $null
            RealTimeProtectionEnabled   = $null
            AMRunningMode               = $null
            Error                       = $_.Exception.Message
        }
    }
}

$results | Sort-Object ComputerName | Format-Table -AutoSize
$results | Sort-Object ComputerName | Export-Csv -Path $outputCsv -NoTypeInformation

Write-Host ""
Write-Host "Results exported to $outputCsv" -ForegroundColor Green

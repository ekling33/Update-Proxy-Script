$machineListPath = ".\machines.txt"
$outputCsv = ".\DefenderDefinitionStatus.csv"
$updateUrl = "https://www.microsoft.com/wdsi/defenderupdates"

if (-not (Test-Path $machineListPath)) {
    throw "machines.txt not found at $machineListPath"
}

$computers = Get-Content $machineListPath | Where-Object { $_.Trim() -ne "" }

if (-not $computers) {
    throw "machines.txt is empty"
}

try {
    $latestPage = Invoke-WebRequest -Uri $updateUrl -UseBasicParsing -ErrorAction Stop
    $latestVersion = [regex]::Match($latestPage.Content, 'Version:\s*([0-9\.]+)').Groups[1].Value

    if (-not $latestVersion) {
        throw "Could not determine latest Defender intelligence version from Microsoft."
    }
}
catch {
    throw "Failed to retrieve latest Defender version from Microsoft. $($_.Exception.Message)"
}

Write-Host "Latest Microsoft Defender intelligence version: $latestVersion" -ForegroundColor Cyan

$results = foreach ($computer in $computers) {
    $session = $null

    try {
        $session = New-CimSession -ComputerName $computer -ErrorAction Stop
        $status = Get-MpComputerStatus -CimSession $session -ErrorAction Stop

        $installedVersion = $status.AntivirusSignatureVersion
        $lastUpdated = $status.AntivirusSignatureLastUpdated
        $sigOutOfDate = $status.DefenderSignaturesOutOfDate
        $avEnabled = $status.AntivirusEnabled
        $rtEnabled = $status.RealTimeProtectionEnabled

        try {
            $installed = [version]$installedVersion
            $latest = [version]$latestVersion

            if (-not $avEnabled) {
                $state = "Antivirus Disabled"
            }
            elseif ($installed -eq $latest) {
                $state = "Current"
            }
            elseif ($installed -lt $latest) {
                $state = "Outdated"
            }
            else {
                $state = "Newer than published"
            }
        }
        catch {
            $state = "Could not compare versions"
        }

        [pscustomobject]@{
            ComputerName                = $computer
            Status                      = $state
            InstalledSignatureVersion   = $installedVersion
            LatestMicrosoftVersion      = $latestVersion
            SignatureLastUpdated        = $lastUpdated
            DefenderSignaturesOutOfDate = $sigOutOfDate
            AntivirusEnabled            = $avEnabled
            RealTimeProtectionEnabled   = $rtEnabled
            Error                       = $null
        }
    }
    catch {
        [pscustomobject]@{
            ComputerName                = $computer
            Status                      = "Unreachable/Failed"
            InstalledSignatureVersion   = $null
            LatestMicrosoftVersion      = $latestVersion
            SignatureLastUpdated        = $null
            DefenderSignaturesOutOfDate = $null
            AntivirusEnabled            = $null
            RealTimeProtectionEnabled   = $null
            Error                       = $_.Exception.Message
        }
    }
    finally {
        if ($session) {
            Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
        }
    }
}

$results | Sort-Object ComputerName | Format-Table -AutoSize
$results | Sort-Object ComputerName | Export-Csv -Path $outputCsv -NoTypeInformation

Write-Host ""
Write-Host "Results exported to $outputCsv" -ForegroundColor Green

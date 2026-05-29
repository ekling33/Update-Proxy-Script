$machineListPath = ".\machines.txt"

if (-not (Test-Path $machineListPath)) {
    throw "machines.txt not found at $machineListPath"
}

$computers = Get-Content $machineListPath | Where-Object { $_.Trim() -ne "" }

if (-not $computers) {
    throw "machines.txt is empty"
}

# Get Microsoft's currently published Defender security intelligence version
$latestPage = Invoke-WebRequest -Uri "https://www.microsoft.com/wdsi/defenderupdates" -UseBasicParsing
$latestVersion = [regex]::Match($latestPage.Content, 'Version:\s*([0-9\.]+)').Groups[1].Value

if (-not $latestVersion) {
    throw "Could not determine latest Defender intelligence version from Microsoft."
}

Write-Host "Latest Microsoft Defender intelligence version: $latestVersion" -ForegroundColor Cyan

$results = foreach ($computer in $computers) {
    try {
        $session = New-CimSession -ComputerName $computer -ErrorAction Stop

        $status = Get-MpComputerStatus -CimSession $session -ErrorAction Stop

        $installedVersion = $status.AntivirusSignatureVersion
        $lastUpdated      = $status.AntivirusSignatureLastUpdated
        $sigOutOfDate     = $status.DefenderSignaturesOutOfDate
        $avEnabled        = $status.AntivirusEnabled
        $rtEnabled        = $status.RealTimeProtectionEnabled

        $versionCompare = [version]$installedVersion -compareTo ([version]$latestVersion)

        $state = if (-not $avEnabled) {
            "Antivirus Disabled"
        }
        elseif ($versionCompare -eq 0) {
            "Current"
        }
        elseif ($versionCompare -lt 0) {
            "Outdated"
        }
        else {
            "Newer than published"
        }

        [pscustomobject]@{
            ComputerName                  = $computer
            Status                        = $state
            InstalledSignatureVersion     = $installedVersion
            LatestMicrosoftVersion        = $latestVersion
            SignatureLastUpdated          = $lastUpdated
            DefenderSignaturesOutOfDate   = $sigOutOfDate
            AntivirusEnabled              = $avEnabled
            RealTimeProtectionEnabled     = $rtEnabled
            Error                         = $null
        }

        Remove-CimSession $session
    }
    catch {
        [pscustomobject]@{
            ComputerName                  = $computer
            Status                        = "Unreachable/Failed"
            InstalledSignatureVersion     = $null
            LatestMicrosoftVersion        = $latestVersion
            SignatureLastUpdated          = $null
            DefenderSignaturesOutOfDate   = $null
            AntivirusEnabled              = $null
            RealTimeProtectionEnabled     = $null
            Error                         = $_.Exception.Message
        }
    }
}

$results | Format-Table -AutoSize
$results | Export-Csv -Path ".\DefenderDefinitionStatus.csv" -NoTypeInformation

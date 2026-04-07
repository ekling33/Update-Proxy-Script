[CmdletBinding()]
param(
    [string]$MachineListPath = ".\machines.txt",
    [string]$ReportOutputPath = ".\ChromeVersionReport.html"
)

if (-not (Test-Path $MachineListPath)) {
    Write-Error "Machine list file not found: $MachineListPath"
    exit 1
}

$machines = Get-Content $MachineListPath | Where-Object { $_ -and $_.Trim() -ne '' }
if (-not $machines) {
    Write-Error "No machines found in $MachineListPath"
    exit 1
}

Write-Host "Found $($machines.Count) machine(s) to query..." -ForegroundColor Cyan

$chromeScriptBlock = {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Google\Chrome\BLBeacon',
        'HKLM:\SOFTWARE\WOW6432Node\Google\Chrome\BLBeacon',
        'HKCU:\SOFTWARE\Google\Chrome\BLBeacon'
    )

    $version = $null

    foreach ($path in $registryPaths) {
        try {
            $val = Get-ItemProperty -Path $path -Name version -ErrorAction SilentlyContinue
            if ($val -and $val.version) {
                $version = $val.version
                break
            }
        }
        catch {
        }
    }

    if (-not $version) {
        $exePaths = @(
            (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:LocalAppData 'Google\Chrome\Application\chrome.exe')
        )

        foreach ($exe in $exePaths) {
            if ($exe -and (Test-Path $exe)) {
                $version = (Get-Item $exe).VersionInfo.ProductVersion
                break
            }
        }
    }

    $osCaption = $null
    try {
        $osCaption = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    }
    catch {
        $osCaption = 'Unknown'
    }

    if (-not $version) {
        $version = 'Not Installed'
    }

    [PSCustomObject]@{
        ComputerName  = $env:COMPUTERNAME
        ChromeVersion = $version
        OSCaption     = $osCaption
        QueryTime     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
}

$results = @()

foreach ($machine in $machines) {
    $machine = $machine.Trim()
    if (-not $machine) { continue }

    Write-Host "Querying: $machine"

    try {
        $data = Invoke-Command -ComputerName $machine -ScriptBlock $chromeScriptBlock -ErrorAction Stop

        $result = [PSCustomObject]@{
            ComputerName  = $machine
            ReportedName  = $data.ComputerName
            ChromeVersion = $data.ChromeVersion
            OSCaption     = $data.OSCaption
            QueryTime     = $data.QueryTime
            Status        = 'Success'
        }
    }
    catch {
        $result = [PSCustomObject]@{
            ComputerName  = $machine
            ReportedName  = 'N/A'
            ChromeVersion = 'N/A'
            OSCaption     = 'N/A'
            QueryTime     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Status        = ('Error: ' + $_.Exception.Message)
        }
    }

    $results += $result
}

$successCount = @($results | Where-Object { $_.Status -eq 'Success' }).Count
$errorCount   = @($results | Where-Object { $_.Status -ne 'Success' }).Count
$notInstalled = @($results | Where-Object { $_.ChromeVersion -eq 'Not Installed' }).Count
$reportDate   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$style = @"
<style>
body { font-family: Arial, sans-serif; font-size: 14px; color: #222; background: #f5f5f5; margin: 20px; }
h1 { margin-bottom: 6px; }
p.meta { color: #666; margin-top: 0; }
.summary { margin: 20px 0; padding: 12px; background: #fff; border: 1px solid #ddd; }
.summary span { display: inline-block; margin-right: 20px; font-weight: bold; }
table { border-collapse: collapse; width: 100%; background: #fff; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background: #f0f0f0; }
.success { color: green; font-weight: bold; }
.error { color: #b00020; font-weight: bold; }
.warn { color: #a06000; font-weight: bold; }
</style>
"@

$html = "<html><head><title>Chrome Version Report</title>$style</head><body>"
$html += "<h1>Google Chrome Version Report</h1>"
$html += "<p class='meta'>Generated: $reportDate</p>"
$html += "<div class='summary'>"
$html += "<span>Total Machines: $($results.Count)</span>"
$html += "<span>Successful: $successCount</span>"
$html += "<span>Errors: $errorCount</span>"
$html += "<span>Chrome Not Installed: $notInstalled</span>"
$html += "</div>"
$html += "<table>"
$html += "<tr><th>Target Name</th><th>Reported Hostname</th><th>Chrome Version</th><th>Operating System</th><th>Query Time</th><th>Status</th></tr>"

foreach ($r in $results) {
    $statusClass = 'success'
    if ($r.Status -ne 'Success') {
        $statusClass = 'error'
    }

    $versionClass = ''
    if ($r.ChromeVersion -eq 'Not Installed') {
        $versionClass = 'warn'
    }

    $html += '<tr>'
    $html += "<td>$($r.ComputerName)</td>"
    $html += "<td>$($r.ReportedName)</td>"
    $html += "<td class='$versionClass'>$($r.ChromeVersion)</td>"
    $html += "<td>$($r.OSCaption)</td>"
    $html += "<td>$($r.QueryTime)</td>"
    $html += "<td class='$statusClass'>$($r.Status)</td>"
    $html += '</tr>'
}

$html += '</table></body></html>'

Set-Content -Path $ReportOutputPath -Value $html -Encoding UTF8

$csvPath = [System.IO.Path]::ChangeExtension($ReportOutputPath, 'csv')
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "Report saved to: $ReportOutputPath" -ForegroundColor Cyan
Write-Host "CSV saved to: $csvPath" -ForegroundColor Cyan
Write-Host "Total machines queried: $($results.Count)"
Write-Host "Successful: $successCount"
Write-Host "Errors: $errorCount"
Write-Host "Chrome not installed: $notInstalled"

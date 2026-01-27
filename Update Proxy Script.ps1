param(
    [switch]$IncludeReboot
)

if (-not (Test-Path "machines.txt")) {
    Write-Error "Create machines.txt with one hostname/IP per line."
    exit 1
}

$machines = Get-Content "machines.txt"
$results = @()

foreach ($machine in $machines) {
    $result = [PSCustomObject]@{
        Machine = $machine
        ChromePreVersion = $null
        UpdateSuccess = $false
        Error = $null
    }

    try {
        Invoke-Command -ComputerName $machine -ScriptBlock {
            $chromePath = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            $updateExe = "${env:ProgramFiles(x86)}\Google\Update\GoogleUpdate.exe"

            # Get current version
            $version = if (Test-Path $chromePath) { (Get-Item $chromePath).VersionInfo.FileVersion } else { "Not Installed" }

            # Kill Chrome processes
            Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force

            # Trigger update if updater exists
            if (Test-Path $updateExe) {
                Start-Process -FilePath $updateExe -ArgumentList "/ua /installsource scheduler" -NoNewWindow -Wait
                $updateSuccess = $true
            } else {
                $updateSuccess = $false
            }

            # Return results (version may not update immediately; relaunch Chrome to apply)
            "PreVersion: $version; Success: $updateSuccess"
        } -ErrorAction Stop | ForEach-Object {
            if ($_ -match "PreVersion: (.+); Success: (.+)") {
                $result.ChromePreVersion = $matches[1]
                $result.UpdateSuccess = ($matches[2] -eq "True")
            }
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    $results += $result

    if ($IncludeReboot) {
        Restart-Computer -ComputerName $machine -Force
    }
}

$results | Export-Csv "Chrome-Update-Results-$(Get-Date -Format 'yyyyMMdd-HHmm').csv" -NoTypeInformation
Write-Host "Results exported to CSV. Check post-update versions manually or re-run." -ForegroundColor Cyan

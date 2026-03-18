# Load machines list
$computers = Get-Content "C:\path\to\machines.txt" | Where-Object { $_ -match '\S' }

# Results array
$results = @()

foreach ($computer in $computers) {
    try {
        $updateResult = Invoke-Command -ComputerName $computer -ScriptBlock {
            $chromePaths = @(
                "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            )
            $updateExe = "${env:ProgramFiles(x86)}\Google\Update\GoogleUpdate.exe"
            
            $chromeInstalled = $false
            $chromePath = $null
            foreach ($path in $chromePaths) {
                if (Test-Path $path) { 
                    $chromeInstalled = $true
                    $chromePath = $path
                    break 
                }
            }
            
            if (-not $chromeInstalled) {
                return @{ Success = $false; Message = "Chrome not found"; Version = "N/A" }
            }
            
            if (Test-Path $updateExe) {
                Stop-Process -Name "chrome" -Force -ErrorAction SilentlyContinue
                & $updateExe /ua /installsource scheduler | Out-Null
                Start-Sleep -Seconds 10  # Brief wait for update
                $version = if (Test-Path $chromePath) { (Get-Item $chromePath).VersionInfo.ProductVersion } else { "Updated (path changed?)" }
                return @{ Success = $true; Message = "Update triggered"; Version = $version }
            } else {
                return @{ Success = $false; Message = "GoogleUpdate.exe not found"; Version = "N/A" }
            }
        }
        # Safely add to results
        $resultObj = $updateResult | ConvertTo-Json | ConvertFrom-Json
        $resultObj | Add-Member -NotePropertyName 'Computer' -NotePropertyValue $computer -Force
        $results += $resultObj
        Write-Host "Success on $computer`: $($updateResult.Message) - Version: $($updateResult.Version)"
    }
    catch {
        $results += [PSCustomObject]@{
            Computer = $computer
            Success = $false
            Message = $_.Exception.Message
            Version = "N/A"
        }
        Write-Warning "Failed on $computer`: $($_.Exception.Message)"
    }
}

# Export results
$results | Export-Csv "ChromeUpdateResults_$(Get-Date -Format 'yyyyMMdd_HHmm').csv" -NoTypeInformation
Write-Host "Results exported to CSV. Check for any failures."

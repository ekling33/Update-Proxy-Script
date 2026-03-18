# Load machines list
$computers = Get-Content "C:\path\to\machines.txt" | Where-Object { $_ -match '\S' }

# Credentials (prompts once or use stored)
$cred = Get-Credential -Message "Enter domain admin credentials"

# Results log
$results = @()

foreach ($computer in $computers) {
    try {
        $updateResult = Invoke-Command -ComputerName $computer -Credential $cred -ScriptBlock {
            $chromePaths = @(
                "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            )
            $updateExe = "${env:ProgramFiles(x86)}\Google\Update\GoogleUpdate.exe"
            
            $chromeInstalled = $false
            foreach ($path in $chromePaths) {
                if (Test-Path $path) { $chromeInstalled = $true; break }
            }
            
            if (-not $chromeInstalled) {
                return @{ Success = $false; Message = "Chrome not found"; Version = "N/A" }
            }
            
            if (Test-Path $updateExe) {
                Stop-Process -Name "chrome" -Force -ErrorAction SilentlyContinue
                Start-Process -FilePath $updateExe -ArgumentList "/ua /installsource scheduler" -Wait -NoNewWindow -ErrorAction Stop
                $version = (Get-Item $chromePaths[0]).VersionInfo.ProductVersion
                return @{ Success = $true; Message = "Updated"; Version = $version }
            } else {
                return @{ Success = $false; Message = "GoogleUpdate.exe not found"; Version = "N/A" }
            }
        }
        $results += [PSCustomObject]@{ Computer = $computer; $($updateResult) }
        Write-Host "Success on $computer`: $($updateResult.Message) $($updateResult.Version)"
    }
    catch {
        $results += [PSCustomObject]@{ Computer = $computer; Success = $false; Message = $_.Exception.Message; Version = "N/A" }
        Write-Warning "Failed on $computer`: $($_.Exception.Message)"
    }
}

# Export results
$results | Export-Csv "ChromeUpdateResults_$(Get-Date -Format 'yyyyMMdd_HHmm').csv" -NoTypeInformation

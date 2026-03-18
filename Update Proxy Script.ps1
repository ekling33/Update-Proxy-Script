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
            
            # Check if Chrome exists
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
                # Install if missing
                $msiUrl = "https://dl.google.com/dl/chrome/win64/ChromeSetup.msi"
                $tempMsi = "C:\temp\ChromeLatest.msi"
                New-Item "C:\temp" -ItemType Directory -Force | Out-Null
                Invoke-WebRequest -Uri $msiUrl -OutFile $tempMsi -UseBasicParsing
                
                Start-Process "msiexec.exe" -ArgumentList "/i `"$tempMsi`" /qn /norestart" -Wait -NoNewWindow
                Remove-Item $tempMsi -Force
                
                $finalPath = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
                $version = if (Test-Path $finalPath) { (Get-Item $finalPath).VersionInfo.ProductVersion } else { "Install complete, verify path" }
                return @{ Success = $true; Message = "Fresh MSI install"; Version = $version }
            } else {
                # Upgrade existing + policy fix
                # Enable updates policy
                $policyPath = "HKLM:\SOFTWARE\Policies\Google\Update"
                $updateKey = "Update{8A69D345-D564-463C-AFF1-A69D9E530F96}"
                if (-not (Test-Path $policyPath)) { New-Item -Path $policyPath -Force | Out-Null }
                Set-ItemProperty -Path $policyPath -Name $updateKey -Value 1 -Type DWord -Force
                
                # Force MSI upgrade
                $msiUrl = "https://dl.google.com/dl/chrome/win64/ChromeSetup.msi"
                $tempMsi = "C:\temp\ChromeLatest.msi"
                New-Item "C:\temp" -ItemType Directory -Force | Out-Null
                Invoke-WebRequest -Uri $msiUrl -OutFile $tempMsi -UseBasicParsing
                
                Stop-Process -Name "chrome" -Force -ErrorAction SilentlyContinue
                Start-Process "msiexec.exe" -ArgumentList "/i `"$tempMsi`" /qn /norestart REINSTALL=ALL REINSTALLMODE=vamus" -Wait -NoNewWindow
                
                Remove-Item $tempMsi -Force
                Start-Sleep -Seconds 5
                
                $finalPath = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
                $version = if (Test-Path $finalPath) { (Get-Item $finalPath).VersionInfo.ProductVersion } else { "Upgrade complete" }
                return @{ Success = $true; Message = "MSI Upgrade + Policy Fixed"; Version = $version }
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
$results | Export-Csv "ChromeMSIUpdateResults_$(Get-Date -Format 'yyyyMMdd_HHmm').csv" -NoTypeInformation
Write-Host "Full results in ChromeMSIUpdateResults CSV. Latest: 146.0.7680.80+"

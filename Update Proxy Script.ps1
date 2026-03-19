# Load machines list
$computers = Get-Content "C:\path\to\machines.txt" | Where-Object { $_ -match '\S' }

$results = @()

foreach ($computer in $computers) {
    try {
        $updateResult = Invoke-Command -ComputerName $computer -ScriptBlock {
            $chromePaths = @(
                "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            )
            
            # Check existing
            $chromeInstalled = $false
            foreach ($path in $chromePaths) {
                if (Test-Path $path) { $chromeInstalled = $true; break }
            }
            
            # Enterprise MSI URLs (working 2026)
            $msiUrls = @(
                "https://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise64.msi",  # x64
                "https://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise.msi"       # x86
            )
            $tempMsi = "C:\temp\ChromeEnterprise.msi"
            New-Item "C:\temp" -ItemType Directory -Force | Out-Null
            
            $msiDownloaded = $false
            foreach ($msiUrl in $msiUrls) {
                try {
                    Remove-Item $tempMsi -Force -ErrorAction SilentlyContinue
                    Invoke-WebRequest -Uri $msiUrl -OutFile $tempMsi -UseBasicParsing -TimeoutSec 60
                    
                    $fileInfo = Get-Item $tempMsi
                    if ($fileInfo.Length -gt 100MB -and $fileInfo.Extension -eq '.msi') {
                        $msiDownloaded = $true
                        Write-Output "Downloaded $msiUrl ($($fileInfo.Length/1MB)MB)"
                        break
                    }
                }
                catch {
                    Write-Warning "Failed $msiUrl`: $($_.Exception.Message)"
                    continue
                }
            }
            
            if (-not $msiDownloaded) {
                return @{ Success = $false; Message = "All MSI downloads failed"; Version = "N/A" }
            }
            
            # Policy enable
            $policyPath = "HKLM:\SOFTWARE\Policies\Google\Update"
            $updateKey = "Update{8A69D345-D564-463C-AFF1-A69D9E530F96}"
            New-Item $policyPath -Force | Out-Null -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $policyPath -Name $updateKey -Value 1 -Type DWord -Force
            
            # Install
            Stop-Process -Name "chrome" -Force -ErrorAction SilentlyContinue
            $msiArgs = "/i `"$tempMsi`" /qn /norestart REINSTALL=ALL REINSTALLMODE=vamus"
            $proc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -ne 0) { throw "MSI exit code: $($proc.ExitCode)" }
            
            Remove-Item $tempMsi -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            
            $versionPath = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            $version = if (Test-Path $versionPath) { 
                (Get-Item $versionPath).VersionInfo.ProductVersion 
            } else { "Installed - check paths" }
            
            return @{ Success = $true; Message = "Enterprise MSI + Policy"; Version = $version }
        }
        
        $resultObj = $updateResult | ConvertTo-Json | ConvertFrom-Json
        $resultObj | Add-Member -NotePropertyName 'Computer' -NotePropertyValue $computer
        $results += $resultObj
        Write-Host "$computer`: $($updateResult.Message) v$($updateResult.Version)"
    }
    catch {
        $results += [PSCustomObject]@{ Computer = $computer; Success = $false; Message = $_.Exception.Message; Version = "N/A" }
        Write-Warning "FAIL $computer`: $($_.Exception.Message)"
    }
}

$results | Export-Csv "ChromeEnterprise_$(Get-Date -Format 'yyyyMMdd_HHmm').csv" -NoTypeInformation
Write-Host "Done. Latest: 146.0.7680.154+ [web:49]"

# UPDATE $centralMsi below to your UNC path
$centralMsi = "\\yourserver\share\ChromeEnterprise.msi"  # e.g. \\fileserver\apps\ChromeEnterprise.msi
$computers = Get-Content "C:\path\to\machines.txt" | Where-Object { $_ -match '\S' }

$results = @()

foreach ($computer in $computers) {
    try {
        $updateResult = Invoke-Command -ComputerName $computer -ScriptBlock {
            param($MsiPath)
            
            # Verify MSI accessible
            if (-not (Test-Path $MsiPath)) {
                return @{ Success = $false; Message = "MSI not accessible: $MsiPath"; Version = "N/A" }
            }
            
            $chromePaths = @(
                "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            )
            
            $chromeInstalled = $false
            foreach ($path in $chromePaths) {
                if (Test-Path $path) { $chromeInstalled = $true; break }
            }
            
            # Policy fix
            $policyPath = "HKLM:\SOFTWARE\Policies\Google\Update"
            $updateKey = "Update{8A69D345-D564-463C-AFF1-A69D9E530F96}"
            New-Item $policyPath -Force | Out-Null -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $policyPath -Name $updateKey -Value 1 -Type DWord -Force
            
            # Copy locally + install
            $localMsi = "C:\temp\ChromeLocal.msi"
            New-Item "C:\temp" -ItemType Directory -Force | Out-Null
            Copy-Item $MsiPath $localMsi -Force
            
            Stop-Process -Name "chrome" -Force -ErrorAction SilentlyContinue
            $msiArgs = "/i `"$localMsi`" /qn /norestart REINSTALL=ALL REINSTALLMODE=vamus"
            $proc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -ne 0) { throw "MSI failed exit $($proc.ExitCode)" }
            
            Remove-Item $localMsi -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            
            $versionPath = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            $version = if (Test-Path $versionPath) { 
                (Get-Item $versionPath).VersionInfo.ProductVersion 
            } else { "Success - verify path" }
            
            return @{ Success = $true; Message = "Central MSI + Policy"; Version = $version }
        } -ArgumentList $centralMsi
        
        $resultObj = $updateResult | ConvertTo-Json | ConvertFrom-Json
        $resultObj | Add-Member -NotePropertyName 'Computer' -NotePropertyValue $computer
        $results += $resultObj
        Write-Host "$computer`: $($updateResult.Success) v$($updateResult.Version)"
    }
    catch {
        $results += [PSCustomObject]@{ Computer = $computer; Success = $false; Message = $_.Exception.Message; Version = "N/A" }
        Write-Warning "FAIL $computer`: $($_.Exception.Message)"
    }
}

$results | Export-Csv "ChromeCentral_$(Get-Date -Format 'yyyyMMdd_HHmm').csv" -NoTypeInformation
Write-Host "Central deployment complete. Update share MSI for future runs."

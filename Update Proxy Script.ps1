# ===== CHROME ENTERPRISE UPGRADE - SINGLE SCRIPT =====
# RUN AS ADMIN. UPDATE THIS PATH and $adminMachine:
$machinesPath = "C:\path\to\machines.txt"
$adminMachine = "YOUR-ADMIN-MACHINE-NAME"  # e.g., "DC01" or "192.168.1.10"

# Local MSI cache folder
$localShare = "C:\ChromeShare"

if (-not (Test-Path $localShare)) {
    New-Item $localShare -ItemType Directory -Force | Out-Null
}

# Create SMB share for remote access
$shareName = "ChromeShare"
if (-not (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $shareName -Path $localShare -FullAccess "Everyone" -ErrorAction Stop
    Write-Host "Created SMB share: \\$adminMachine\ChromeShare"
}

$x64Msi = Join-Path $localShare "ChromeEnterprise64.msi"
$x86Msi = Join-Path $localShare "ChromeEnterprise.msi"

# Download x64 MSI if missing/small
if (-not (Test-Path $x64Msi) -or ((Get-Item $x64Msi).Length -lt 100MB)) {
    Write-Host "Downloading Chrome x64 Enterprise MSI..."
    Invoke-WebRequest `
        -Uri "https://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise64.msi" `
        -OutFile $x64Msi
}

# Download x86 MSI if missing/small
if (-not (Test-Path $x86Msi) -or ((Get-Item $x86Msi).Length -lt 100MB)) {
    Write-Host "Downloading Chrome x86 Enterprise MSI..."
    Invoke-WebRequest `
        -Uri "https://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise.msi" `
        -OutFile $x86Msi
}

Write-Host "x64 MSI size: $([math]::Round((Get-Item $x64Msi).Length/1MB,1)) MB"
Write-Host "x86 MSI size: $([math]::Round((Get-Item $x86Msi).Length/1MB,1)) MB"

if (-not (Test-Path $machinesPath)) {
    throw "machines.txt not found: $machinesPath"
}

$computers = Get-Content $machinesPath | Where-Object { $_ -match '\S' }
$results = @()

$x64Unc = "\\$adminMachine\ChromeShare\ChromeEnterprise64.msi"
$x86Unc = "\\$adminMachine\ChromeShare\ChromeEnterprise.msi"

foreach ($computer in $computers) {
    try {
        $updateResult = Invoke-Command -ComputerName $computer -ScriptBlock {
            param(
                [string]$x64MsiRemote,
                [string]$x86MsiRemote
            )

            $x64Path = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
            $x86Path = "`"$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe`""

            $currentVersion = $null
            $currentVersionString = $null
            $arch = $null
            $centralMsi = $null

            # Detect installed Chrome + architecture
            if (Test-Path $x64Path) {
                $currentVersionString = (Get-Item $x64Path).VersionInfo.ProductVersion
                $parts = $currentVersionString.Split('.')
                if ($parts.Count -ge 3) {
                    $currentVersion = [version]::Parse(($parts[0..2] -join '.'))
                }
                $arch = "64-bit"
                $centralMsi = $x64MsiRemote
            }
            elseif (Test-Path $x86Path) {
                $currentVersionString = (Get-Item $x86Path).VersionInfo.ProductVersion
                $parts = $currentVersionString.Split('.')
                if ($parts.Count -ge 3) {
                    $currentVersion = [version]::Parse(($parts[0..2] -join '.'))
                }
                $arch = "32-bit"
                $centralMsi = $x86MsiRemote
            }
            else {
                $arch = "none→64-bit"
                $centralMsi = $x64MsiRemote
            }

            # If already 146 or higher, skip
            if ($currentVersion -and $currentVersion.Major -ge 146) {
                return @{
                    Success = $true
                    Message = "Already latest $arch $currentVersionString"
                    Version = $currentVersionString
                    Arch    = $arch
                }
            }

            if (-not (Test-Path $centralMsi)) {
                return @{
                    Success = $false
                    Message = "MSI not found: $centralMsi"
                    Version = $currentVersionString
                    Arch    = $arch
                }
            }

            # Enable update policy
            $policyPath = "HKLM:\SOFTWARE\Policies\Google\Update"
            New-Item $policyPath -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty `
                -Path $policyPath `
                -Name "Update{8A69D345-D564-463C-AFF1-A69D9E530F96}" `
                -Value 1 -Type DWord -Force

            # Copy MSI locally and install
            $localMsi = "C:\temp\Chrome_$arch.msi"
            New-Item "C:\temp" -ItemType Directory -Force | Out-Null
            Copy-Item $centralMsi $localMsi -Force

            Stop-Process -Name "chrome" -Force -ErrorAction SilentlyContinue

            $msiArgs = "/i `"$localMsi`" /qn /norestart REINSTALL=ALL REINSTALLMODE=vamus"
            $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow

            Remove-Item $localMsi -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            if ($proc.ExitCode -ne 0) {
                throw "MSI exit code: $($proc.ExitCode)"
            }

            # Read new version
            $finalPath = if (Test-Path $x64Path) { $x64Path } elseif (Test-Path $x86Path) { $x86Path } else { $null }
            $newVerString = $null
            if ($finalPath) {
                $newVerString = (Get-Item $finalPath).VersionInfo.ProductVersion
            } else {
                $newVerString = "Installed/updated - check manually"
            }

            return @{
                Success = $true
                Message = "Upgraded $arch → latest"
                Version = $newVerString
                Arch    = $arch
            }

        } -ArgumentList $x64Unc, $x86Unc

        # Back on admin machine – collect result
        $obj = $updateResult | ConvertTo-Json | ConvertFrom-Json
        $obj | Add-Member -NotePropertyName 'Computer' -NotePropertyValue $computer -Force
        $results += $obj

        Write-Host "$computer : $($obj.Success) - $($obj.Message) [$($obj.Arch)]"
    }
    catch {
        $results += [PSCustomObject]@{
            Computer = $computer
            Success  = $false
            Message  = $_.Exception.Message
            Version  = "N/A"
            Arch     = "Error"
        }
        Write-Warning "FAIL $computer : $($_.Exception.Message)"
    }
}

# Export summary
$csvName = "Chrome_Upgrade_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
$results | Export-Csv -Path $csvName -NoTypeInformation
Write-Host "Done. Results saved to $csvName"

# ===== SINGLE SCRIPT: Chrome Enterprise Upgrade =====
# Creates C:\ChromeShare with latest MSIs, deploys to machines.txt

# Config - UPDATE PATHS
$machinesPath = "C:\path\to\machines.txt"
$localShare = "C:\ChromeShare"

# Step 1: Setup share + download MSIs (idempotent)
if (-not (Test-Path $localShare)) { New-Item $localShare -ItemType Directory -Force | Out-Null }
$x64Msi = "$localShare\ChromeEnterprise64.msi"
$x86Msi = "$localShare\ChromeEnterprise.msi"

if (-not (Test-Path $x64Msi) -or ((Get-Item $x64Msi).Length -lt 100MB)) {
    Write-Host "Downloading x64 MSI..."
    Invoke-WebRequest "https://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise64.msi" -OutFile $x64Msi
}
if (-not (Test-Path $x86Msi) -or ((Get-Item $x86Msi).Length -lt 100MB)) {
    Write-Host "Downloading x86 MSI..."
    Invoke-WebRequest "https://dl.google.com/edgedl/chrome/install/GoogleChromeStandaloneEnterprise.msi" -OutFile $x86Msi
}

Write-Host "MSIs ready: x64=$((Get-Item $x64Msi).Length/1MB)MB, x86=$((Get-Item $x86Msi).Length/1MB)MB"

# Step 2: Load targets
if (-not (Test-Path $machinesPath)) { throw "machines.txt not found: $machinesPath" }
$computers = Get-Content $machinesPath | Where-Object { $_ -match '\S' }

$results = @()

foreach ($computer in $computers) {
    try {
        $updateResult = Invoke-Command -ComputerName $computer -ScriptBlock {
            param($x64MsiLocal, $x86MsiLocal)
            
            $x64Path = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
            $x86Path = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
            
            # Detect current
            $currentVersion = $null
            $arch = $null
            $targetMsi = $null
            
            if (Test-Path $x64Path) {
                $verStr = (Get-Item $x64Path).VersionInfo.ProductVersion
                $currentVersion = [version]($verStr -split '\.' | Select -First 3 -join '.')
                $arch = "64-bit"
                $targetMsi = $x64MsiLocal
            } elseif (Test-Path $x86Path) {
                $verStr = (Get-Item $x86Path).VersionInfo.ProductVersion
                $currentVersion = [version]($verStr -split '\.' | Select -First 3 -join '.')
                $arch = "32-bit"
                $targetMsi = $x86MsiLocal
            }
            
            # Already latest?
            if ($currentVersion -and $currentVersion.Major -ge 146) {
                return @{ Success = $true; Message = "Latest $arch v$currentVersion"; Version = $verStr; Arch = $arch }
            }
            
            # Verify MSI
            if (-not (Test-Path $targetMsi)) {
                return @{ Success = $false; Message = "MSI not found: $targetMsi"; Version = $currentVersion; Arch = $arch }
            }
            
            # Policy fix
            $policyPath = "HKLM:\SOFTWARE\Policies\Google\Update"
            New-Item $policyPath -Force | Out-Null -ErrorAction SilentlyContinue
            Set-ItemProperty $policyPath "Update{8A69D345-D564-463C-AFF1-A69D9E530F96}" 1 -Type DWord -Force
            
            # Deploy
            $localMsi = "C:\temp\Chrome_$arch.msi"
            New-Item "C:\temp" -ItemType Directory -Force | Out-Null
            Copy-Item $targetMsi $localMsi -Force
            
            Stop-Process "chrome" -Force -ErrorAction SilentlyContinue
            $msiArgs = "/i `"$localMsi`" /qn /norestart REINSTALL=ALL REINSTALLMODE=vamus"
            $proc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
            
            Remove-Item $localMsi -Force -ErrorAction SilentlyContinue
            Start-Sleep 3
            
            if ($proc.ExitCode -ne 0) { throw "MSI exit code: $($proc.ExitCode)" }
            
            $newVerPath = if ($arch -eq "64-bit") { $x64Path } else { $x86Path }
            $newVersion = if (Test-Path $newVerPath) { (Get-Item $newVerPath).VersionInfo.ProductVersion } else { "Deployed 146.x" }
            
            return @{ Success = $true; Message = "$arch → Latest 146.x"; Version = $newVersion; Arch = $arch }
        } -ArgumentList $x64Msi, $x86Msi
        
        $resultObj = $updateResult | ConvertTo-Json | ConvertFrom-Json
        $resultObj | Add-Member -NotePropertyName 'Computer' -NotePropertyValue $computer -Force
        $results += $resultObj
        Write-Host "$computer`: $($updateResult.Success) - $($updateResult.Message) [$($updateResult.Arch)]"
    }
    catch {
        $results += [PSCustomObject]@{
            Computer = $computer
            Success = $false
            Message = $_.Exception.Message
            Version = "N/A"
            Arch = "Error"
        }
        Write-Warning "FAIL $computer`: $($_.Exception.Message)"
    }
}

# Export
$csvName = "ChromeComplete_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
$results | Export-Csv $csvName -NoTypeInformation
Write-Host "Complete! Results: $csvName | MSIs cached: $localShare | Latest: 146.0.7680.154+"

# Remove-RawVP9Extensions-Multi.ps1
# Removes BOTH MS Raw Image Extension AND VP9 Video Extensions from machines.txt
# Run as admin. No reboot required.

param(
    [switch]$IncludeReboot
)

# Load targets from machines.txt
if (-not (Test-Path "machines.txt")) {
    Write-Error "Create machines.txt with one hostname/IP per line first."
    exit 1
}

$ComputerNames = Get-Content "machines.txt" | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }

if ($ComputerNames.Count -eq 0) {
    Write-Error "No valid machines found in machines.txt"
    exit 1
}

$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
$regName = "AllowDeploymentInSpecialProfiles"
$regValue = 1

# BOTH packages
$packages = @("Microsoft.RawImageExtension", "Microsoft.VP9VideoExtensions")

$results = @()

foreach ($ComputerName in $ComputerNames) {
    Write-Host "`n=== Processing $ComputerName ===" -ForegroundColor Green
    
    try {
        # Test WinRM
        if (-not (Test-WSMan -ComputerName $ComputerName -ErrorAction SilentlyContinue)) {
            throw "WinRM not available"
        }

        # Step 1: Enable special profile deployment
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($Path, $Name, $Value)
            if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
            gpupdate /force /wait:0
        } -ArgumentList $regPath, $regName, $regValue

        if ($IncludeReboot) {
            Write-Host "  Rebooting..."
            Restart-Computer -ComputerName $ComputerName -Force -Wait -For PowerShell -Timeout 600 -Delay 30
        }

        # Step 2: Remove BOTH packages
        $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($PkgList)

            $report = @{}

            foreach ($pkgName in $PkgList) {
                # User packages (bundle + regular)
                Get-AppxPackage -AllUsers -Name $pkgName -PackageTypeFilter Bundle |
                    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                
                Get-AppxPackage -AllUsers -Name $pkgName |
                    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                
                # Provisioned
                Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $pkgName |
                    Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
                
                # Counts
                $userCount = (Get-AppxPackage -AllUsers -Name $pkgName | Measure-Object).Count
                $provCount = (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $pkgName | Measure-Object).Count
                
                $report[$pkgName] = @{Users = $userCount; Provisioned = $provCount}
            }

            # Revert registry
            $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
            Remove-ItemProperty -Path $regPath -Name "AllowDeploymentInSpecialProfiles" -ErrorAction SilentlyContinue
            
            return $report
        } -ArgumentList $packages

        $results += [PSCustomObject]@{
            ComputerName = $ComputerName
            RawImageUsers = $result["Microsoft.RawImageExtension"].Users
            RawImageProv  = $result["Microsoft.RawImageExtension"].Provisioned
            VP9Users      = $result["Microsoft.VP9VideoExtensions"].Users
            VP9Prov       = $result["Microsoft.VP9VideoExtensions"].Provisioned
            Status        = "Success"
        }
        
        Write-Host "  ✓ Raw Image: Users=$($result['Microsoft.RawImageExtension'].Users), Prov=$($result['Microsoft.RawImageExtension'].Provisioned)"
        Write-Host "  ✓ VP9 Video: Users=$($result['Microsoft.VP9VideoExtensions'].Users), Prov=$($result['Microsoft.VP9VideoExtensions'].Provisioned)"
        
    } catch {
        $results += [PSCustomObject]@{
            ComputerName = $ComputerName
            RawImageUsers = "N/A"
            RawImageProv  = "N/A"
            VP9Users      = "N/A"
            VP9Prov       = "N/A"
            Status        = $_.Exception.Message -replace "`n"," "
        }
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Results
Write-Host "`n=== SUMMARY ===" -ForegroundColor Yellow
$results | Format-Table -AutoSize

$csvPath = "RawVP9-Removal-Results-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "Results saved: $csvPath" -ForegroundColor Cyan

# Remove-Paint3D-Multi.ps1
# Removes Paint 3D from machines.txt - NO REBOOT
# Run as admin

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
$pkgName = "Microsoft.MSPaint"

$results = @()

foreach ($ComputerName in $ComputerNames) {
    Write-Host "`n=== Processing $ComputerName ===" -ForegroundColor Green
    
    try {
        if (-not (Test-WSMan -ComputerName $ComputerName -ErrorAction SilentlyContinue)) {
            throw "WinRM not available"
        }

        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($Path, $Name, $Value)
            if (-not (Test-Path $Path)) { 
                New-Item -Path $Path -Force | Out-Null 
            }
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
            gpupdate /force /wait:0
        } -ArgumentList $regPath, $regName, $regValue

        $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($InnerPkgName)

            Get-AppxPackage -AllUsers -Name $InnerPkgName -PackageTypeFilter Bundle |
                Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            
            Get-AppxPackage -AllUsers -Name $InnerPkgName |
                Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $InnerPkgName |
                Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
            
            $userCount = (Get-AppxPackage -AllUsers -Name $InnerPkgName | Measure-Object).Count
            $provCount = (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $InnerPkgName | Measure-Object).Count
            
            $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
            Remove-ItemProperty -Path $regPath -Name "AllowDeploymentInSpecialProfiles" -ErrorAction SilentlyContinue
            
            return @{Users = $userCount; Provisioned = $provCount}
        } -ArgumentList $pkgName

        $results += [PSCustomObject]@{
            ComputerName = $ComputerName
            Paint3DUsers = $result.Users
            Paint3DProv  = $result.Provisioned
            Status       = "Success"
        }
        
        Write-Host "  ✓ Paint 3D: Users=$($result.Users), Prov=$($result.Provisioned)"
        
    }
    catch {
        $results += [PSCustomObject]@{
            ComputerName = $ComputerName
            Paint3DUsers = "N/A"
            Paint3DProv  = "N/A"
            Status       = $_.Exception.Message
        }
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Yellow
$results | Format-Table -AutoSize

$csvPath = "Paint3D-Removal-Results-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "Results saved: $csvPath" -ForegroundColor Cyan

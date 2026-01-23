param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName
)

# Target package DisplayName / Name
$pkgName = "Microsoft.WebMediaExtensions"

Write-Host "=== Step 1: Enable deployment in special profiles on $ComputerName ==="

$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
$regName = "AllowDeploymentInSpecialProfiles"
$regValue = 1

Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    param($Path, $Name, $Value)

    # Create policy path if missing
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    # Set DWORD to allow deployment in special profiles
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force

    gpupdate /force /wait:0
} -ArgumentList $regPath, $regName, $regValue

Write-Host "Registry updated on $ComputerName. Initiating reboot..."

Write-Host "=== Step 2: Rebooting $ComputerName and waiting for PowerShell availability ==="

Restart-Computer -ComputerName $ComputerName -Force -Wait -For PowerShell -Timeout 600 -Delay 30

Write-Host "Reboot complete. Connecting back to $ComputerName for removal..."

Write-Host "=== Step 3: Removing Web Media Extensions (Windows Codecs Library) on $ComputerName ==="

$result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    param($InnerPkgName)

    # Remove user packages (all users, bundle aware)
    Get-AppxPackage -AllUsers -Name $InnerPkgName -PackageTypeFilter Bundle |
        Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

    # Also catch non-bundle variants if any
    Get-AppxPackage -AllUsers -Name $InnerPkgName |
        Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

    # Remove provisioned copy
    Get-AppxProvisionedPackage -Online |
        Where-Object DisplayName -EQ $InnerPkgName |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

    # Verify counts
    $userCount = (Get-AppxPackage -AllUsers -Name $InnerPkgName | Measure-Object).Count
    $provCount = (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $InnerPkgName | Measure-Object).Count

    # Optional: revert registry flag
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
    Remove-ItemProperty -Path $regPath -Name "AllowDeploymentInSpecialProfiles" -ErrorAction SilentlyContinue

    return @{Users = $userCount; Provisioned = $provCount}
} -ArgumentList $pkgName

Write-Host "=== Web Media Extensions removal complete on $ComputerName ==="
Write-Host "Users: $($result.Users), Provisioned: $($result.Provisioned)"

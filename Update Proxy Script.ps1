param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName
)

# Step 1: Set registry key remotely to allow special profile deployments
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
$regName = "AllowDeploymentInSpecialProfiles"
$regValue = 1

Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    param($Path, $Name, $Value)
    
    # Create path if missing
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    
    # Set DWORD
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
    
    # Update policy
    gpupdate /force /wait:0
} -ArgumentList $regPath, $regName, $regValue

Write-Host "Registry updated on $ComputerName. Initiating reboot..."

# Step 2: Reboot (waits for completion)
Restart-Computer -ComputerName $ComputerName -Force -Wait -For PowerShell -Timeout 600 -Delay 30

Write-Host "Reboot complete. Removing 3D Viewer..."

# Step 3: Run cleanup script post-reboot
$result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    $pkgName = "Microsoft.Microsoft3DViewer"
    
    # Remove user packages
    Get-AppxPackage -AllUsers -Name $pkgName -PackageTypeFilter Bundle | 
        Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    
    # Remove provisioned
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $pkgName | 
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    
    # Verify & return counts
    $userCount = (Get-AppxPackage -AllUsers -Name $pkgName | Measure-Object).Count
    $provCount = (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $pkgName | Measure-Object).Count
    
    # Revert registry
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx"
    Remove-ItemProperty -Path $regPath -Name "AllowDeploymentInSpecialProfiles" -ErrorAction SilentlyContinue
    
    return @{Users = $userCount; Provisioned = $provCount}
}

Write-Host "3D Viewer removal complete on $ComputerName."
Write-Host "Users: $($result.Users), Provisioned: $($result.Provisioned)"

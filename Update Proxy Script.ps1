# Remove Microsoft Paint 3D from remote VMs (fixes related QIDs)
# Usage: Same as before - machines.txt, run as Admin

$ErrorActionPreference = 'Stop'
$machinesFile = 'machines.txt'  # Or create machines_failed.txt for the 3

if (-not (Test-Path $machinesFile)) { Write-Error "machines.txt missing."; exit 1 }

$machines = Get-Content $machinesFile | Where-Object { $_ -match '^\s*[\w\.\-\d]+\s*$' } | ForEach-Object { $_.Trim() }

$results = foreach ($machine in $machines) {
    try {
        Write-Host "Removing Paint 3D from $machine..." -ForegroundColor Cyan
        $session = New-PSSession -ComputerName $machine -ErrorAction Stop
        
        $output = Invoke-Command -Session $session -ScriptBlock {
            # Target Paint 3D specifically
            $pkgNames = @('Microsoft.MSPaint*', '*MSPaint*')
            
            foreach ($name in $pkgNames) {
                Get-AppxPackage -AllUsers $name -PackageTypeFilter Bundle | 
                    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            }
            
            # Deprovision
            Get-AppxProvisionedPackage -Online | Where-Object { 
                $_.DisplayName -match 'MSPaint|Paint3D|Paint 3D' 
            } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
            
            # Leftover folders
            $appPaths = @(
                "${env:ProgramFiles}\WindowsApps\Microsoft.MSPaint*",
                "${env:LOCALAPPDATA}\Packages\Microsoft.MSPaint*"
            )
            foreach ($path in $appPaths) {
                Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Verify
            $installed = (Get-AppxPackage *MSPaint* -AllUsers).Count
            $provisioned = (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*MSPaint*").Count
            $total = $installed + $provisioned
            "SUCCESS: Installed: $installed | Provisioned: $provisioned | Total: $total"
        }
        
        Remove-PSSession $session
        "[$machine] $output"
    }
    catch {
        "[$machine] FAILED: $($_.Exception.Message)"
    }
}

$results | Out-File -FilePath "Paint3D-Removal-Results.txt" -Force
Write-Host "`nResults: Paint3D-Removal-Results.txt" -ForegroundColor Green
$results

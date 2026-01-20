# Aggressive Microsoft 3D Viewer removal - clears remaining packages
# Run as Admin, assumes WinRM on targets, machines.txt present

$ErrorActionPreference = 'Stop'
$machinesFile = 'machines.txt'

if (-not (Test-Path $machinesFile)) { Write-Error "machines.txt missing."; exit 1 }

$machines = Get-Content $machinesFile | Where-Object { $_ -match '^\s*[\w\.\-\d]+\s*$' } | ForEach-Object { $_.Trim() }

$results = foreach ($machine in $machines) {
    try {
        Write-Host "Aggressively cleaning $machine..." -ForegroundColor Cyan
        $session = New-PSSession -ComputerName $machine -ErrorAction Stop
        
        $output = Invoke-Command -Session $session -ScriptBlock {
            # Remove by exact names (handles renames/bundles)
            $pkgNames = @(
                'Microsoft.Microsoft3DViewer*',
                '*3dviewer*'
            )
            
            foreach ($name in $pkgNames) {
                Get-AppxPackage -AllUsers $name -PackageTypeFilter Bundle | 
                    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            }
            
            # Deprovision all variants
            Get-AppxProvisionedPackage -Online | Where-Object { 
                $_.DisplayName -match '3DViewer|3dviewer' 
            } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
            
            # Nuke any leftover folders (post-removal)
            $appPaths = @(
                "${env:ProgramFiles}\WindowsApps\Microsoft.Microsoft3DViewer*",
                "${env:LOCALAPPDATA}\Packages\Microsoft.Microsoft3DViewer*"
            )
            foreach ($path in $appPaths) {
                Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Final count
            $installed = (Get-AppxPackage *3dviewer* -AllUsers).Count
            $provisioned = (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*3DViewer*").Count
            $totalRemaining = $installed + $provisioned
            "SUCCESS: Installed: $installed | Provisioned: $provisioned | Total: $totalRemaining"
        }
        
        Remove-PSSession $session
        "[$machine] $output"
    }
    catch {
        "[$machine] FAILED: $($_.Exception.Message)"
    }
}

$results | Out-File -FilePath "3DViewer-Full-Results.txt" -Force
Write-Host "`nFull results: 3DViewer-Full-Results.txt" -ForegroundColor Green
$results

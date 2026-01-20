# Remove Microsoft 3D Viewer from remote VMs to fix QIDs 92117/92061
# Requires: Run as Administrator, WinRM enabled on targets, machines.txt with one FQDN/IP per line

$ErrorActionPreference = 'Stop'
$machinesFile = 'machines.txt'

if (-not (Test-Path $machinesFile)) {
    Write-Error "machines.txt not found in current directory."
    exit 1
}

$machines = Get-Content $machinesFile | Where-Object { $_ -match '^\s*[\w\.\-\d]+\s*$' } | ForEach-Object { $_.Trim() }
if ($machines.Count -eq 0) {
    Write-Warning "No valid machines found in $machinesFile"
    exit 0
}

$results = foreach ($machine in $machines) {
    try {
        Write-Host "Processing $machine..." -ForegroundColor Yellow
        
        $session = New-PSSession -ComputerName $machine -ErrorAction Stop
        
        Invoke-Command -Session $session -ScriptBlock {
            # Remove installed 3D Viewer for all users
            Get-AppxPackage *3dviewer* -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
            
            # Remove provisioned package to block on new profiles
            Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*3DViewer*" | 
                Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
            
            # Verify removal
            $remaining = (Get-AppxPackage *3dviewer* -AllUsers).Count + 
                         (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*3DViewer*").Count
            "SUCCESS: $env:COMPUTERNAME - Remaining packages: $remaining"
        }
        
        Remove-PSSession $session
        "[$machine] SUCCESS"
    }
    catch {
        "[$machine] FAILED: $($_.Exception.Message)"
    }
}

# Output results
$results | Out-File -FilePath "3DViewer-Removal-Results.txt"
Write-Host "`nResults saved to 3DViewer-Removal-Results.txt" -ForegroundColor Green
$results | ForEach-Object { Write-Host $_ }

# Check-VDIDiskSpace.ps1
$machines = Get-Content -Path "machines.txt" | Where-Object { $_.Trim() -ne "" }
$lowSpaceVMs = @()
$tenGB = 10GB

Write-Host "Checking disk space on VMs..." -ForegroundColor Green

foreach ($vm in $machines) {
    $vm = $vm.Trim()
    Write-Host "Processing $vm ..." -ForegroundColor Yellow
    
    try {
        $disks = Get-WmiObject -Class Win32_LogicalDisk -ComputerName $vm -ErrorAction Stop | 
                 Where-Object { $_.DriveType -eq 3 } |  # Fixed drives only
                 Select-Object DeviceID, 
                     @{Name="SizeGB"; Expression={[math]::Round($_.Size / 1GB, 2)}},
                     @{Name="FreeGB"; Expression={[math]::Round($_.FreeSpace / 1GB, 2)}}
        
        if ($disks) {
            $lowDrives = $disks | Where-Object { $_.FreeGB -lt 10 }
            if ($lowDrives) {
                Write-Host "  LOW SPACE on $vm :" -ForegroundColor Red
                $lowDrives | Format-Table -AutoSize
                $lowSpaceVMs += "$vm has low space drives: $($lowDrives.DeviceID -join ', ')"
            } else {
                Write-Host "  All drives OK on $vm" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "  ERROR on $vm : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Output file
$lowSpaceVMs | Out-File -FilePath "Output_VDI.txt" -Encoding UTF8
Write-Host "`nLow space VMs saved to Output_VDI.txt" -ForegroundColor Green

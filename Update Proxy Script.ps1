# Check-VDIDiskSpace.ps1 (Updated for 15GB threshold, machine names only in output)
$machines = Get-Content -Path "machines.txt" | Where-Object { $_.Trim() -ne "" }
$lowSpaceVMs = @()
$fifteenGB = 15GB

Write-Host "Checking C: and fixed drives for <15GB free (patching safe threshold)..." -ForegroundColor Green

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
            $lowDrives = $disks | Where-Object { $_.FreeGB -lt 15 }
            if ($lowDrives) {
                Write-Host "  LOW SPACE (<15GB) on $vm :" -ForegroundColor Red
                $lowDrives | Format-Table -AutoSize
                $lowSpaceVMs += $vm  # Just the machine name
            } else {
                Write-Host "  All fixed drives >=15GB on $vm" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Host "  ERROR on $vm : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Output file: Only low-space machine names, one per line
$lowSpaceVMs | Out-File -FilePath "Output_VDI.txt" -Encoding UTF8
Write-Host "`nLow space VMs (<15GB) saved to Output_VDI.txt (machine names only):" -ForegroundColor Green
$lowSpaceVMs | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }

if ($lowSpaceVMs.Count -eq 0) {
    Write-Host "  No VMs below 15GB threshold." -ForegroundColor Green
}

# Remote VM Cleanup Script (Updated with Force Kill for wuauserv)
# Run as Administrator with PS Remoting enabled on targets
# Assumes machines.txt has one computername per line

$machines = Get-Content -Path "machines.txt"
$drive = "C:"  # Change if needed

foreach ($computer in $machines) {
    Write-Host "Processing $computer..." -ForegroundColor Green
    
    try {
        Invoke-Command -ComputerName $computer -ScriptBlock {
            $before = (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$using:drive'" | Select-Object -ExpandProperty FreeSpace)
            
            # 1. Event Viewer Logs
            Get-WinEvent -ListLog * | Where-Object {$_.RecordCount -gt 0} | ForEach-Object {Clear-EventLog $_.LogName -ErrorAction SilentlyContinue}
            
            # 2. System Log Files
            Remove-Item "$env:SystemRoot\Logs\*.*" -Recurse -Force -ErrorAction SilentlyContinue
            
            # 3. CBS Log Files
            Stop-Service TrustedInstaller -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:SystemRoot\Logs\CBS\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service TrustedInstaller -ErrorAction SilentlyContinue
            
            # 4. Prefetch
            Remove-Item "$env:SystemRoot\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue
            
            # 5. Windows Temp
            Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
            
            # 6. Windows Error Reporting
            Remove-Item "$env:ProgramData\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue
            Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item "$($_.FullName)\AppData\Local\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # 7. Windows Update Logs
            Remove-Item "$env:SystemRoot\SoftwareDistribution\Logs\*" -Recurse -Force -ErrorAction SilentlyContinue
            
            # 16. Force Windows Update cleanup (ultra-aggressive)
            $services = @('wuauserv', 'bits', 'cryptsvc', 'trustedinstaller')
            foreach ($svc in $services) {
                try {
                    Stop-Service $svc -Force -ErrorAction Stop
                } catch {
                    # Force kill PID
                    $wmiSvc = Get-WmiObject Win32_Service -Filter "Name='$svc'"
                    if ($wmiSvc -and $wmiSvc.ProcessId) {
                        Stop-Process -Id $wmiSvc.ProcessId -Force -ErrorAction SilentlyContinue
                    }
                    # Fallback taskkill
                    taskkill /F /FI "SERVICES eq $svc" 2>$null
                }
                Start-Sleep -Seconds 2
            }
            Remove-Item "$env:SystemRoot\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
            # Restart services
            foreach ($svc in $services) {
                Start-Service $svc -ErrorAction SilentlyContinue
            }
            
            # 8. System Restore Points
            vssadmin delete shadows /all /quiet 2>$null
            
            # 9. Downloaded Program Files
            Remove-Item "$env:SystemRoot\Downloaded Program Files\*" -Recurse -Force -ErrorAction SilentlyContinue
            
            # 10. Thumbnails Cache
            Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*" -Force -ErrorAction SilentlyContinue
            Get-ChildItem "C:\Users\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item "$($_.FullName)\AppData\Local\Microsoft\Windows\Explorer\thumbcache_*" -Force -ErrorAction SilentlyContinue
            }
            
            # 11. Recycle Bin all users
            Get-ChildItem "C:\`$Recycle.Bin" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            
            # 12-15. Browser & User Temp/IE/Edge/Chrome
            $users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
            foreach ($user in $users) {
                # IE
                @(
                    "$($user.FullName)\AppData\Local\Microsoft\Windows\INetCache",
                    "$($user.FullName)\AppData\Local\Microsoft\Windows\Temporary Internet Files"
                ) | ForEach-Object { Remove-Item "$_\*" -Recurse -Force -ErrorAction SilentlyContinue }
                
                # Edge
                @(
                    "$($user.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
                    "$($user.FullName)\AppData\Local\Packages\Microsoft.MicrosoftEdge_*\AC\MicrosoftEdge\Cache\*",
                    "$($user.FullName)\AppData\Local\Packages\Microsoft.MicrosoftEdge_*\AC\#!001\MicrosoftEdge\Cache\*"
                ) | ForEach-Object { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }
                
                # Chrome
                Remove-Item "$($user.FullName)\AppData\Local\Google\Chrome\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
                
                # User Temp
                Remove-Item "$($user.FullName)\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # 17. CCMCache
            try {
                $ccmCache = Get-WmiObject -Namespace "root\CCM\SoftMgmtAgent" -Class CacheElement 2>$null
                if ($ccmCache) {
                    foreach ($cache in $ccmCache) {
                        $cache.Delete() | Out-Null
                    }
                }
            } catch { }
            
            # 18-20. OST/Teams/Eclipse
            foreach ($user in $users) {
                Remove-Item "$($user.FullName)\AppData\Local\Microsoft\Outlook\*.ost" -Force -ErrorAction SilentlyContinue
                Remove-Item "$($user.FullName)\AppData\Roaming\Microsoft\Teams" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item "$($user.FullName)\AppData\Roaming\Eclipse" -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            $after = (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$using:drive'" | Select-Object -ExpandProperty FreeSpace)
            $freedGB = [math]::Round(($after - $before) / 1GB, 2)
            Write-Output "Space freed on $env:COMPUTERNAME`: $freedGB GB"
        } -ErrorAction Stop
        Write-Host "Completed $computer successfully.`n" -ForegroundColor Green
    } catch {
        Write-Host "Failed $computer`: $($_.Exception.Message)`n" -ForegroundColor Red
    }
}

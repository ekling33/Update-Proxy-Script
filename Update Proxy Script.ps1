# Remote VM Cleanup Script (WMI-Free Force Stop)
# Run as Administrator with PS Remoting enabled on targets
# machines.txt: one computername per line

$machines = Get-Content -Path "machines.txt"
$drive = "C:"

foreach ($computer in $machines) {
    Write-Host "Processing $computer..." -ForegroundColor Green
    
    try {
        Invoke-Command -ComputerName $computer -ScriptBlock {
            $before = (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$using:drive'" | Select-Object -ExpandProperty FreeSpace)
            
            # 1. Event Viewer Logs
            Get-WinEvent -ListLog * | Where-Object {$_.RecordCount -gt 0} | ForEach-Object {Clear-EventLog $_.LogName -ErrorAction SilentlyContinue}
            
            # 2-3. System/CBS Logs
            Remove-Item "$env:SystemRoot\Logs\*.*" -Recurse -Force -ErrorAction SilentlyContinue
            Stop-Service TrustedInstaller -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:SystemRoot\Logs\CBS\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service TrustedInstaller -ErrorAction SilentlyContinue
            
            # 4-6. Prefetch/Temp/WER
            Remove-Item "$env:SystemRoot\Prefetch\*" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:ProgramData\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue
            
            # 7 & 16. Windows Update (ultra-force, no WMI)
            $services = @('wuauserv', 'bits', 'cryptsvc')
            foreach ($svc in $services) {
                Stop-Service $svc -Force -ErrorAction SilentlyContinue
                taskkill /F /FI "SERVICES eq $svc" /T 2>$null | Out-Null
                Start-Sleep -Seconds 3
            }
            Remove-Item "$env:SystemRoot\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            foreach ($svc in $services) { Start-Service $svc -ErrorAction SilentlyContinue }
            
            # 8-10. Restore/Downloaded/Thumbs
            vssadmin delete shadows /all /quiet 2>$null
            Remove-Item "$env:SystemRoot\Downloaded Program Files\*" -Recurse -Force -ErrorAction SilentlyContinue
            Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer", "C:\Users\*\AppData\Local\Microsoft\Windows\Explorer" -Filter "thumbcache_*" -Force -ErrorAction SilentlyContinue | Remove-Item -Force
            
            # 11. Recycle Bin
            Remove-Item "C:\`$Recycle.Bin\*" -Recurse -Force -ErrorAction SilentlyContinue
            
            # 12-15. Browsers & User Temps (loop users once)
            $users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
            foreach ($user in $users) {
                $userTemp = "$($user.FullName)\AppData\Local\Temp\*"
                Remove-Item $userTemp -Recurse -Force -ErrorAction SilentlyContinue
                
                # IE
                Remove-Item "$($user.FullName)\AppData\Local\Microsoft\Windows\INetCache\*" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item "$($user.FullName)\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" -Recurse -Force -ErrorAction SilentlyContinue
                
                # Edge
                Remove-Item "$($user.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
                Get-ChildItem "$($user.FullName)\AppData\Local\Packages" -Filter "*MicrosoftEdge*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-Item "$($_.FullName)\AC\*\MicrosoftEdge\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
                }
                
                # Chrome
                Remove-Item "$($user.FullName)\AppData\Local\Google\Chrome\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # 17. CCMCache (try-catch safe)
            try {
                $uiRes = New-Object -ComObject UIResource.UIResourceMgr
                $cacheElements = $uiRes.GetCacheInfo().GetCacheElements()
                foreach ($elem in $cacheElements) {
                    $uiRes.GetCacheInfo().DeleteCacheElement($elem.CacheElementID) | Out-Null
                }
                [Runtime.InteropServices.Marshal]::ReleaseComObject($uiRes) | Out-Null
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

# Remote VM Cleanup Script
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
            
            # 2. System Log Files (general logs)
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
            Get-ChildItem "C:\Users\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item "$($_.FullName)\AppData\Local\Microsoft\Windows\WER\*" -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # 7. Windows Update Logs
            Remove-Item "$env:SystemRoot\SoftwareDistribution\Logs\*" -Recurse -Force -ErrorAction SilentlyContinue
            
            # 16. Old Windows Update cache (full SD)
            Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:SystemRoot\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service wuauserv, bits -ErrorAction SilentlyContinue
            
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
            
            # 12. IE Cache all users
            Get-ChildItem "C:\Users\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $iePaths = @(
                    "$($_.FullName)\AppData\Local\Microsoft\Windows\INetCache",
                    "$($_.FullName)\AppData\Local\Microsoft\Windows\Temporary Internet Files"
                )
                $iePaths | ForEach-Object { Remove-Item $_\* -Recurse -Force -ErrorAction SilentlyContinue }
            }
            
            # 13. Edge Cache all users (both classic and new)
            Get-ChildItem "C:\Users\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $edgePaths = @(
                    "$($_.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
                    "$($_.FullName)\AppData\Local\Packages\Microsoft.MicrosoftEdge_* \AC\MicrosoftEdge\Cache\*",
                    "$($_.FullName)\AppData\Local\Packages\Microsoft.MicrosoftEdge_* \AC\#!001\MicrosoftEdge\Cache\*"
                )
                $edgePaths | ForEach-Object { 
                    if (Test-Path $_) { Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue }
                }
            }
            
            # 14. Chrome Cache all users
            Get-ChildItem "C:\Users\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $chromePath = "$($_.FullName)\AppData\Local\Google\Chrome\User Data\Default\Cache"
                Remove-Item $chromePath\* -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # 15. Temp folders all profiles
            Get-ChildItem "C:\Users\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item "$($_.FullName)\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # 17. CCMCache using COM
            try {
                $CCM = New-Object -ComObject UIResource.UIResourceMgr
                $CacheInfo = $CCM.GetCacheInfo().GetCacheElements()
                foreach ($CacheItem in $CacheInfo) {
                    $CCM.GetCacheInfo().DeleteCacheElement($CacheItem.CacheElementID)
                }
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($CCM) | Out-Null
            } catch {
                # Ignore if no SCCM
            }
            
            # 18. .ost files all profiles
            Get-ChildItem "C:\Users\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item "$($_.FullName)\AppData\Local\Microsoft\Outlook\*.ost" -Force -ErrorAction SilentlyContinue
            }
            
            # 19. Teams all profiles
            Get-ChildItem "C:\Users\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item "$($_.FullName)\AppData\Roaming\Microsoft\Teams" -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # 20. Eclipse all profiles
            Get-ChildItem "C:\Users\*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item "$($_.FullName)\AppData\Roaming\Eclipse" -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            $after = (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$using:drive'" | Select-Object -ExpandProperty FreeSpace)
            $freedGB = [math]::Round(($after - $before) / 1GB, 2)
            Write-Output "Space freed on $env:COMPUTERNAME`: $freedGB GB"
        } -ErrorAction Stop
        Write-Host "Completed $computer successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to process $computer`: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

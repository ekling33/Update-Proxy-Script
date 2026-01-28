# Path to the list of target machines
$Computers = Get-Content -Path ".\machines.txt"

foreach ($Computer in $Computers) {
    Write-Host "Processing $Computer ..." -ForegroundColor Cyan
    try {
        Invoke-Command -ComputerName $Computer -ScriptBlock {
            # Get all profile directories under C:\Users
            $userProfileDirs = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue

            foreach ($dir in $userProfileDirs) {
                # Eclipse path
                $eclipsePath = Join-Path -Path $dir.FullName -ChildPath 'AppData\Roaming\Eclipse'
                if (Test-Path -Path $eclipsePath) {
                    Write-Output "Deleting Eclipse: $eclipsePath"
                    Remove-Item -Path $eclipsePath -Recurse -Force -ErrorAction SilentlyContinue
                }

                # Teams path
                $teamsPath = Join-Path -Path $dir.FullName -ChildPath 'AppData\Roaming\Microsoft\Teams'
                if (Test-Path -Path $teamsPath) {
                    Write-Output "Deleting Teams: $teamsPath"
                    Remove-Item -Path $teamsPath -Recurse -Force -ErrorAction SilentlyContinue
                }

                # All .ost files in Outlook dir
                $outlookDir = Join-Path -Path $dir.FullName -ChildPath 'AppData\Local\Microsoft\Outlook'
                if (Test-Path -Path $outlookDir) {
                    $ostFiles = Get-ChildItem -Path $outlookDir -Filter "*.ost" -File -ErrorAction SilentlyContinue
                    foreach ($ost in $ostFiles) {
                        Write-Output "Deleting OST: $($ost.FullName)"
                        Remove-Item -Path $ost.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        } -ErrorAction Stop

        # Report C: free space after deletions
        $diskInfo = Invoke-Command -ComputerName $Computer -ScriptBlock {
            $drive = Get-PSDrive -Name C
            [PSCustomObject]@{
                FreeGB = [math]::Round($drive.Free / 1GB, 2)
                TotalGB = [math]::Round($drive.Used / 1GB + $drive.Free / 1GB, 2)
                FreePercent = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 1)
            }
        }
        Write-Host "C: Free Space on $Computer : $($diskInfo.FreeGB) GB / $($diskInfo.TotalGB) GB ($($diskInfo.FreePercent)% free)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed on $Computer : $($_.Exception.Message)"
    }
}

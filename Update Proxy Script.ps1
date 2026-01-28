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
            }
        } -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed on $Computer : $($_.Exception.Message)"
    }
}

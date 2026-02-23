# Enhanced PowerShell: Check Blue Prism Edge Extension + Registry across users
# Run as Admin

$edgeExtBase = "\AppData\Local\Microsoft\Edge\User Data"
$bluePrismIDs = @("hekghghgjpohegdkkakdkgpcgelmemkk", "gienmpaoakaajldgdjpoamkldclcgbni", "cnfofffmelggnbmkejhffmhakppdjiib")  # 6.10, BAA v2, 6.9
$blueKeywords = @("blue prism", "blueprism", "baa", "browser automation")

$allResults = @()

# Get local users
$users = Get-LocalUser | Where-Object { $_.Enabled -eq $true } | Select-Object -ExpandProperty Name

foreach ($user in $users) {
    $userPath = "C:\Users\$user"
    if (Test-Path $userPath) {
        # Check registry for extension auto-install (HKLM first, then HKCU)
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Edge\Extensions",
            "HKCU:\SOFTWARE\Microsoft\Edge\Extensions"
        )
        $regFound = $false
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $exts = Get-ChildItem $regPath -ErrorAction SilentlyContinue
                foreach ($ext in $exts) {
                    $updateUrl = (Get-ItemProperty "$regPath\$($ext.PSChildName)" -Name "update_url" -ErrorAction SilentlyContinue).update_url
                    if ($bluePrismIDs -contains $ext.PSChildName -or $updateUrl -like "*blueprism*") {
                        $allResults += [PSCustomObject]@{ User = $user; Type = "Registry"; Location = $regPath + "\" + $ext.PSChildName; Found = "Yes (Auto-install)" }
                        $regFound = $true
                    }
                }
            }
        }
        
        # Check file system: Extensions and Profiles
        $edgeUserData = Join-Path $userPath $edgeExtBase
        if (Test-Path $edgeUserData) {
            # Extensions (global-ish)
            $extDir = Join-Path $edgeUserData "Extensions"
            if (Test-Path $extDir) {
                Get-ChildItem $extDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $extId = $_.Name
                    $manifest = Join-Path $_.FullName "manifest.json"
                    if (($bluePrismIDs -contains $extId) -or (Test-Path $manifest -and (Get-Content $manifest -Raw | Select-String -Pattern "(?i)blue prism|blueprism|baa" -Quiet))) {
                        $allResults += [PSCustomObject]@{ User = $user; Type = "Extensions Folder"; Location = $_.FullName; Found = "Yes" }
                    }
                }
            }
            
            # Check profiles (Default, Profile 1, etc.)
            Get-ChildItem $edgeUserData -Directory -Filter "Default", "*Profile*" -ErrorAction SilentlyContinue | ForEach-Object {
                $profExt = Join-Path $_.FullName "Extensions"
                if (Test-Path $profExt) {
                    Get-ChildItem $profExt -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                        $extId = $_.Name
                        if ($bluePrismIDs -contains $extId) {
                            $allResults += [PSCustomObject]@{ User = $user; Type = "Profile $($_.Parent.Name)"; Location = $_.FullName; Found = "Yes" }
                        }
                    }
                }
            }
        }
    }
}

# Results
if ($allResults) {
    $allResults | Format-Table User, Type, Location, Found -AutoSize
} else {
    Write-Host "No Blue Prism traces found in files/registry." -ForegroundColor Red
    Write-Host "Sample Edge folders (first 10 per user) for manual check:" -ForegroundColor Cyan
    $users | ForEach-Object { Get-ChildItem "C:\Users\$_\AppData\Local\Microsoft\Edge\User Data" -Directory | Select-Object -First 10 | ForEach-Object { Write-Host "$_ : $($_.FullName)" } }
}

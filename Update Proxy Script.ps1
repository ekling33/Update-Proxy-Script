# PowerShell script to check Blue Prism Edge Extension across all local users
# Run as Administrator

$blueprismExtensionsPath = "C:\Users\*"
$edgeExtensionsBase = "\AppData\Local\Microsoft\Edge\User Data\Default\Extensions"
$bluePrismKeywords = @("blueprism", "Blue Prism", "bp", "cnfofffmelggnbmkejhffmhakppdjiib")  # Adjust ID if known

$results = @()

Get-ChildItem -Path $blueprismExtensionsPath -Directory | ForEach-Object {
    $userFolder = $_.FullName
    $userName = $_.Name
    $edgePath = Join-Path $userFolder $edgeExtensionsBase
    
    if (Test-Path $edgePath) {
        Get-ChildItem -Path $edgePath -Directory | ForEach-Object {
            $extFolder = $_.Name
            $extPath = $_.FullName
            $manifestPath = Join-Path $extPath "manifest.json"
            
            if (Test-Path $manifestPath) {
                $manifestContent = Get-Content $manifestPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
                
                if ($manifestContent -and ($bluePrismKeywords | Where-Object { $extFolder -like "*$_*" -or ($manifestContent.name -like "*$_*") -or ($manifestContent.description -like "*$_*") })) {
                    $results += [PSCustomObject]@{
                        User = $userName
                        ExtensionID = $extFolder
                        FullPath = $extPath
                        Name = $manifestContent.name
                        Version = $manifestContent.version
                        Found = "Yes"
                    }
                }
            }
        }
    }
}

# Output results
if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize
    Write-Host "Blue Prism Extension found in $($results.Count) user(s)." -ForegroundColor Green
} else {
    Write-Host "Blue Prism Extension not found in any user profile." -ForegroundColor Yellow
}

# Optionally export to CSV
# $results | Export-Csv -Path "BluePrismExtensions.csv" -NoTypeInformation

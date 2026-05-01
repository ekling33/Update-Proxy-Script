$machinesFile = Join-Path $PSScriptRoot 'machines.txt'
$regPath = 'SOFTWARE\Policies\Microsoft\EdgeUpdate'

if (-not (Test-Path $machinesFile)) {
    Write-Error "machines.txt was not found in $PSScriptRoot"
    exit 1
}

$machines = Get-Content $machinesFile | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }

foreach ($machine in $machines) {
    $machine = $machine.Trim()
    Write-Host "Processing $machine..."

    try {
        Invoke-Command -ComputerName $machine -ScriptBlock {
            param($path)

            if (Test-Path "Registry::HKEY_LOCAL_MACHINE\\$path") {
                Remove-Item "Registry::HKEY_LOCAL_MACHINE\\$path" -Recurse -Force
                Write-Output "Removed HKLM\\$path"
            }
            else {
                Write-Output "Registry key not found: HKLM\\$path"
            }
        } -ArgumentList $regPath -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed on $machine : $($_.Exception.Message)"
    }
}

$machines = Get-Content -Path ".\machines.txt"

$regPath = "HKLM:\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown"
$valueName = "bUpdater"
$valueData = 1
$valueType = "DWord"

foreach ($machine in $machines) {
    $machine = $machine.Trim()
    if ([string]::IsNullOrWhiteSpace($machine)) { continue }

    Write-Host "Processing $machine..."

    try {
        Invoke-Command -ComputerName $machine -ScriptBlock {
            param($regPath, $valueName, $valueData)

            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }

            New-ItemProperty -Path $regPath -Name $valueName -Value $valueData -PropertyType DWord -Force | Out-Null
            Write-Output "Updated $valueName to $valueData"
        } -ArgumentList $regPath, $valueName, $valueData -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed on $machine : $($_.Exception.Message)"
    }
}

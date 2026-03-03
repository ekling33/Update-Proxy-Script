#Requires -RunAsAdministrator
# machines.txt: one computer name per line (DNS name or IP). Lines starting with # are ignored.

$MachinesFile = Join-Path $PSScriptRoot 'machines.txt'
$RegPath      = 'HKLM:\SOFTWARE\Policies\Google\Update'

$RemoveValues = @(
    'RollbackToTargetVersion{8A}',
    'Update{8A}'
)

$SetDwordValues = @{
    'DisableAutoUpdateChecksCheckboxValue' = 1
    'AutoUpdateCheckPeriodMinutes'         = 90   # Note: correct policy name is AutoUpdateCheckPeriodMinutes
}

$Computers = Get-Content -Path $MachinesFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_ -notmatch '^\s*#' } |
    Sort-Object -Unique

$Results = Invoke-Command -ComputerName $Computers -ErrorAction Continue -ScriptBlock {
    param($RegPath, $RemoveValues, $SetDwordValues)

    $out = [ordered]@{
        ComputerName = $env:COMPUTERNAME
        Status       = 'OK'
        Details      = @()
    }

    try {
        if (-not (Test-Path -Path $RegPath)) {
            New-Item -Path $RegPath -Force | Out-Null
            $out.Details += "Created key: $RegPath"
        }

        foreach ($name in $RemoveValues) {
            if (Get-ItemProperty -Path $RegPath -Name $name -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $RegPath -Name $name -Force
                $out.Details += "Removed value: $name"
            } else {
                $out.Details += "Value not present (skip): $name"
            }
        }

        foreach ($kvp in $SetDwordValues.GetEnumerator()) {
            New-ItemProperty -Path $RegPath -Name $kvp.Key -Value ([int]$kvp.Value) -PropertyType DWord -Force | Out-Null
            $out.Details += "Set DWORD: $($kvp.Key)=$($kvp.Value)"
        }
    }
    catch {
        $out.Status  = 'FAILED'
        $out.Details += $_.Exception.Message
    }

    [pscustomobject]$out
} -ArgumentList $RegPath, $RemoveValues, $SetDwordValues

# Output to screen + CSV log
$Results | Select-Object ComputerName, Status, @{n='Details';e={$_.Details -join '; '}} | Format-Table -AutoSize
$Results | Export-Csv -NoTypeInformation -Path (Join-Path $PSScriptRoot 'RegistryUpdateResults.csv')

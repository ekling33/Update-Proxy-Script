# Clear-SCCMCache-Remote.ps1
# Reads machines.txt (one computername per line), clears SCCM cache remotely using COM object.
# Usage: .\Clear-SCCMCache-Remote.ps1 [-Days 14] [-WhatIf]

param(
    [int]$Days = 0,  # 0 = clear all; >0 = clear older than X days
    [switch]$WhatIf
)

function Clear-ClientCache {
    param([int]$CacheAgeInDays, [bool]$WhatIfMode)
    
    try {
        $UIResourceMgr = New-Object -ComObject "UIResource.UIResourceMgr" -ErrorAction Stop
        $Cache = $UIResourceMgr.GetCacheInfo()
        $CutoffDate = (Get-Date).AddDays(-$CacheAgeInDays)
        
        $CacheElements = $Cache.GetCacheElements() | Where-Object { $_.LastReferenceTime -lt $CutoffDate }
        
        if ($CacheElements.Count -eq 0) {
            Write-Output "No old cache elements found on $env:COMPUTERNAME."
            return
        }
        
        Write-Output "Found $($CacheElements.Count) old cache elements on $env:COMPUTERNAME. Cache folder: $($Cache.Location)"
        
        foreach ($Element in $CacheElements) {
            if ($WhatIfMode) {
                Write-Output "  WhatIf: Would delete $($Element.Location) (ContentID: $($Element.ContentID))"
            } else {
                $Cache.DeleteCacheElement($Element.CacheElementID)
                Write-Output "  Deleted: $($Element.Location)"
            }
        }
    } catch {
        Write-Error "Failed on $env:COMPUTERNAME`: $($_.Exception.Message)"
    }
}

# Read machines.txt
$machines = Get-Content -Path "machines.txt" | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }

foreach ($machine in $machines) {
    Write-Output "`n--- Processing $machine ---"
    if ($WhatIf) {
        Invoke-Command -ComputerName $machine -ScriptBlock ${function:Clear-ClientCache} -ArgumentList $Days, $true -ErrorAction Continue
    } else {
        Invoke-Command -ComputerName $machine -ScriptBlock ${function:Clear-ClientCache} -ArgumentList $Days -ErrorAction Continue
    }
}

#requires -RunAsAdministrator
function Clear-CMClientCache {
[CmdletBinding(SupportsShouldProcess = $true)]
param (
[string[]]$ComputerName = $env:COMPUTERNAME,
[int]$CacheAgeinDays = 0
)
function Clean-ClientCache {
param ([int]$CacheAgeinDays, [bool]$WhatIf)
$UIResourceMgr = New-Object -ComObject UIResource.UIResourceMgr
$Cache = $UIResourceMgr.GetCacheInfo()
$CacheElements = $Cache.GetCacheElements() | Where-Object {$_.LastReferenceTime -lt (Get-Date).AddDays(-$CacheAgeInDays)}
if ($CacheElements) {
foreach ($Element in $CacheElements) {
if ($WhatIf) { Write-Output "WhatIf: Would delete $($Element.Location)" }
else { $Cache.DeleteCacheElement($Element.CacheElementID) }
}
}
foreach ($Computer in $ComputerName) {
if ($PSBoundParameters.ContainsKey('WhatIf')) {
Invoke-Command -ComputerName $Computer -ScriptBlock ${function:Clean-ClientCache} -ArgumentList $CacheAgeinDays, $true
} else {
Invoke-Command -ComputerName $Computer -ScriptBlock ${function:Clean-ClientCache} -ArgumentList $CacheAgeinDays
}
}
}
Clear-CMClientCache -CacheAgeinDays 30  # Adjust days as needed; 0 clears all

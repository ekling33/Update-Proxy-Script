# Config
$VMs = Get-Content .\machines.txt
$TargetUser = "TARGETUSERNAME"  # Likely "Administrator"
$LogFile = "DisableAdmin_Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

$ScriptBlock = {
    param($User)
    $log = @()
    $log += "=== $($env:COMPUTERNAME) ==="
    
    $userObj = Get-LocalUser -Name $User -ErrorAction SilentlyContinue
    if (-not $userObj) { $log += "$User not found."; return $log }
    
    $log += "Before: $($userObj.Name) Enabled=$($userObj.Enabled), SID=$($userObj.SID.Value), Desc='$($userObj.Description)'"
    
    # Service check (rare for built-in, but thorough)
    $services = Get-CimInstance Win32_Service | Where-Object { $_.StartName -eq $User }
    if ($services) { $log += "Services: $($services.Name -join ', ') - disable services first."; return $log }
    
    if ($userObj.Enabled) {
        try {
            Disable-LocalUser -Name $User
            $log += "SUCCESS: Disabled via PowerShell."
        }
        catch {
            $null = net user $User /active:no 2>&1
            if ($LASTEXITCODE -eq 0) { $log += "SUCCESS: Disabled via 'net user'." }
            else { $log += "FAILED: $($_.Exception.Message)" }
        }
        # Verify
        $check = Get-LocalUser -Name $User
        $log += "After: Enabled=$($check.Enabled)"
    } else {
        $log += "Already disabled."
    }
    
    $log
}

# Loop VMs
foreach ($VM in $VMs) {
    if (Test-Connection $VM -Count 1 -Quiet) {
        $results = Invoke-Command -ComputerName $VM -ScriptBlock $ScriptBlock -ArgumentList $TargetUser
        $results | Out-File $LogFile -Append UTF8
        Write-Host "Processed $VM"
    } else {
        "Offline: $VM" | Out-File $LogFile -Append
    }
}
Write-Host "Log: $LogFile"

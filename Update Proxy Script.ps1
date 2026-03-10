# Config
$VMs = Get-Content .\machines.txt
$TargetUser = "TARGETUSERNAME"
$LogFile = "DeleteUser_Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

# Function for per-VM processing
$ScriptBlock = {
    param($User)
    $log = @()
    $log += "=== $($env:COMPUTERNAME) ==="
    
    $userObj = Get-LocalUser -Name $User -ErrorAction SilentlyContinue
    if (-not $userObj) {
        $log += "$User not found."
        return $log
    }
    
    $log += "User: $($userObj.Name), Enabled: $($userObj.Enabled), SID: $($userObj.SID.Value), Desc: '$($userObj.Description)'"
    
    # Check services using this account (local or domain)
    $services = Get-CimInstance -ClassName Win32_Service | Where-Object { $_.StartName -eq $User -or $_.StartName -eq ".\$User" -or $_.StartName -like "*$User*" }
    if ($services) {
        $log += "BLOCKED: Services using $User`: $($services.Name -join ', ')"
        foreach ($svc in $services) { $log += "  - $($svc.Name): $($svc.StartName) (State: $($svc.State))" }
        return $log
    }
    
    # Check sessions
    $sessions = quser 2>$null | Select-String $User
    if ($sessions) { $log += "BLOCKED: Active sessions for $User"; return $log }
    
    # Attempt delete
    try {
        Remove-LocalUser -Name $User -Confirm:$false
        $log += "SUCCESS: Deleted via PowerShell cmdlet."
    }
    catch {
        $log += "PS failed (0x$($_.Exception.HResult.ToString('X8'))): $($_.Exception.Message)"
        # Fallback net user
        $result = & net user $User /delete 2>&1
        if ($LASTEXITCODE -eq 0) {
            $log += "SUCCESS: Deleted via 'net user' fallback."
        } else {
            $log += "Net user also failed: $result"
        }
    }
    
    $log
}

# Main loop
foreach ($VM in $VMs) {
    if (Test-Connection $VM -Count 1 -Quiet) {
        try {
            $results = Invoke-Command -ComputerName $VM -ScriptBlock $ScriptBlock -ArgumentList $TargetUser
            $results | Out-File $LogFile -Append UTF8
            Write-Host "Processed $VM - see log."
        }
        catch {
            "Error on $VM`: $($_.Exception.Message)" | Out-File $LogFile -Append UTF8
            Write-Host "Failed $VM`: $($_.Exception.Message)"
        }
    } else {
        "Offline: $VM" | Out-File $LogFile -Append UTF8
    }
}

Write-Host "Full log: $LogFile"

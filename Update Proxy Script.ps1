# Remote Service Status Checker
# Assumes the original script checks a service status, e.g., "W3SVC" for IIS
# Adjust $serviceName as needed based on your script

# Prompt for admin credentials
$credential = Get-Credential -Message "Enter admin credentials for remote VMs"

# Read list of VM names/IPs (one per line)
$computers = Get-Content -Path "machines.txt" | Where-Object { $_.Trim() -ne "" }

# Original script logic converted to scriptblock
# Replace 'W3SVC' with your actual service name from the script
$serviceName = "W3SVC"

$scriptBlock = {
    param($ServiceName)
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        Write-Output "Service '$ServiceName' on $($env:COMPUTERNAME): Status = $($service.Status)"
        
        # Add any other logic from your script here, e.g.:
        # If it does more like checking processes or logs, insert here
        
    }
    catch {
        Write-Output "Error on $($env:COMPUTERNAME): $($_.Exception.Message)"
    }
}

# Run remotely on all machines, with error handling
Invoke-Command -ComputerName $computers -Credential $credential -ScriptBlock $scriptBlock -ArgumentList $serviceName -ErrorAction SilentlyContinue | 
    ForEach-Object { Write-Output $_ } |
    Export-Csv -Path "service_status_report.csv" -NoTypeInformation

Write-Host "Check service_status_report.csv for results." [web:3][web:7]

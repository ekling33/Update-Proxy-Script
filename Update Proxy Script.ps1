# Load VM list and target user
$VMs = Get-Content .\machines.txt
$TargetUser = "TARGETUSERNAME"

# Loop through VMs
foreach ($VM in $VMs) {
    try {
        if (Test-Connection $VM -Count 1 -Quiet) {
            Invoke-Command -ComputerName $VM -ScriptBlock {
                param($User)
                if (Get-LocalUser -Name $User -ErrorAction SilentlyContinue) {
                    Remove-LocalUser -Name $User -Confirm:$false
                    Write-Output "Deleted $User on $env:COMPUTERNAME"
                } else {
                    Write-Output "$User not found on $env:COMPUTERNAME"
                }
            } -ArgumentList $TargetUser
        } else {
            Write-Output "$VM offline - skipped"
        }
    }
    catch {
        Write-Output "Error on $VM`: $($_.Exception.Message)"
    }
}

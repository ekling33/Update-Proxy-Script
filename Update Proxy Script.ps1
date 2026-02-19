$machines = Get-Content .\machines.txt
foreach ($pc in $machines) {
    $status = Invoke-Command -ComputerName $pc -ScriptBlock {
        try {
            (Get-LocalUser JIMMYWILLOW).Enabled
        } catch { "NotFound" }
    } -ErrorAction SilentlyContinue
    Write-Host "$pc`: Enabled=$status"
}

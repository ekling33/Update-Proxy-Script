Invoke-Command -Session $session -ScriptBlock {
    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Google\Update",
        "HKLM:\SOFTWARE\Wow6432Node\Policies\Google\Update",
        "HKLM:\SOFTWARE\Policies\Google\Chrome\Update"  # Chrome-specific if present
    )
    
    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            # Expanded blocking keys/values (REG_DWORD=0, strings pinning versions, etc.)
            $blockingKeys = @(
                'UpdateDefault', 'AutoUpdateCheckPeriodMinutes', 'UpdatePolicy', 'DisableAutoUpdate',
                'RollbackToTargetVersion', 'TargetVersionPrefix', 'TargetChannel', 'Update',
                'TargetChannelOverride', 'TargetVersionPrefixOverride'
            )
            foreach ($key in $blockingKeys) {
                if (Get-ItemProperty -Path $path -Name $key -ErrorAction SilentlyContinue) {
                    Remove-ItemProperty -Path $path -Name $key -Force
                    Write-Output "Deleted $path\$key"
                }
            }
            
            # Set UpdateDefault=1
            New-ItemProperty -Path $path -Name 'UpdateDefault' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue
            Write-Output "Set $path\UpdateDefault to 1"
        }
    }
    
    # Restart services
    $services = @('gupdate', 'gupdatem')
    foreach ($svc in $services) {
        if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
            Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Output "Restarted $svc"
        }
    }
}

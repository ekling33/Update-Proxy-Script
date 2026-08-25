Invoke-Command -ComputerName PC-NAME-HERE -ScriptBlock {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -match 'Citrix|NetScaler|Gateway|Access'
        } |
        Select-Object DisplayName, DisplayVersion, PSChildName, UninstallString, QuietUninstallString |
        Format-List

    Get-ItemProperty 'HKLM:\SOFTWARE\Citrix\Secure Access Client' -ErrorAction SilentlyContinue |
        Format-List *
}

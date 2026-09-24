[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$ExcludeAppPool = @('DefaultAppPool')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module WebAdministration -ErrorAction Stop

do {
    $Thumbprint = Read-Host 'Enter the certificate thumbprint from Local Computer\Personal'
    $Thumbprint = ($Thumbprint -replace '\s', '').ToUpperInvariant()

    if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
        Write-Warning 'A certificate thumbprint is required.'
        $Certificate = $null
        continue
    }

    if ($Thumbprint -notmatch '^[A-F0-9]+$') {
        Write-Warning 'The thumbprint can contain only hexadecimal characters (0-9 and A-F).'
        $Certificate = $null
        continue
    }

    $Certificate = Get-Item -Path "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction SilentlyContinue

    if (-not $Certificate) {
        Write-Warning "No certificate with thumbprint '$Thumbprint' was found in Cert:\LocalMachine\My."
    }
    elseif (-not $Certificate.HasPrivateKey) {
        Write-Warning "The certificate '$Thumbprint' does not have a private key and cannot be used for IIS HTTPS."
        $Certificate = $null
    }
}
until ($Certificate)

Write-Host ''
Write-Host 'Selected certificate' -ForegroundColor Cyan
Write-Host "  Subject:      $($Certificate.Subject)"
Write-Host "  Friendly name: $($Certificate.FriendlyName)"
Write-Host "  Thumbprint:   $($Certificate.Thumbprint)"
Write-Host "  Issuer:       $($Certificate.Issuer)"
Write-Host "  Valid from:   $($Certificate.NotBefore)"
Write-Host "  Valid until:  $($Certificate.NotAfter)"
Write-Host ''

$Confirmation = Read-Host 'Use this certificate for eligible IIS HTTPS bindings? Type YES to continue'

if ($Confirmation -cne 'YES') {
    Write-Host 'No changes were made.' -ForegroundColor Yellow
    return
}

$Results = @()

Get-Website | ForEach-Object {
    $Site = $_

    # Get-Website exposes the app pool associated with the site's root application.
    $ApplicationPool = $Site.ApplicationPool

    if ([string]::IsNullOrWhiteSpace($ApplicationPool)) {
        Write-Warning "Skipping '$($Site.Name)': no application pool is configured for the site."

        $Results += [PSCustomObject]@{
            Site               = $Site.Name
            ApplicationPool    = '<Unknown>'
            BindingInformation = ''
            PreviousThumbprint = ''
            NewThumbprint      = $Thumbprint
            Status             = 'Skipped - No application pool configured'
        }

        return
    }

    # Do not touch sites whose root application uses DefaultAppPool.
    if ($ExcludeAppPool -contains $ApplicationPool) {
        Write-Host "Skipping '$($Site.Name)' because it uses excluded app pool '$ApplicationPool'." -ForegroundColor Yellow

        $Results += [PSCustomObject]@{
            Site               = $Site.Name
            ApplicationPool    = $ApplicationPool
            BindingInformation = ''
            PreviousThumbprint = ''
            NewThumbprint      = $Thumbprint
            Status             = 'Skipped - Excluded application pool'
        }

        return
    }

    $HttpsBindings = @(Get-WebBinding -Name $Site.Name -Protocol 'https')

    if ($HttpsBindings.Count -eq 0) {
        Write-Host "Skipping '$($Site.Name)': no HTTPS bindings found." -ForegroundColor DarkYellow

        $Results += [PSCustomObject]@{
            Site               = $Site.Name
            ApplicationPool    = $ApplicationPool
            BindingInformation = ''
            PreviousThumbprint = ''
            NewThumbprint      = $Thumbprint
            Status             = 'Skipped - No HTTPS bindings'
        }

        return
    }

    foreach ($Binding in $HttpsBindings) {
        $BindingInformation = $Binding.bindingInformation
        $PreviousThumbprint = $Binding.certificateHash

        $Action = "Assign certificate '$Thumbprint' to HTTPS binding '$BindingInformation'"

        if ($PSCmdlet.ShouldProcess($Site.Name, $Action)) {
            try {
                $Binding.AddSslCertificate($Thumbprint, 'My')

                Write-Host "Updated: $($Site.Name) [$ApplicationPool] -> $BindingInformation" -ForegroundColor Green

                $Results += [PSCustomObject]@{
                    Site               = $Site.Name
                    ApplicationPool    = $ApplicationPool
                    BindingInformation = $BindingInformation
                    PreviousThumbprint = $PreviousThumbprint
                    NewThumbprint      = $Thumbprint
                    Status             = 'Updated'
                }
            }
            catch {
                Write-Warning "Failed: $($Site.Name) -> $BindingInformation. $($_.Exception.Message)"

                $Results += [PSCustomObject]@{
                    Site               = $Site.Name
                    ApplicationPool    = $ApplicationPool
                    BindingInformation = $BindingInformation
                    PreviousThumbprint = $PreviousThumbprint
                    NewThumbprint      = $Thumbprint
                    Status             = "Failed - $($_.Exception.Message)"
                }
            }
        }
    }
}

Write-Host ''
Write-Host 'Summary' -ForegroundColor Cyan
Write-Host '-------'

$Results |
    Sort-Object Site, BindingInformation |
    Format-Table Site, ApplicationPool, BindingInformation, PreviousThumbprint, NewThumbprint, Status -AutoSize

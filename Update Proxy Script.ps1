<#
.SYNOPSIS
    Updates IIS HTTPS binding certificates for sites not using DefaultAppPool.

.DESCRIPTION
    Prompts for the target certificate thumbprint when the script starts.
    Skips sites whose root application uses DefaultAppPool.
    Updates existing HTTPS bindings only.
    Compatible with Windows PowerShell 5.1.

.NOTES
    Run in an elevated PowerShell console.
    The certificate must be present in Cert:\LocalMachine\My
    and include a private key.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$ExcludeAppPool = @('DefaultAppPool')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module WebAdministration -ErrorAction Stop

# Ask for a certificate thumbprint at run time.
do {
    $Thumbprint = Read-Host 'Enter the certificate thumbprint from Local Computer\Personal'

    # Remove normal spaces, non-breaking spaces, and other pasted whitespace.
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

# This is a final check before changing IIS.
$Confirmation = Read-Host 'Use this certificate for eligible IIS HTTPS bindings? Type YES to continue'

if ($Confirmation -cne 'YES') {
    Write-Host 'No changes were made.' -ForegroundColor Yellow
    return
}

$Results = @()

Get-Website | ForEach-Object {
    $Site = $_

    # Identify the app pool assigned to the root application ("/") of the IIS site.
    $RootApplication = Get-WebApplication -Site $Site.Name |
        Where-Object { $_.Path -eq '/' } |
        Select-Object -First 1

    if (-not $RootApplication) {
        Write-Warning "Skipping '$($Site.Name)': unable to identify its root application pool."

        $Results += [PSCustomObject]@{
            Site               = $Site.Name
            ApplicationPool    = '<Unknown>'
            BindingInformation = ''
            PreviousThumbprint = ''
            NewThumbprint      = $Thumbprint
            Status             = 'Skipped - Root application not found'
        }

        return
    }

    $ApplicationPool = $RootApplication.ApplicationPool

    # Skip a site when its root application uses DefaultAppPool.
    if ($ExcludeAppPool -contains $ApplicationPool) {
        Write-Host "Skipping '$($Site.Name)' because its root app pool is '$ApplicationPool'." -ForegroundColor Yellow

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
            Status             = 'Skipped - No HTTPS binding'
        }

        return
    }

    foreach ($Binding in $HttpsBindings) {
        $BindingInformation = $Binding.bindingInformation
        $PreviousThumbprint = $Binding.certificateHash

        $Action = "Assign certificate '$Thumbprint' to HTTPS binding '$BindingInformation'"

        if ($PSCmdlet.ShouldProcess($Site.Name, $Action)) {
            try {
                # IIS certificate bindings use the Local Computer Personal store: "My".
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

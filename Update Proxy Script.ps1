##Step 1:

# Create self-signed certificate
$cert = New-SelfSignedCertificate `
  -DnsName $env:COMPUTERNAME, "localhost" `
  -CertStoreLocation "cert:\LocalMachine\My" `
  -KeyUsage DigitalSignature, KeyEncipherment `
  -ExtentionList @("2.5.29.17") `
  -NotAfter (Get-Date).AddYears(2)

  ##Step 2:
  # Add certificate to Trusted Root Certification Authorities
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store `
  -ArgumentList Root, LocalMachine
$rootStore.Open("MaxAllowed")
$rootStore.Add($cert)
$rootStore.Close()

##Step 3:

# Get the thumbprint (needed for Blue Prism configuration)
$cert.Thumbprint

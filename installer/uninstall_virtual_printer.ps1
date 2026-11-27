param(
  [string]$CertificatePath
)
$ErrorActionPreference = "Stop"

$package = Get-AppxPackage -Name "XP323B.VirtualPrinter"
if ($package) {
  Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
  Write-Host "Removed XP-P323B Virtual Printer package."
}

# Remove only the test-signing certificate shipped with this installation.
# The uninstall entry runs before Inno Setup deletes the application directory.
if (-not [string]::IsNullOrWhiteSpace($CertificatePath) -and
    (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
  $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
  if ($certificate.Subject -eq "CN=XP-P323B") {
    $trusted = Get-ChildItem -Path "Cert:\LocalMachine\TrustedPeople" |
      Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
    if ($trusted) {
      Remove-Item -LiteralPath ("Cert:\LocalMachine\TrustedPeople\" + $certificate.Thumbprint) -Force
      Write-Host "Removed the XP-P323B test-signing certificate from LocalMachine\TrustedPeople."
    }
  }
}

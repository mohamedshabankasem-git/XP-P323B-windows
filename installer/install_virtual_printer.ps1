param(
  [Parameter(Mandatory = $true)][string]$MsixPath,
  [Parameter(Mandatory = $true)][string]$CertificatePath
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $MsixPath -PathType Leaf)) { throw "Signed virtual-printer MSIX not found: $MsixPath" }
if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) { throw "Package signing certificate not found: $CertificatePath" }
$certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
if ($certificate.Subject -ne "CN=XP-P323B") { throw "Unexpected package certificate subject: $($certificate.Subject)" }
$thumbprint = $certificate.Thumbprint
$existing = Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object Thumbprint -eq $thumbprint
if (-not $existing) {
  Import-Certificate -FilePath $CertificatePath -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
}
Add-AppxPackage -Path $MsixPath -ErrorAction Stop
$package = Get-AppxPackage -Name "XP323B.VirtualPrinter"
if (-not $package) { throw "Windows did not register the XP-P323B virtual-printer package." }
Write-Host "Installed $($package.PackageFullName)"

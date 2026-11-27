param([Parameter(Mandatory = $true)][string]$MsixPath)
$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $MsixPath -PathType Leaf)) { throw "Signed virtual-printer MSIX not found: $MsixPath" }
Add-AppxPackage -Path $MsixPath -ErrorAction Stop
$package = Get-AppxPackage -Name "XP323B.VirtualPrinter"
if (-not $package) { throw "Windows did not register the XP-P323B virtual-printer package." }
Write-Host "Installed $($package.PackageFullName)"

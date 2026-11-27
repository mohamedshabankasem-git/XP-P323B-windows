$ErrorActionPreference = "Stop"
$package = Get-AppxPackage -Name "XP323B.VirtualPrinter"
if ($package) {
  Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
  Write-Host "Removed XP-P323B Virtual Printer package."
}

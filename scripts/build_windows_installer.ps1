param([Parameter(Mandatory = $true)][string]$MsixPath)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$flutterRelease = Join-Path $repoRoot "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $flutterRelease "xp_p323b_windows.exe"))) { throw "Build the Flutter Windows release first." }
if (-not (Test-Path -LiteralPath $MsixPath -PathType Leaf)) { throw "MSIX file not found: $MsixPath" }
if ([string]::IsNullOrWhiteSpace($env:XP_P323B_SIGNING_PFX_BASE64) -or [string]::IsNullOrWhiteSpace($env:XP_P323B_SIGNING_PFX_PASSWORD)) {
  throw "A code-signing PFX is required. For CI testing, generate a temporary CN=XP-P323B certificate first."
}
$payload = Join-Path $PSScriptRoot "..\installer\payload"
New-Item -ItemType Directory -Force -Path $payload | Out-Null
$signedMsix = Join-Path $payload "XP-P323B.VirtualPrinter.msix"
Copy-Item -LiteralPath $MsixPath -Destination $signedMsix -Force
$tempPfx = Join-Path ([System.IO.Path]::GetTempPath()) ("xp323b-signing-" + [guid]::NewGuid().ToString("N") + ".pfx")
try {
  [IO.File]::WriteAllBytes($tempPfx, [Convert]::FromBase64String($env:XP_P323B_SIGNING_PFX_BASE64))
  $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    $tempPfx, $env:XP_P323B_SIGNING_PFX_PASSWORD,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
  if ($certificate.Subject -ne "CN=XP-P323B") { throw "Certificate subject must exactly match package Publisher CN=XP-P323B. Actual: $($certificate.Subject)" }
  if (-not $certificate.HasPrivateKey) { throw "The PFX does not contain a private signing key." }
  $publicCertPath = Join-Path $payload "XP-P323B-TestSigning.cer"
  [IO.File]::WriteAllBytes($publicCertPath, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
  $certificate.Dispose()
  $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
  $kits = Join-Path $programFilesX86 "Windows Kits\10\bin"
  $signtool = Get-ChildItem -Path $kits -Filter signtool.exe -Recurse -ErrorAction Stop |
    Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
  if (-not $signtool) { throw "Windows SDK signtool.exe was not found." }
  & $signtool sign /fd SHA256 /f $tempPfx /p $env:XP_P323B_SIGNING_PFX_PASSWORD /tr http://timestamp.digicert.com /td SHA256 $signedMsix
  if ($LASTEXITCODE -ne 0) { throw "MSIX signing failed." }
  & $signtool verify /pa /v $signedMsix
  if ($LASTEXITCODE -ne 0) { throw "MSIX signature verification failed." }
}
finally { if (Test-Path $tempPfx) { Remove-Item -LiteralPath $tempPfx -Force } }
$iscc = Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
  $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($command) { $iscc = $command.Source }
}
if (-not (Test-Path $iscc)) { throw "Inno Setup 6 (ISCC.exe) was not found." }
Push-Location $PSScriptRoot
try { & $iscc "XP-P323B.iss"; if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed." } }
finally { Pop-Location }
$setup = Join-Path $repoRoot "dist\XP-P323B-Setup.exe"
if (-not (Test-Path $setup -PathType Leaf) -or (Get-Item $setup).Length -lt 1MB) { throw "Setup.exe is missing or unexpectedly small." }
Write-Host "Created $setup"

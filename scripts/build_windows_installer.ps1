param([Parameter(Mandatory = $true)][string]$MsixPath)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$flutterRelease = Join-Path $repoRoot "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $flutterRelease "xp_p323b_windows.exe"))) { throw "Build the Flutter Windows release first." }
if (-not (Test-Path -LiteralPath $MsixPath -PathType Leaf)) { throw "MSIX file not found: $MsixPath" }
if ([string]::IsNullOrWhiteSpace($env:XP_P323B_SIGNING_PFX_BASE64) -or [string]::IsNullOrWhiteSpace($env:XP_P323B_SIGNING_PFX_PASSWORD)) {
  throw "Set XP_P323B_SIGNING_PFX_BASE64 and XP_P323B_SIGNING_PFX_PASSWORD to a trusted code-signing certificate. No self-signed trust is created."
}
$payload = Join-Path $PSScriptRoot "..\installer\payload"
New-Item -ItemType Directory -Force -Path $payload | Out-Null
$signedMsix = Join-Path $payload "XP-P323B.VirtualPrinter.msix"
Copy-Item -LiteralPath $MsixPath -Destination $signedMsix -Force
$tempPfx = Join-Path ([System.IO.Path]::GetTempPath()) ("xp323b-signing-" + [guid]::NewGuid().ToString("N") + ".pfx")
try {
  [IO.File]::WriteAllBytes($tempPfx, [Convert]::FromBase64String($env:XP_P323B_SIGNING_PFX_BASE64))
  $securePassword = ConvertTo-SecureString $env:XP_P323B_SIGNING_PFX_PASSWORD -AsPlainText -Force
  $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    $tempPfx, $securePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
  if ($certificate.Subject -ne "CN=XP-P323B") {
    throw "Signing certificate subject must exactly match the package Publisher CN=XP-P323B. Actual: $($certificate.Subject)"
  }
  if (-not $certificate.HasPrivateKey) { throw "The PFX does not contain a private signing key." }
  $certificate.Dispose()
  $kits = Join-Path $env:ProgramFiles(x86) "Windows Kits\10\bin"
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
$iscc = Join-Path $env:ProgramFiles(x86) "Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
  $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($command) { $iscc = $command.Source }
}
if (-not (Test-Path $iscc)) { throw "Inno Setup 6 (ISCC.exe) was not found." }
Push-Location $PSScriptRoot
try { & $iscc "XP-P323B.iss"; if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed." } }
finally { Pop-Location }
Write-Host "Created signed XP-P323B Setup.exe."

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
$importedCertificate = $null
$trustedRootCertificate = $null
try {
  [IO.File]::WriteAllBytes($tempPfx, [Convert]::FromBase64String($env:XP_P323B_SIGNING_PFX_BASE64))
  $password = ConvertTo-SecureString -String $env:XP_P323B_SIGNING_PFX_PASSWORD -AsPlainText -Force
  # Persist the private key in the Windows certificate store; SignTool's PFX loader
  # was failing with 0x8007000b on the hosted runner.
  $importedCertificate = Import-PfxCertificate -FilePath $tempPfx -CertStoreLocation "Cert:\CurrentUser\My" -Password $password -Exportable
  if (-not $importedCertificate) { throw "Could not import the MSIX signing certificate into CurrentUser\My." }
  $certificate = Get-Item -LiteralPath ("Cert:\CurrentUser\My\" + $importedCertificate.Thumbprint)
  if ($certificate.Subject -cne "CN=XP-P323B") { throw "Certificate subject must exactly match package Publisher CN=XP-P323B. Actual: $($certificate.Subject)" }
  if (-not $certificate.HasPrivateKey) { throw "The imported certificate does not contain a private signing key." }
  if ($certificate.PublicKey.Oid.Value -ne "1.2.840.113549.1.1.1") { throw "MSIX test signing requires an RSA certificate." }
  $codeSigningEku = $certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.37" }
  $hasCodeSigningEku = $false
  if ($codeSigningEku) {
    $ekuExtension = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($codeSigningEku, $codeSigningEku.Critical)
    $hasCodeSigningEku = @($ekuExtension.EnhancedKeyUsages | Where-Object { $_.Value -eq "1.3.6.1.5.5.7.3.3" }).Count -gt 0
  }
  if (-not $hasCodeSigningEku) { throw "The signing certificate is missing the Code Signing EKU (1.3.6.1.5.5.7.3.3)." }
  $certificateSubject = $certificate.Subject
  $thumbprint = $certificate.Thumbprint
  $publicCertPath = Join-Path $payload "XP-P323B-TestSigning.cer"
  [IO.File]::WriteAllBytes($publicCertPath, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
  $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
  $kits = Join-Path $programFilesX86 "Windows Kits\10\bin"
  $signtool = Get-ChildItem -Path $kits -Filter signtool.exe -Recurse -ErrorAction Stop |
    Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
  if (-not $signtool) { throw "Windows SDK signtool.exe was not found." }
  Write-Host "Signing MSIX with certificate-store key: $certificateSubject ($thumbprint)"
  & $signtool sign /debug /v /fd SHA256 /sha1 $thumbprint /s My $signedMsix
  if ($LASTEXITCODE -ne 0) {
    $signExitCode = $LASTEXITCODE
    Write-Host "SignTool failed with exit code $signExitCode. Collecting current MSIX packaging diagnostics."
    # Microsoft documents Event IDs 150, 151 and 152 as the actionable causes
    # commonly wrapped by SignerSign 0x8007000B (publisher, block-map hash, content).
    $since = (Get-Date).AddMinutes(-10)
    $appxLogs = Get-WinEvent -ListLog "*AppxPackaging*" -ErrorAction SilentlyContinue |
      Where-Object { $_.IsEnabled -and $_.RecordCount -gt 0 }
    foreach ($log in $appxLogs) {
      Write-Host "---- Event log: $($log.LogName) ----"
      try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = $log.LogName; StartTime = $since } -ErrorAction Stop |
          Where-Object { $_.Level -le 2 -or $_.Id -in @(150,151,152) } |
          Select-Object -First 30 TimeCreated, Id, LevelDisplayName, Message
        if ($events) { $events | Format-List | Out-String | Write-Host }
        else { Write-Host "No recent error or actionable MSIX packaging events in this log." }
      } catch { Write-Warning "Could not read $($log.LogName): $($_.Exception.Message)" }
    }
    # Print package metadata next to the event details to distinguish certificate
    # publisher mismatch from block-map/hash or package-content problems.
    try {
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      $zip = [System.IO.Compression.ZipFile]::OpenRead($signedMsix)
      try {
        $manifestEntry = $zip.GetEntry("AppxManifest.xml")
        $blockMapEntry = $zip.GetEntry("AppxBlockMap.xml")
        if ($manifestEntry) {
          $reader = [IO.StreamReader]::new($manifestEntry.Open())
          try { [xml]$packageManifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
          Write-Host "MSIX manifest Publisher: $($packageManifest.Package.Identity.Publisher)"
        }
        if ($blockMapEntry) {
          $reader = [IO.StreamReader]::new($blockMapEntry.Open())
          try { [xml]$blockMap = $reader.ReadToEnd() } finally { $reader.Dispose() }
          Write-Host "MSIX block-map HashMethod: $($blockMap.BlockMap.HashMethod)"
        }
      } finally { $zip.Dispose() }
    } catch { Write-Warning "Could not inspect MSIX manifest/block map: $($_.Exception.Message)" }
    throw "MSIX signing failed (SignTool exit code $signExitCode). See SignTool debug output and AppxPackaging events above."
  }
  # The CI certificate is intentionally self-signed. Trust its public certificate
  # in the current user's Root store only for this verification step, then remove it.
  # The installed product separately places the public certificate in LocalMachine\\TrustedPeople.
  $trustedRootCertificate = Import-Certificate -FilePath $publicCertPath -CertStoreLocation "Cert:\CurrentUser\Root"
  if (-not $trustedRootCertificate) { throw "Could not trust the temporary test certificate for CI signature verification." }
  & $signtool verify /pa /v $signedMsix
  if ($LASTEXITCODE -ne 0) { throw "MSIX signature verification failed even after trusting the temporary CI certificate." }
}
finally {
  if ($trustedRootCertificate) {
    Remove-Item -LiteralPath ("Cert:\CurrentUser\Root\\" + $trustedRootCertificate.Thumbprint) -Force -ErrorAction SilentlyContinue
  }
  if ($importedCertificate) { Remove-Item -LiteralPath ("Cert:\CurrentUser\My\" + $importedCertificate.Thumbprint) -Force -ErrorAction SilentlyContinue }
  if (Test-Path $tempPfx) { Remove-Item -LiteralPath $tempPfx -Force }
}
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

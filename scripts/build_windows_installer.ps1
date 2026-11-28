param([Parameter(Mandatory = $true)][string]$MsixPath)
$ErrorActionPreference = "Stop"

function Write-Stage {
  param([string]$Message)
  Write-Host ("[{0}] {1}" -f (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"), $Message)
}

function Quote-ProcessArgument {
  param([string]$Value)
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-ExternalProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$Stage,
    [Parameter(Mandatory = $true)][int]$TimeoutMinutes
  )
  $logRoot = Join-Path ([IO.Path]::GetTempPath()) ("xp323b-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
  $stdout = Join-Path $logRoot "stdout.log"
  $stderr = Join-Path $logRoot "stderr.log"
  $argumentLine = ($Arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join " "
  $started = Get-Date
  Write-Stage ("START {0}; timeout={1}m; executable={2}" -f $Stage, $TimeoutMinutes, $FilePath)
  Write-Stage ("ARGS {0}" -f $argumentLine)
  try {
    $process = Start-Process -FilePath $FilePath -ArgumentList $argumentLine -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $deadline = $started.AddMinutes($TimeoutMinutes)
    $nextHeartbeat = $started.AddSeconds(30)
    while (-not $process.HasExited) {
      if ((Get-Date) -ge $deadline) {
        Write-Stage ("TIMEOUT {0}; stopping process id {1}" -f $Stage, $process.Id)
        try { $process.Kill() } catch { Write-Warning ("Could not stop process {0}: {1}" -f $process.Id, $_.Exception.Message) }
        try { $process.WaitForExit(15000) | Out-Null } catch {}
        if (-not $process.HasExited) { throw ("{0} exceeded its {1}-minute timeout and could not be stopped." -f $Stage, $TimeoutMinutes) }
        throw ("{0} exceeded its {1}-minute timeout." -f $Stage, $TimeoutMinutes)
      }
      if ((Get-Date) -ge $nextHeartbeat) {
        $elapsed = [int]((Get-Date) - $started).TotalSeconds
        Write-Stage ("RUNNING {0}; elapsed={1}s; processId={2}" -f $Stage, $elapsed, $process.Id)
        $nextHeartbeat = (Get-Date).AddSeconds(30)
      }
      Start-Sleep -Seconds 2
      $process.Refresh()
    }
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    if (Test-Path $stdout) { Get-Content -LiteralPath $stdout -Tail 120 | ForEach-Object { Write-Host $_ } }
    if (Test-Path $stderr) { Get-Content -LiteralPath $stderr -Tail 120 | ForEach-Object { Write-Host $_ } }
    $duration = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    Write-Stage ("END {0}; exitCode={1}; duration={2}s" -f $Stage, $exitCode, $duration)
    if ($exitCode -ne 0) { throw ("{0} failed with exit code {1}." -f $Stage, $exitCode) }
  }
  finally { Remove-Item -LiteralPath $logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

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
$stageStarted = Get-Date

try {
  Write-Stage "START Import and validate temporary signing certificate"
  [IO.File]::WriteAllBytes($tempPfx, [Convert]::FromBase64String($env:XP_P323B_SIGNING_PFX_BASE64))
  $password = ConvertTo-SecureString -String $env:XP_P323B_SIGNING_PFX_PASSWORD -AsPlainText -Force
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
  Write-Stage ("END Import and validate temporary signing certificate; duration={0}s; subject={1}; thumbprint={2}" -f [math]::Round(((Get-Date) - $stageStarted).TotalSeconds, 1), $certificateSubject, $thumbprint)

  $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
  $kits = Join-Path $programFilesX86 "Windows Kits\10\bin"
  Write-Stage "Searching Windows SDK for x64 SignTool"
  $signtool = Get-ChildItem -Path $kits -Filter signtool.exe -Recurse -ErrorAction Stop | Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
  if (-not $signtool) { throw "Windows SDK signtool.exe was not found." }

  Write-Stage ("START Sign MSIX; certificate={0} ({1})" -f $certificateSubject, $thumbprint)
  & $signtool sign /debug /v /fd SHA256 /sha1 $thumbprint /s My $signedMsix
  $signExitCode = $LASTEXITCODE
  Write-Stage ("END Sign MSIX; exitCode={0}" -f $signExitCode)
  if ($signExitCode -ne 0) {
    Write-Host "SignTool failed. Collecting recent MSIX packaging diagnostics."
    $since = (Get-Date).AddMinutes(-10)
    $appxLogs = Get-WinEvent -ListLog "*AppxPackaging*" -ErrorAction SilentlyContinue | Where-Object { $_.IsEnabled -and $_.RecordCount -gt 0 }
    foreach ($log in $appxLogs) {
      Write-Host "---- Event log: $($log.LogName) ----"
      try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = $log.LogName; StartTime = $since } -ErrorAction Stop | Where-Object { $_.Level -le 2 -or $_.Id -in @(150,151,152) } | Select-Object -First 30 TimeCreated, Id, LevelDisplayName, Message
        if ($events) { $events | Format-List | Out-String | Write-Host } else { Write-Host "No recent error or actionable MSIX packaging events in this log." }
      } catch { Write-Warning "Could not read $($log.LogName): $($_.Exception.Message)" }
    }
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

  $certutil = Join-Path $env:SystemRoot "System32\certutil.exe"
  if (-not (Test-Path -LiteralPath $certutil -PathType Leaf)) { throw "Windows certutil.exe was not found." }

  Write-Stage "START Add temporary signing certificate to CurrentUser Root (60-second timeout)"
  Invoke-ExternalProcess -FilePath $certutil -Arguments @("-user", "-addstore", "-f", "Root", $publicCertPath) -Stage "Trust temporary certificate for CI signature verification" -TimeoutMinutes 1
  $trustedRootCertificate = $true
  Write-Stage "END Add temporary signing certificate to CurrentUser Root"

  Invoke-ExternalProcess -FilePath $signtool -Arguments @("verify", "/pa", "/v", $signedMsix) -Stage "Verify signed MSIX" -TimeoutMinutes 3
}
finally {
  Write-Stage "START Remove temporary signing certificates and PFX"
  if ($trustedRootCertificate -and $thumbprint) {
    try {
      $certutil = Join-Path $env:SystemRoot "System32\certutil.exe"
      Invoke-ExternalProcess -FilePath $certutil -Arguments @("-user", "-delstore", "Root", $thumbprint) -Stage "Remove temporary certificate from CurrentUser Root" -TimeoutMinutes 1
    } catch { Write-Warning ("Could not remove temporary Root certificate: {0}" -f $_.Exception.Message) }
  }
  if ($importedCertificate) { Remove-Item -LiteralPath ("Cert:\CurrentUser\My\" + $importedCertificate.Thumbprint) -Force -ErrorAction SilentlyContinue }
  if (Test-Path $tempPfx) { Remove-Item -LiteralPath $tempPfx -Force -ErrorAction SilentlyContinue }
  Write-Stage "END Remove temporary signing certificates and PFX"
}

$iscc = Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
  $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($command) { $iscc = $command.Source }
}
if (-not (Test-Path $iscc)) { throw "Inno Setup 6 (ISCC.exe) was not found." }
$setup = Join-Path $repoRoot "dist\XP-P323B-Setup.exe"
$dist = Split-Path -Parent $setup
New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $setup) { Remove-Item -LiteralPath $setup -Force }
$releaseBytes = (Get-ChildItem -LiteralPath $flutterRelease -File -Recurse | Measure-Object -Property Length -Sum).Sum
$msixBytes = (Get-Item -LiteralPath $signedMsix).Length
Write-Stage ("Installer input sizes: FlutterRelease={0:N1} MB; MSIX={1:N1} MB" -f ($releaseBytes / 1MB), ($msixBytes / 1MB))

Push-Location $PSScriptRoot
try { Invoke-ExternalProcess -FilePath $iscc -Arguments @("XP-P323B.iss") -Stage "Compile Inno Setup installer" -TimeoutMinutes 25 }
finally { Pop-Location }

if (-not (Test-Path $setup -PathType Leaf) -or (Get-Item $setup).Length -lt 1MB) { throw "Setup.exe is missing or unexpectedly small." }
Write-Stage ("SUCCESS Created {0}; size={1:N1} MB" -f $setup, ((Get-Item $setup).Length / 1MB))

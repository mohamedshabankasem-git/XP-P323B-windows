$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot "generate_virtual_printer_assets.ps1")
if ($LASTEXITCODE -ne 0) {
  throw "Virtual printer asset generation failed."
}

$solution = Join-Path $repoRoot "windows-virtual-printer\PrintSupportApp\XP323B.VirtualPrinter.sln"
if (-not (Test-Path $solution)) {
  throw "Virtual printer solution was not found: $solution"
}

$vswhere = Join-Path $env:ProgramFiles(x86) "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
  throw "Visual Studio Installer (vswhere.exe) was not found."
}
$msbuild = & $vswhere -latest -products * -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
if (-not $msbuild -or -not (Test-Path $msbuild)) {
  throw "MSBuild was not found. Install Visual Studio 2026 with MSIX and Windows App SDK tools."
}

& $msbuild $solution /restore /m /p:Configuration=Release /p:Platform=x64 /p:AppxPackageSigningEnabled=false
if ($LASTEXITCODE -ne 0) {
  throw "Virtual printer MSIX build failed with exit code $LASTEXITCODE."
}

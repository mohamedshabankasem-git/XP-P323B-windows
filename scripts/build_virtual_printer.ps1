$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot "generate_virtual_printer_assets.ps1")

$solution = Join-Path $repoRoot "windows-virtual-printer\PrintSupportApp\XP323B.VirtualPrinter.sln"
if (-not (Test-Path $solution)) {
  throw "Virtual printer solution was not found: $solution"
}

$programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
if ([string]::IsNullOrWhiteSpace($programFilesX86)) {
  throw "The 32-bit Program Files directory could not be resolved."
}
$vswhere = Join-Path $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
  throw "Visual Studio Installer (vswhere.exe) was not found."
}
$msbuild = & $vswhere -latest -products '*' -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
if (-not $msbuild -or -not (Test-Path $msbuild)) {
  throw "MSBuild was not found. Install Visual Studio 2026 with MSIX and Windows App SDK tools."
}

$packageOutput = Join-Path $repoRoot "artifacts\\VirtualPrinterPackages\\"
New-Item -ItemType Directory -Force -Path $packageOutput | Out-Null

# A normal Build compiles the WinUI app but does not create an MSIX.
# GenerateAppxPackageOnBuild is required for the single-project MSIX output.
& $msbuild $solution /restore /m /p:Configuration=Release /p:Platform=x64 /p:AppxPackageSigningEnabled=false /p:GenerateAppxPackageOnBuild=true /p:UapAppxPackageBuildMode=SideloadOnly /p:AppxBundle=Never "/p:AppxPackageDir=$packageOutput"
if ($LASTEXITCODE -ne 0) {
  throw "Virtual printer MSIX build failed with exit code $LASTEXITCODE."
}

$packages = Get-ChildItem -Path $packageOutput -Filter *.msix -Recurse -File
if (-not $packages) {
  throw "MSBuild completed but did not generate an MSIX package in $packageOutput."
}
$packages | ForEach-Object { Write-Host "Generated MSIX: $($_.FullName)" }

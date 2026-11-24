$ErrorActionPreference = "Stop"

$runnerDir = Join-Path $PSScriptRoot "..\windows\runner"
$cmakePath = Join-Path $runnerDir "CMakeLists.txt"
$windowPath = Join-Path $runnerDir "flutter_window.cpp"

if (-not (Test-Path $cmakePath) -or -not (Test-Path $windowPath)) {
  throw "Flutter Windows runner files were not generated."
}

$cmake = Get-Content -Raw $cmakePath
if ($cmake -notmatch '"xp_printer_bridge.cpp"') {
  $needle = '  "flutter_window.cpp"'
  if (-not $cmake.Contains($needle)) { throw "Could not locate flutter_window.cpp in runner CMakeLists." }
  $cmake = $cmake.Replace($needle, $needle + "`r`n  `"xp_printer_bridge.cpp`"")
  Set-Content -Path $cmakePath -Value $cmake -Encoding utf8
}

if ($cmake -notmatch 'winspool\.lib') {
  Add-Content -Path $cmakePath -Value "`r`ntarget_link_libraries(`${BINARY_NAME} PRIVATE winspool.lib advapi32.lib)`r`n" -Encoding utf8
}

$window = Get-Content -Raw $windowPath
if ($window -notmatch '#include "xp_printer_bridge.h"') {
  $window = $window.Replace('#include "flutter_window.h"', '#include "flutter_window.h"' + "`r`n`r`n#include `"xp_printer_bridge.h`"")
}
if ($window -notmatch 'RegisterXpPrinterBridge') {
  $needle = '  RegisterPlugins(flutter_controller_->engine());'
  if (-not $window.Contains($needle)) { throw "Could not locate RegisterPlugins in flutter_window.cpp." }
  $window = $window.Replace($needle, $needle + "`r`n  RegisterXpPrinterBridge(flutter_controller_->engine()->messenger());")
}
Set-Content -Path $windowPath -Value $window -Encoding utf8

Write-Host "XP-P323B native Windows bridge integrated into generated Flutter runner."

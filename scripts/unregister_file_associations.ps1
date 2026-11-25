$ErrorActionPreference = 'Stop'
$progId = 'XP.P323B.PrintDocument'
$classes = 'HKCU:\Software\Classes'
$extensions = @('.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tif', '.tiff', '.pdf', '.txt', '.csv', '.log')

foreach ($extension in $extensions) {
  $key = "$classes\$extension\OpenWithProgids"
  if (Test-Path $key) {
    Remove-ItemProperty -Path $key -Name $progId -ErrorAction SilentlyContinue
  }
}
Remove-Item -Path "$classes\$progId" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$classes\Applications\xp_p323b_windows.exe" -Recurse -Force -ErrorAction SilentlyContinue
$sendTo = [Environment]::GetFolderPath('SendTo')
Remove-Item -Path (Join-Path $sendTo 'Print with XP-P323B.lnk') -Force -ErrorAction SilentlyContinue
Write-Host 'XP-P323B file associations removed.'

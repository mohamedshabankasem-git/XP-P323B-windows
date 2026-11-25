param(
  [Parameter(Mandatory = $true)]
  [string]$ExePath
)

$ErrorActionPreference = 'Stop'
$resolvedExe = (Resolve-Path $ExePath).Path
$exeName = [System.IO.Path]::GetFileName($resolvedExe)
$progId = 'XP.P323B.PrintDocument'
$displayName = 'XP-P323B Printer'
$extensions = @('.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tif', '.tiff', '.pdf', '.txt', '.csv', '.log')
$classes = 'HKCU:\Software\Classes'

New-Item -Path "$classes\$progId\shell\open\command" -Force | Out-Null
Set-Item -Path "$classes\$progId" -Value $displayName
Set-Item -Path "$classes\$progId\shell\open\command" -Value ('"{0}" "%1"' -f $resolvedExe)

$appKey = "$classes\Applications\$exeName"
New-Item -Path "$appKey\shell\open\command" -Force | Out-Null
Set-Item -Path "$appKey\shell\open\command" -Value ('"{0}" "%1"' -f $resolvedExe)
New-Item -Path "$appKey\SupportedTypes" -Force | Out-Null

foreach ($extension in $extensions) {
  New-Item -Path "$classes\$extension\OpenWithProgids" -Force | Out-Null
  New-ItemProperty -Path "$classes\$extension\OpenWithProgids" -Name $progId -Value '' -PropertyType String -Force | Out-Null
  New-ItemProperty -Path "$appKey\SupportedTypes" -Name $extension -Value '' -PropertyType String -Force | Out-Null
}

$sendTo = [Environment]::GetFolderPath('SendTo')
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $sendTo 'Print with XP-P323B.lnk'))
$shortcut.TargetPath = $resolvedExe
$shortcut.Arguments = '"%1"'
$shortcut.WorkingDirectory = [System.IO.Path]::GetDirectoryName($resolvedExe)
$shortcut.Description = 'Open the selected file in XP-P323B Printer'
$shortcut.Save()

Write-Host "Registered $displayName for Open with and Send to."
Write-Host "Executable: $resolvedExe"

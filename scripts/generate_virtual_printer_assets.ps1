$ErrorActionPreference = "Stop"

$assetDir = Join-Path $PSScriptRoot "..\windows-virtual-printer\PrintSupportApp\Assets"
New-Item -ItemType Directory -Force -Path $assetDir | Out-Null
Add-Type -AssemblyName System.Drawing

function New-XpLogo {
  param([int]$Size, [string]$Path)

  $bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::FromArgb(23, 105, 170))
    $fontSize = [Math]::Max(8, [int]($Size * 0.34))
    $font = New-Object System.Drawing.Font("Arial", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    try {
      $format = New-Object System.Drawing.StringFormat
      $format.Alignment = [System.Drawing.StringAlignment]::Center
      $format.LineAlignment = [System.Drawing.StringAlignment]::Center
      $graphics.DrawString("XP", $font, $brush, [System.Drawing.RectangleF]::new(0, 0, $Size, $Size), $format)
      $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $format.Dispose()
      $brush.Dispose()
      $font.Dispose()
    }
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

New-XpLogo -Size 50 -Path (Join-Path $assetDir "StoreLogo.png")
New-XpLogo -Size 150 -Path (Join-Path $assetDir "Square150x150Logo.png")
New-XpLogo -Size 44 -Path (Join-Path $assetDir "Square44x44Logo.png")
Write-Host "Generated MSIX package logo assets in $assetDir"

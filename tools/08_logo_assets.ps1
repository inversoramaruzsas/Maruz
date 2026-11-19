$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$src = "C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\.user_uploaded\media_1795116029231_082a6779.jpg"
$assets = "c:\Users\proye\Downloads\pentecostes-maruz\assets"
New-Item -ItemType Directory -Force -Path (Join-Path $assets "media") | Out-Null

$bmp = New-Object System.Drawing.Bitmap($src)
$W = $bmp.Width; $H = $bmp.Height
$bg = $bmp.GetPixel(6, 6)
$bgLum = (0.299 * $bg.R + 0.587 * $bg.G + 0.114 * $bg.B)

# Alpha mask from luminance: bg -> 0, white -> 255
$alpha = New-Object 'byte[]' ($W * $H)
$minX = $W; $minY = $H; $maxX = 0; $maxY = 0
for ($y = 0; $y -lt $H; $y++) {
    for ($x = 0; $x -lt $W; $x++) {
        $p = $bmp.GetPixel($x, $y)
        $lum = 0.299 * $p.R + 0.587 * $p.G + 0.114 * $p.B
        $a = [Math]::Max(0.0, [Math]::Min(1.0, ($lum - $bgLum) / (255.0 - $bgLum)))
        $alpha[$y * $W + $x] = [byte][Math]::Round($a * 255)
        if ($a -gt 0.25) {
            if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
$pad = 14
$minX = [Math]::Max(0, $minX - $pad); $minY = [Math]::Max(0, $minY - $pad)
$maxX = [Math]::Min($W - 1, $maxX + $pad); $maxY = [Math]::Min($H - 1, $maxY + $pad)
$cw = $maxX - $minX + 1; $ch = $maxY - $minY + 1
Write-Output ("crop " + $cw + "x" + $ch)

function Save-Variant($path, $r, $g, $b) {
    $out = New-Object System.Drawing.Bitmap($cw, $ch, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $ch; $y++) {
        for ($x = 0; $x -lt $cw; $x++) {
            $a = $alpha[($y + $minY) * $W + ($x + $minX)]
            $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($a, $r, $g, $b))
        }
    }
    # Downscale to 640 px wide for web
    $tw = 640; $th = [int][Math]::Round($ch * $tw / $cw)
    $small = New-Object System.Drawing.Bitmap($tw, $th, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g2 = [System.Drawing.Graphics]::FromImage($small)
    $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g2.DrawImage($out, 0, 0, $tw, $th)
    $g2.Dispose()
    $small.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $small.Dispose(); $out.Dispose()
}
Save-Variant (Join-Path $assets "logo-maruz-white.png") 255 255 255
Save-Variant (Join-Path $assets "logo-maruz-navy.png") $bg.R $bg.G $bg.B

# Original (for og:image / reference) and favicon
Copy-Item $src (Join-Path $assets "logo-maruz-inversora.jpg") -Force
$fav = New-Object System.Drawing.Bitmap(128, 128)
$gf = [System.Drawing.Graphics]::FromImage($fav)
$gf.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gf.DrawImage($bmp, 0, 0, 128, 128)
$gf.Dispose()
$fav.Save((Join-Path $assets "favicon.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$fav.Dispose(); $bmp.Dispose()

# Intro video
Copy-Item "C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\.user_uploaded\media_1795116182261_7d5dcae8.mp4" (Join-Path $assets "media\maruz-intro.mp4") -Force


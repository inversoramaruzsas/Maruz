$ErrorActionPreference = "Stop"
$assets = "c:\Users\proye\Downloads\pentecostes-maruz\assets"
$fontDir = Join-Path $assets "fonts"
New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
$url = "https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600;9..144,700&family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=Outfit:wght@400;500;600;700;800&family=JetBrains+Mono:wght@500;600&display=swap"
$css = (Invoke-WebRequest -Uri $url -UserAgent $ua -UseBasicParsing).Content
$blocks = [regex]::Matches($css, "/\*\s*([a-z0-9-]+)\s*\*/\s*@font-face\s*\{(.*?)\}", [System.Text.RegularExpressions.RegexOptions]::Singleline)
$out = New-Object System.Text.StringBuilder
[void]$out.AppendLine("/* Fuentes auto-hospedadas (Google Fonts, licencia OFL). Generado por tools/07_selfhost_fonts.ps1 */")
$downloaded = @{}
$kept = 0
foreach ($m in $blocks) {
    $subset = $m.Groups[1].Value
    if ($subset -notin @("latin", "latin-ext")) { continue }
    $body = $m.Groups[2].Value
    $family = [regex]::Match($body, "font-family:\s*'([^']+)'").Groups[1].Value
    $style = [regex]::Match($body, "font-style:\s*(\w+)").Groups[1].Value
    $weight = [regex]::Match($body, "font-weight:\s*([\d ]+);").Groups[1].Value.Trim()
    $src = [regex]::Match($body, "url\((https://[^)]+)\)").Groups[1].Value
    $range = [regex]::Match($body, "unicode-range:\s*([^;]+);").Groups[1].Value
    if (-not $src) { continue }
    if (-not $downloaded.ContainsKey($src)) {
        $fname = (($family -replace "\s", "") + "-" + $subset + "-" + ($weight -replace "\s", "_") + ".woff2")
        Invoke-WebRequest -Uri $src -OutFile (Join-Path $fontDir $fname) -UserAgent $ua -UseBasicParsing
        $downloaded[$src] = $fname
    }
    $fname = $downloaded[$src]
    [void]$out.AppendLine("@font-face { font-family: '$family'; font-style: $style; font-weight: $weight; font-display: swap; src: url('fonts/$fname') format('woff2'); unicode-range: $range; }")
    $kept++
}
[System.IO.File]::WriteAllText((Join-Path $assets "fonts.css"), $out.ToString(), $utf8NoBom)
Write-Output ("font-face rules: " + $kept + " | files: " + $downloaded.Count)
Get-ChildItem $fontDir | Select-Object Name, Length | Format-Table -AutoSize

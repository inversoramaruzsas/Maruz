$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Drawing

# 1. Inspect PDF objects of 1 - PENTECOSTES (1).pdf and extract high-res JPEG
$pdfPath = "c:\Users\proye\Downloads\1 - PENTECOSTES (1).pdf"
$bytes = [System.IO.File]::ReadAllBytes($pdfPath)
$enc = [System.Text.Encoding]::GetEncoding(28591)
$str = $enc.GetString($bytes)

# Print non-stream parts of objects
$objMatches = [regex]::Matches($str, "(\d+\s+\d+\s+obj\b)(.*?)(?=stream\r?\n|endobj)", [System.Text.RegularExpressions.RegexOptions]::Singleline)
Write-Output "=== PDF OBJECT HEADERS ==="
foreach ($m in $objMatches) {
    $hdr = ($m.Groups[2].Value -replace "\s+", " ").Trim()
    if ($hdr.Length -gt 200) { $hdr = $hdr.Substring(0, 200) + "..." }
    Write-Output ("  " + $m.Groups[1].Value + ": " + $hdr)
}

# Find the 13015173-byte DCTDecode stream
$marker = "/Length 13015173"
$idx = $str.IndexOf($marker)
if ($idx -ge 0) {
    $streamIdx = $str.IndexOf("stream", $idx)
    $startPos = $streamIdx + 6
    if ($bytes[$startPos] -eq 13 -and $bytes[$startPos+1] -eq 10) { $startPos += 2 }
    elseif ($bytes[$startPos] -eq 10) { $startPos += 1 }
    $jpgLen = 13015173
    $jpgBytes = New-Object byte[] $jpgLen
    [System.Array]::Copy($bytes, $startPos, $jpgBytes, 0, $jpgLen)
    $outJpg = "C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\scratch\pentecostes_raw.jpg"
    [System.IO.File]::WriteAllBytes($outJpg, $jpgBytes)
    Write-Output ("Extracted raw JPG: first bytes = " + $jpgBytes[0].ToString("X2") + " " + $jpgBytes[1].ToString("X2") + " " + $jpgBytes[2].ToString("X2") + " " + $jpgBytes[3].ToString("X2"))

    # Also check 1 - PENTECOSTES plano.pdf just in case raw.jpg is CMYK
    $img = [System.Drawing.Image]::FromFile($outJpg)
    Write-Output ("Loaded Image: Width=" + $img.Width + " Height=" + $img.Height + " PixelFormat=" + $img.PixelFormat)

    # Crop CUADRO DE AREAS (bottom-right area: x from 68% to 99%, y from 50% to 99.5%) into 3 crisp readable PNGs!
    $bmp = New-Object System.Drawing.Bitmap($img)
    # Top third of Cuadro de Areas (Manzanas 1-10)
    $r1 = New-Object System.Drawing.Rectangle([int]($img.Width * 0.68), [int]($img.Height * 0.50), [int]($img.Width * 0.315), [int]($img.Height * 0.16))
    $c1 = $bmp.Clone($r1, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $c1.Save("C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\scratch\cuadro_1_10.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $c1.Dispose()

    # Middle third of Cuadro de Areas (Manzanas 11-20)
    $r2 = New-Object System.Drawing.Rectangle([int]($img.Width * 0.68), [int]($img.Height * 0.645), [int]($img.Width * 0.315), [int]($img.Height * 0.185))
    $c2 = $bmp.Clone($r2, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $c2.Save("C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\scratch\cuadro_11_20.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $c2.Dispose()

    # Bottom third of Cuadro de Areas (Manzanas 21-28 + Superlotes)
    $r3 = New-Object System.Drawing.Rectangle([int]($img.Width * 0.68), [int]($img.Height * 0.82), [int]($img.Width * 0.315), [int]($img.Height * 0.175))
    $c3 = $bmp.Clone($r3, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $c3.Save("C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\scratch\cuadro_21_28_sl.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $c3.Dispose()

    $bmp.Dispose()
    $img.Dispose()
    Write-Output "Saved 3 cropped PNGs of CUADRO DE AREAS!"
}

# 2. Extract PENTECOSTÉS and named placemarks from KML
$kml = [System.IO.File]::ReadAllText("C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\scratch\maruz_proyectos.kml")
$pmMatches = [regex]::Matches($kml, "<Placemark>.*?</Placemark>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
Write-Output "=== NAMED KML PLACEMARKS ==="
foreach ($pm in $pmMatches) {
    $name = [regex]::Match($pm.Value, "<name>(.*?)</name>").Groups[1].Value.Trim()
    if ($name -ne "" -and $name -notlike "Ruta*") {
        Write-Output "--- PLACEMARK: $name ---"
        Write-Output $pm.Value
    }
}

# 3. Parse JAVIER NUÑEZ.xlsx completely (sharedStrings + sheet1)
function Read-XlsxSheet($xlsxFile, $sheetEntryPath) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($xlsxFile)
    $shared = @()
    $ssEntry = $zip.GetEntry("xl/sharedStrings.xml")
    if ($ssEntry) {
        $sr = New-Object System.IO.StreamReader($ssEntry.Open())
        [xml]$ssXml = $sr.ReadToEnd()
        $sr.Close()
        foreach ($si in $ssXml.sst.si) {
            if ($si.t -ne $null) {
                if ($si.t -is [string]) { $shared += $si.t } else { $shared += $si.t.InnerText }
            } elseif ($si.r) {
                $txt = ($si.r | ForEach-Object { if ($_.t -is [string]) { $_.t } else { $_.t.InnerText } }) -join ""
                $shared += $txt
            } else {
                $shared += ""
            }
        }
    }
    $shEntry = $zip.GetEntry($sheetEntryPath)
    $sr2 = New-Object System.IO.StreamReader($shEntry.Open())
    [xml]$shXml = $sr2.ReadToEnd()
    $sr2.Close()
    $zip.Dispose()

    $rowsOut = @()
    foreach ($row in $shXml.worksheet.sheetData.row) {
        $vals = @{}
        foreach ($c in $row.c) {
            $ref = $c.r -replace "\d+", ""
            $v = ""
            if ($c.v -ne $null) {
                if ($c.t -eq "s") {
                    $v = $shared[[int]$c.v]
                } else {
                    $v = [string]$c.v
                }
            }
            $vals[$ref] = $v
        }
        $rowsOut += [PSCustomObject]$vals
    }
    return $rowsOut
}

$jnRows = Read-XlsxSheet "c:\Users\proye\Downloads\JAVIER NUÑEZ.xlsx" "xl/worksheets/sheet1.xml"
Write-Output ("=== JAVIER NUÑEZ.XLSX TOTAL ROWS: " + $jnRows.Count + " ===")
$jnRows | Select-Object -First 5 | Format-Table -AutoSize
$jnRows | Select-Object -Last 10 | Format-Table -AutoSize

# Group by trimmed ESTADO
$stateCounts = @{}
foreach ($r in ($jnRows | Select-Object -Skip 1)) {
    $st = if ($r.C) { $r.C.Trim().ToUpper() } else { "(VACIO)" }
    if (-not $stateCounts.ContainsKey($st)) { $stateCounts[$st] = 0 }
    $stateCounts[$st]++
}
Write-Output "=== ESTADO COUNTS IN JAVIER NUÑEZ.XLSX ==="
foreach ($k in ($stateCounts.Keys | Sort-Object)) {
    Write-Output ("  " + $k + ": " + $stateCounts[$k])
}

# Save full JSON of JAVIER NUÑEZ.xlsx
$jnJson = $jnRows | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText("C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\scratch\javier_nunez.json", $jnJson, [System.Text.Encoding]::UTF8)

# Also check PROYECTOS sheet in INVENTARIO COMERCIAL .xlsx (sheet2.xml)
$icRows = Read-XlsxSheet "c:\Users\proye\Downloads\INVENTARIO COMERCIAL .xlsx" "xl/worksheets/sheet2.xml"
Write-Output ("=== INVENTARIO COMERCIAL PROYECTOS ROWS: " + $icRows.Count + " ===")
foreach ($r in ($icRows | Select-Object -First 35)) {
    $line = ($r.PSObject.Properties | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join " | "
    if ($line.Trim() -ne "") { Write-Output ("  " + $line) }
}

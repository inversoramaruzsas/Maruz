$ErrorActionPreference = "Stop"

$webDir = "c:\Users\proye\Downloads\pentecostes-maruz"
$invPath = Join-Path $webDir "data\pentecostes-inventory.json"
$dataJsPath = Join-Path $webDir "assets\pentecostes-data.js"

$payload = Get-Content $invPath -Raw -Encoding UTF8 | ConvertFrom-Json

# GPS bounds of Pentecostes from KML:
# In masterplan image (8702 x 11811), North-East is top-right (Mz 28 near 6700, 2700 -> lat ~5.2468, lng ~-72.4075)
# South-West is bottom-left (SL-02 near 1650, 7900 -> lat ~5.2413, lng ~-72.4120)
# South-East is bottom-right (SL-17 / Mz 01 near 5100, 9600 -> lat ~5.2405, lng ~-72.4105)
$minPxX = 1400.0; $maxPxX = 7200.0
$minPxY = 1950.0; $maxPxY = 10300.0
$minLat = 5.24050; $maxLat = 5.24715
$minLng = -72.41210; $maxLng = -72.40730

# Group lots by Manzana for fast neighbor lindero detection
$byMz = @{}
foreach ($l in $payload.lots) {
    $mk = [string]$l.manzana
    if (-not $byMz.ContainsKey($mk)) { $byMz[$mk] = New-Object System.Collections.Generic.List[object] }
    $byMz[$mk].Add($l)
}

# Precompute bbox for every lot
foreach ($l in $payload.lots) {
    $minX = 1e9; $minY = 1e9; $maxX = -1e9; $maxY = -1e9
    $perimPx = 0.0
    $n = $l.pts.Count
    $edgesPx = New-Object System.Collections.Generic.List[double]
    for ($i = 0; $i -lt $n; $i++) {
        $x1 = [double]$l.pts[$i][0]; $y1 = [double]$l.pts[$i][1]
        $x2 = [double]$l.pts[($i + 1) % $n][0]; $y2 = [double]$l.pts[($i + 1) % $n][1]
        if ($x1 -lt $minX) { $minX = $x1 }
        if ($x1 -gt $maxX) { $maxX = $x1 }
        if ($y1 -lt $minY) { $minY = $y1 }
        if ($y1 -gt $maxY) { $maxY = $y1 }
        $ed = [Math]::Sqrt(($x2 - $x1)*($x2 - $x1) + ($y2 - $y1)*($y2 - $y1))
        $edgesPx.Add($ed)
        $perimPx += $ed
    }
    $l | Add-Member -NotePropertyName "bbox" -NotePropertyValue ([int[]]@([int][Math]::Round($minX), [int][Math]::Round($minY), [int][Math]::Round($maxX), [int][Math]::Round($maxY))) -Force

    # Pixel-to-meter scale calibrated from each lot's official m2 area & polygon pixel area!
    # Compute exact shoelace pixel area of simplified polygon
    $shoe2 = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $x1 = [double]$l.pts[$i][0]; $y1 = [double]$l.pts[$i][1]
        $x2 = [double]$l.pts[($i + 1) % $n][0]; $y2 = [double]$l.pts[($i + 1) % $n][1]
        $shoe2 += ($x1 * $y2 - $x2 * $y1)
    }
    $polyPxArea = [Math]::Max(1000.0, [Math]::Abs($shoe2) * 0.5)
    $mPerPx = [Math]::Sqrt([double]$l.area / $polyPxArea)

    $sortedEdgesM = @($edgesPx | ForEach-Object { $_ * $mPerPx } | Sort-Object)
    $frenteM = if ($l.area -eq 90 -and -not $l.isSuperLote) { 6.0 } else { [Math]::Round($sortedEdgesM[0], 1) }
    $fondoM  = if ($l.area -eq 90 -and -not $l.isSuperLote) { 15.0 } else { [Math]::Round($sortedEdgesM[$sortedEdgesM.Count - 1], 1) }
    $perimM  = if ($l.area -eq 90 -and -not $l.isSuperLote) { 42.0 } else { [Math]::Round($perimPx * $mPerPx, 1) }

    $l | Add-Member -NotePropertyName "perimetroM" -NotePropertyValue $perimM -Force
    $l | Add-Member -NotePropertyName "frenteM" -NotePropertyValue $frenteM -Force
    $l | Add-Member -NotePropertyName "fondoM" -NotePropertyValue $fondoM -Force

    # GPS interpolation inside Pentecostes KML footprint
    $nx = ([double]$l.cx - $minPxX) / ($maxPxX - $minPxX)
    $ny = 1.0 - (([double]$l.cy - $minPxY) / ($maxPxY - $minPxY))
    $lat = [Math]::Round($minLat + $ny * ($maxLat - $minLat), 6)
    $lng = [Math]::Round($minLng + $nx * ($maxLng - $minLng), 6)
    $l | Add-Member -NotePropertyName "lat" -NotePropertyValue $lat -Force
    $l | Add-Member -NotePropertyName "lng" -NotePropertyValue $lng -Force

    # Everia-compatible separation & initial 30d breakdown
    $sep = 1000000L
    $saldoIni30d = [Math]::Max(0L, [long]$l.cuotaInicial - $sep)
    $l | Add-Member -NotePropertyName "separacion" -NotePropertyValue $sep -Force
    $l | Add-Member -NotePropertyName "saldoInicial30d" -NotePropertyValue $saldoIni30d -Force
    $mzPad = if ($l.isSuperLote) { "SL" } else { "MZ" + ([int]$l.manzana).ToString("00") }
    $l | Add-Member -NotePropertyName "fichaRef" -NotePropertyValue ("MARUZ-PENT-" + $mzPad + "-" + ([int]$l.lote).ToString("00")) -Force
}

# Compute real N/S/E/O Linderos & Esquinero status from same-Manzana neighbor adjacency!
$esquinerosCount = 0
foreach ($mk in $byMz.Keys) {
    $list = $byMz[$mk]
    foreach ($a in $list) {
        $norte = "Vía vehicular interna"
        $sur   = "Vía vehicular interna"
        $este  = "Vía vehicular interna"
        $oeste = "Vía vehicular interna"
        if ($a.isSuperLote) {
            $sur = "Zona de reserva forestal / Ronda verde"
            $norte = "Vía perimetral Urbanización Pentecostés"
        } elseif ([int]$a.manzana -eq 28) {
            $norte = "Parque Ecológico Reserva Natural"
            $este  = "Parque Ecológico Reserva Natural"
        }

        $sharedCount = 0
        foreach ($b in $list) {
            if ($a.id -eq $b.id) { continue }
            $dx = [double]$b.cx - [double]$a.cx
            $dy = [double]$b.cy - [double]$a.cy
            $dist = [Math]::Sqrt($dx*$dx + $dy*$dy)
            $maxNeighborDist = if ($a.isSuperLote) { 460.0 } else { 195.0 }
            if ($dist -le $maxNeighborDist) {
                # Check bbox gap <= 28px (actually touching wall/corner)
                $gx = [Math]::Max(0, [Math]::Max($a.bbox[0] - $b.bbox[2], $b.bbox[0] - $a.bbox[2]))
                $gy = [Math]::Max(0, [Math]::Max($a.bbox[1] - $b.bbox[3], $b.bbox[1] - $a.bbox[3]))
                if ($gx -le 28 -and $gy -le 28) {
                    $sharedCount++
                    $lbl = if ($b.isSuperLote) { "Super Lote " + $b.lote } else { "Lote " + ([int]$b.lote).ToString("00") }
                    # Assign to dominant cardinal quadrant
                    if ([Math]::Abs($dy) -ge [Math]::Abs($dx)) {
                        if ($dy -lt 0) { $norte = $lbl } else { $sur = $lbl }
                    } else {
                        if ($dx -gt 0) { $este = $lbl } else { $oeste = $lbl }
                    }
                }
            }
        }

        # Corner lot (Esquinero): in a 2-row block, interior medianero lots touch >= 3 lots (left, right, back),
        # whereas corner lots (esquineros) touch <= 2 neighbor lots (2 street fronts!) or have irregular corner area != 90m2!
        $isCorner = (-not $a.isSuperLote) -and (($sharedCount -le 2) -or ($a.area -gt 92) -or ($a.area -lt 85))
        if ($isCorner) { $esquinerosCount++ }
        $a | Add-Member -NotePropertyName "esEsquinero" -NotePropertyValue $isCorner -Force
        $a | Add-Member -NotePropertyName "linderos" -NotePropertyValue ([ordered]@{
            norte     = $norte
            sur       = $sur
            oriente   = $este
            occidente = $oeste
        }) -Force
    }
}
Write-Output ("Detected corner lots (Esquineros): " + $esquinerosCount + " / 839")

# Save enriched Stage 1 JSON & JS payload without UTF-8 BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$outJson = $payload | ConvertTo-Json -Depth 9 -Compress
[System.IO.File]::WriteAllText($invPath, $outJson, $utf8NoBom)
[System.IO.File]::WriteAllText($dataJsPath, ("window.PENTECOSTES_DATA = " + $outJson + ";"), $utf8NoBom)
Write-Output ("Stage 1 enriched dataset saved! Size = " + [Math]::Round($outJson.Length / 1024.0, 1) + " KB")

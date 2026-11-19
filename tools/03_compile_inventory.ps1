$ErrorActionPreference = "Stop"

$scratchDir = "C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\scratch"
$webDir = "c:\Users\proye\Downloads\pentecostes-maruz"
New-Item -ItemType Directory -Force -Path (Join-Path $webDir "assets") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $webDir "data") | Out-Null

# Copy original PDF plano for 1-click download in the UI
Copy-Item "c:\Users\proye\Downloads\1 - PENTECOSTES plano.pdf" (Join-Path $webDir "assets\plano-original-pentecostes.pdf") -Force

$rawPolyJson = (Get-Content (Join-Path $scratchDir "extracted_polygons.json") -Raw -Encoding UTF8) -replace '"r":F1', '"r":50'
$polyObj = $rawPolyJson | ConvertFrom-Json
$excelRows = Get-Content (Join-Path $scratchDir "javier_nunez.json") -Raw -Encoding UTF8 | ConvertFrom-Json

# Exact geometric split of the single merged pair in Mz 10 (Lote 05 + Lote 19 across circle 10) into exact 4-corner quads!
$mz10Polys = @($polyObj.polygons | Where-Object { ([string]$_.mz) -eq "10" } | Sort-Object { [int]$_.lote })
if ($mz10Polys.Count -eq 22) {
    Write-Output "Repairing Mz 10 merged pair (Lote 05 & Lote 19) using exact neighbor quad corners..."
    $otherPolys = @($polyObj.polygons | Where-Object { ([string]$_.mz) -ne "10" })
    $byLote = @{}
    foreach ($mp in $mz10Polys) { $byLote[[int]$mp.lote] = $mp }
    # In verify_mz10.jpg:
    # 1..4 are exact Lotes 01..04
    # 5..17 are exact Lotes 06..18
    # 18..21 are exact Lotes 20..23
    # 22 is the merged (05 + 19)
    $p04 = $byLote[4]
    $p06 = $byLote[5]
    $p18 = $byLote[17]
    $p20 = $byLote[18]

    # Helper: get the 2 vertices of poly A closest to poly B
    function Get-SharedEdgeVerts($polyA, $refCx, $refCy) {
        return @($polyA.pts | Sort-Object {
            $dx = $_[0] - $refCx; $dy = $_[1] - $refCy
            $dx * $dx + $dy * $dy
        } | Select-Object -First 2)
    }
    $mid05x = ($p04.cx + $p06.cx) * 0.5; $mid05y = ($p04.cy + $p06.cy) * 0.5
    $e04 = Get-SharedEdgeVerts $p04 $p06.cx $p06.cy
    $e06 = Get-SharedEdgeVerts $p06 $p04.cx $p04.cy
    # Order 4 corners of Lote 05 around its centroid (force pure [int[]] arrays so PS 5.1 ConvertTo-Json emits [[x,y],...]!)
    $raw05 = @($e04[0], $e04[1], $e06[0], $e06[1]) | Sort-Object { [Math]::Atan2([double]$_[1] - $mid05y, [double]$_[0] - $mid05x) }
    $pts05 = New-Object System.Collections.Generic.List[int[]]
    foreach ($pt in $raw05) { $pts05.Add([int[]]@([int]$pt[0], [int]$pt[1])) }

    $mid19x = ($p18.cx + $p20.cx) * 0.5; $mid19y = ($p18.cy + $p20.cy) * 0.5
    $e18 = Get-SharedEdgeVerts $p18 $p20.cx $p20.cy
    $e20 = Get-SharedEdgeVerts $p20 $p18.cx $p18.cy
    $raw19 = @($e18[0], $e18[1], $e20[0], $e20[1]) | Sort-Object { [Math]::Atan2([double]$_[1] - $mid19y, [double]$_[0] - $mid19x) }
    $pts19 = New-Object System.Collections.Generic.List[int[]]
    foreach ($pt in $raw19) { $pts19.Add([int[]]@([int]$pt[0], [int]$pt[1])) }

    $fixedMz10 = New-Object System.Collections.Generic.List[object]
    for ($k = 1; $k -le 4; $k++) { $fixedMz10.Add($byLote[$k]) }
    $fixedMz10.Add([PSCustomObject]@{ mz = 10; lote = 5; cx = [Math]::Round($mid05x); cy = [Math]::Round($mid05y); pxArea = 8900; pts = $pts05 })
    for ($k = 5; $k -le 17; $k++) {
        $item = $byLote[$k]; $item.lote = $k + 1; $fixedMz10.Add($item)
    }
    $fixedMz10.Add([PSCustomObject]@{ mz = 10; lote = 19; cx = [Math]::Round($mid19x); cy = [Math]::Round($mid19y); pxArea = 8900; pts = $pts19 })
    for ($k = 18; $k -le 21; $k++) {
        $item = $byLote[$k]; $item.lote = $k + 2; $fixedMz10.Add($item)
    }
    $polyObj.polygons = @($otherPolys + $fixedMz10) | Sort-Object { if ([string]$_.mz -like "SUPER*") { 99 } else { [int]$_.mz } }, { [int]$_.lote }
}

# Build lookup dictionary from Excel rows: key = "$mzKey|$loteNum"
$invMap = @{}
$rowIdx = 0
foreach ($r in $excelRows) {
    $rowIdx++
    if ($rowIdx -eq 1) { continue } # header
    $mzRaw = if ($r.A -ne $null) { ([string]$r.A).Trim().ToUpper() } else { "" }
    $ltRaw = if ($r.B -ne $null) { ([string]$r.B).Trim() } else { "" }
    $stRaw = if ($r.C -ne $null) { ([string]$r.C).Trim().ToUpper() } else { "" }
    $m2Raw = if ($r.D -ne $null) { ([string]$r.D).Trim() } else { "" }
    $valRaw = if ($r.E -ne $null) { ([string]$r.E).Trim() } else { "" }

    # Row 841 in Excel has empty MANZANA and LOTE=1 -> Manzana 28, Lote 1
    if ($mzRaw -eq "" -and $ltRaw -eq "1") {
        $mzRaw = "28"
    }
    if ($mzRaw -like "SUPER*") {
        $mzRaw = "SUPER LOTE"
    }
    $key = "$mzRaw|$ltRaw"
    $invMap[$key] = @{
        rawStatus = $stRaw
        m2        = if ($m2Raw -ne "") { [double]$m2Raw } else { 0.0 }
        valorHist = if ($valRaw -ne "") { [double]$valRaw } else { $null }
    }
}

# Cuadro de Areas fallback / reference areas where Excel had blank (e.g. 18|10 = 90)
$cuadroOverrides = @{
    "18|10" = 90.0
    "15|26" = 126.0
    "15|27" = 113.0
    "15|28" = 91.0
    "15|29" = 91.0
    "27|9"  = 95.0
    "27|10" = 97.0
}

$compiledLots = New-Object System.Collections.Generic.List[object]
$statusSummary = @{}

foreach ($p in $polyObj.polygons) {
    $mzStr = [string]$p.mz
    if ($mzStr -like "SUPER*") { $mzStr = "SUPER LOTE" }
    $loteNum = [int]$p.lote
    $key = "$mzStr|$loteNum"

    $rawStatus = ""
    $areaM2 = 90.0
    $valorHist = $null

    if ($invMap.ContainsKey($key)) {
        $entry = $invMap[$key]
        $rawStatus = $entry.rawStatus
        if ($entry.m2 -gt 0) {
            $areaM2 = $entry.m2
        } elseif ($cuadroOverrides.ContainsKey($key)) {
            $areaM2 = $cuadroOverrides[$key]
        }
        $valorHist = $entry.valorHist
    } elseif ($cuadroOverrides.ContainsKey($key)) {
        $areaM2 = $cuadroOverrides[$key]
    }

    $areaPlano = if ($cuadroOverrides.ContainsKey($key)) { $cuadroOverrides[$key] } else { $areaM2 }

    # Normalize status into clear commercial categories while preserving exact rawStatus!
    # Categories:
    # - VENDIDO: painted RED (#ef4444)
    # - DISPONIBLE: blank in Excel -> pure available, painted EMERALD GREEN (#10b981)
    # - LIBERADO: DEVOLUCION, CLAUSULA, CAMBIO DE PARCELA, REUBICADO -> recovered/available inventory, painted TEAL/GREEN (#14b8a6 / #10b981)
    # - PROCESO: SEPARADO, PENDIENTE, CESION DE APORTES -> reserved / in legal process, painted AMBER (#f59e0b)
    $statusGroup = "DISPONIBLE"
    $statusLabel = "Disponible"
    if ($rawStatus -eq "VENDIDO") {
        $statusGroup = "VENDIDO"
        $statusLabel = "Vendido"
    } elseif ($rawStatus -eq "") {
        $statusGroup = "DISPONIBLE"
        $statusLabel = "Disponible Inmediato"
    } elseif ($rawStatus -in @("SEPARADO", "PENDIENTE", "CESION DE APORTES")) {
        $statusGroup = "PROCESO"
        if ($rawStatus -eq "SEPARADO") { $statusLabel = "Separado" }
        elseif ($rawStatus -eq "PENDIENTE") { $statusLabel = "En Trámite (Pendiente)" }
        else { $statusLabel = "Cesión de Aportes" }
    } else {
        # CLAUSULA, DEVOLUCION, CAMBIO DE PARCELA, REUBICADO
        $statusGroup = "LIBERADO"
        if ($rawStatus -eq "CLAUSULA") { $statusLabel = "Liberado (Cláusula)" }
        elseif ($rawStatus -eq "DEVOLUCION") { $statusLabel = "Disponible (Devolución)" }
        elseif ($rawStatus -eq "CAMBIO DE PARCELA") { $statusLabel = "Liberado (Cambio Parcela)" }
        elseif ($rawStatus -eq "REUBICADO") { $statusLabel = "Liberado (Reubicado)" }
        else { $statusLabel = $rawStatus }
    }

    $stCountKey = if ($rawStatus -eq "") { "DISPONIBLE (VACIO)" } else { $rawStatus }
    if (-not $statusSummary.ContainsKey($stCountKey)) { $statusSummary[$stCountKey] = 0 }
    $statusSummary[$stCountKey]++

    # Official Pentecostes Pricing Formula:
    # Reference 90 m2: Financiado = $30,000,000 COP ($333,333.33 / m2), Contado = $25,000,000 COP ($277,777.78 / m2)
    # Cuota Inicial = $10,000,000 COP, Cuotas Fijas Mensuales = $350,000 COP (0% interés)
    $precioFinanciado = [long][Math]::Round($areaM2 * (30000000.0 / 90.0))
    $precioContado    = [long][Math]::Round($areaM2 * (25000000.0 / 90.0))
    $ahorroContado    = $precioFinanciado - $precioContado
    $cuotaInicial     = 10000000L
    $cuotaMensual     = 350000L
    $saldoFinanciar   = [Math]::Max(0L, $precioFinanciado - $cuotaInicial)
    $numCuotas        = [Math]::Round($saldoFinanciar / 350000.0, 2)

    $isSuper = ($mzStr -eq "SUPER LOTE")
    $code = if ($isSuper) { ("SL-" + $loteNum.ToString("00")) } else { ("MZ" + ([int]$mzStr).ToString("00") + "-L" + $loteNum.ToString("00")) }
    $shortLabel = if ($isSuper) { ("SL-" + $loteNum.ToString("00")) } else { $loteNum.ToString("00") }

    # Typical dimensions string
    $dims = if ($isSuper) {
        if ($areaM2 -eq 1000) { "20m × 50m aprox." } else { "Lote Especial ($areaM2 m²)" }
    } elseif ($areaM2 -eq 90) {
        "6m × 15m"
    } else {
        "Irregular / Esquinero ($areaM2 m²)"
    }

    $compiledLots.Add([ordered]@{
        id               = $code
        manzana          = if ($isSuper) { "SUPER LOTE" } else { [int]$mzStr }
        lote             = $loteNum
        shortLabel       = $shortLabel
        isSuperLote      = $isSuper
        area             = $areaM2
        areaPlano        = $areaPlano
        dimensions       = $dims
        status           = $statusGroup
        statusLabel      = $statusLabel
        rawStatus        = $rawStatus
        precioFinanciado = $precioFinanciado
        precioContado    = $precioContado
        ahorroContado    = $ahorroContado
        cuotaInicial     = $cuotaInicial
        cuotaMensual     = $cuotaMensual
        saldoFinanciar   = $saldoFinanciar
        numCuotas        = $numCuotas
        valorHistorico   = $valorHist
        cx               = $p.cx
        cy               = $p.cy
        pts              = $p.pts
    })
}

Write-Output ("Compiled total polygons with full attributes: " + $compiledLots.Count)
foreach ($k in ($statusSummary.Keys | Sort-Object)) {
    Write-Output ("  Status [" + $k + "] = " + $statusSummary[$k])
}

# Parse GPS boundary of PENTECOSTÉS from maruz_proyectos.kml
$kmlText = [System.IO.File]::ReadAllText((Join-Path $scratchDir "maruz_proyectos.kml"))
$pentBlock = [regex]::Match($kmlText, "<Placemark>\s*<name>PENTECOSTÉS</name>.*?</Placemark>", [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
$coordRaw = [regex]::Match($pentBlock, "<coordinates>(.*?)</coordinates>", [System.Text.RegularExpressions.RegexOptions]::Singleline).Groups[1].Value.Trim()
$gpsBoundary = New-Object System.Collections.Generic.List[double[]]
foreach ($tok in ($coordRaw -split "\s+")) {
    if ($tok -match "^(-?\d+\.\d+),(-?\d+\.\d+)") {
        $gpsBoundary.Add([double[]]@([double]$Matches[2], [double]$Matches[1])) # [lat, lng]
    }
}

$masterPayload = [ordered]@{
    project = [ordered]@{
        name              = "Urbanización Pentecostés"
        company           = "Inversora Maruz S.A.S."
        slogan            = ""
        location          = "Vereda San Rafael de Morichal · Casanare"
        addressOffice     = ""   # configurar en assets/site-config.js
        whatsapp          = ""   # configurar en assets/site-config.js
        whatsappDisplay   = ""
        coordinates       = @{ lat = 5.243400; lng = -72.409928; dms = "5°14'36.24""N 72°24'35.74""O" }
        gpsBoundary       = $gpsBoundary
        pricingRules      = [ordered]@{
            baseAreaM2          = 90
            baseFinanciado      = 30000000
            baseContado         = 25000000
            pricePerM2Financ    = 333333.3333333333
            pricePerM2Contado   = 277777.7777777778
            cuotaInicialBase    = 10000000
            cuotaMensualFija    = 350000
            tasaInteres         = 0
        }
    }
    mapConfig = [ordered]@{
        canvasWidth    = $polyObj.canvasWidth
        canvasHeight   = $polyObj.canvasHeight
        imageScale     = 0.4
        initialViewBox = @(1220, 1820, 6150, 8750)
        manzanaCenters = $polyObj.manzanaCenters
    }
    lots          = $compiledLots
}

$jsonString = $masterPayload | ConvertTo-Json -Depth 8 -Compress
[System.IO.File]::WriteAllText((Join-Path $webDir "data\pentecostes-inventory.json"), $jsonString, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText((Join-Path $webDir "assets\pentecostes-data.js"), ("window.PENTECOSTES_DATA = " + $jsonString + ";"), [System.Text.Encoding]::UTF8)
Write-Output ("Wrote pentecostes-data.js (" + [Math]::Round($jsonString.Length / 1024.0, 1) + " KB)!")

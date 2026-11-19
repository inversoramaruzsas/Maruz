$ErrorActionPreference = "Stop"
# Builds assets/atlas-data.js ONLY from verified sources:
#   - PROYECTOS CUOTAS PARES UBICACION.xlsx  (vereda, lat/lng DMS, cuotas partes, area modal)
#   - INVENTARIO COMERCIAL .xlsx / hoja PROYECTOS (precios, inicial, cuota, # cuotas)
# Projects without a commercial offer in the inventory sheet are flagged "consultar".
Add-Type -AssemblyName System.IO.Compression.FileSystem
$webDir = "c:\Users\proye\Downloads\pentecostes-maruz"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-Sheet($xlsxFile) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($xlsxFile)
    $shared = @()
    $ss = $zip.GetEntry("xl/sharedStrings.xml")
    if ($ss) {
        $sr = New-Object System.IO.StreamReader($ss.Open()); [xml]$x = $sr.ReadToEnd(); $sr.Close()
        foreach ($si in $x.sst.si) {
            if ($si.t -ne $null) { if ($si.t -is [string]) { $shared += $si.t } else { $shared += $si.t.InnerText } }
            elseif ($si.r) { $shared += (($si.r | ForEach-Object { if ($_.t -is [string]) { $_.t } else { $_.t.InnerText } }) -join "") }
            else { $shared += "" }
        }
    }
    $sr2 = New-Object System.IO.StreamReader($zip.GetEntry("xl/worksheets/sheet1.xml").Open()); [xml]$sx = $sr2.ReadToEnd(); $sr2.Close()
    $zip.Dispose()
    $rows = @()
    foreach ($row in $sx.worksheet.sheetData.row) {
        $h = @{}
        foreach ($c in $row.c) {
            $col = $c.r -replace "\d+", ""
            $v = ""
            if ($c.v -ne $null) { if ($c.t -eq "s") { $v = $shared[[int]$c.v] } else { $v = [string]$c.v } }
            $h[$col] = $v.Trim()
        }
        $rows += , $h
    }
    return $rows
}

function Dms-ToDec($s) {
    $m = [regex]::Match($s, "(\d+)\D+(\d+)\D+([\d\.]+)\D*([NSEOW])")
    if (-not $m.Success) { return $null }
    $d = [double]$m.Groups[1].Value + [double]$m.Groups[2].Value / 60.0 + [double]::Parse($m.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture) / 3600.0
    if ($m.Groups[4].Value -in @("S", "O", "W")) { $d = -$d }
    return [Math]::Round($d, 6)
}

$rows = Read-Sheet "c:\Users\proye\Downloads\PROYECTOS CUOTAS PARES UBICACION.xlsx"
$byItem = [ordered]@{}
foreach ($r in ($rows | Select-Object -Skip 1)) {
    if (-not $r["A"]) { continue }
    $item = [int]$r["A"]
    $k = "k$item"
    if (-not $byItem.Contains($k)) { $byItem[$k] = New-Object System.Collections.Generic.List[hashtable] }
    $byItem[$k].Add($r)
}

# Verified commercial offers from INVENTARIO COMERCIAL (hoja PROYECTOS). Amounts in COP.
function Offer($label, $credito, $contado, $inicial, $cuota, $n, $verificar) {
    return [ordered]@{ label = $label; credito = $credito; contado = $contado; inicial = $inicial; cuota = $cuota; nCuotas = $n; validar = $verificar }
}
$offers = @{
    1  = @( (Offer "Oferta estándar" 30000000 25000000 10000000 350000 57.14 $false) )
    2  = @( (Offer "Oferta estándar" 35000000 30000000 1000000 250000 136 $false) )
    3  = @(
        (Offer "Etapa 1" 35000000 30000000 1000000 250000 136 $false),
        (Offer "Etapa 2" 35000000 30000000 2000000 250000 132 $false),
        (Offer "Etapa 5" 25000000 20000000 1000000 250000 96 $false),
        (Offer "Etapa 6" 35000000 30000000 500000 250000 138 $false) )
    4  = @( (Offer "Oferta estándar" 40000000 35000000 5000000 500000 70 $false) )
    5  = @( (Offer "Oferta estándar" 40000000 35000000 2000000 350000 108.57 $false) )
    6  = @( (Offer "Oferta estándar" 35000000 30000000 500000 250000 138 $false) )
    8  = @( (Offer "Oferta estándar" 35000000 30000000 2000000 250000 132 $false) )
    12 = @(
        (Offer "Esquineros" 35000000 25000000 2000000 250000 132 $false),
        (Offer "Medianeros" 35000000 25000000 350000 350000 99 $false) )
    16 = @(
        (Offer "Oferta 1" 16000000 10000000 1000000 500000 30 $false),
        (Offer "Oferta 2" 16000000 10000000 5000000 500000 22 $false),
        (Offer "Oferta 3" 30000000 10000000 300000 300000 99 $true) )
    19 = @(
        (Offer "Esquineros" 55000000 50000000 2000000 350000 151.43 $false),
        (Offer "Medianeros" 55000000 50000000 500000 350000 155.71 $false) )
    20 = @( (Offer "Oferta estándar" 15000000 10000000 500000 350000 41.43 $false) )
}

$displayNames = @{
    1 = "Pentecostés"; 2 = "Samara"; 3 = "Tierra Prometida"; 4 = "Jireh"; 5 = "Asiel"; 6 = "Santa Gracia"
    7 = "Baruc"; 8 = "Abiel"; 9 = "Edén"; 10 = "Leche Miel"; 11 = "Milagros"; 12 = "Cristo Santo"
    13 = "Peña de Horeb"; 14 = "Rey de Reyes"; 15 = "Shaddai"; 16 = "Shalom"; 17 = "Shekinah"
    18 = "Yannis"; 19 = "Yeshua"; 20 = "Elohim"; 21 = "Ian"
}
function Title($s) { return (Get-Culture).TextInfo.ToTitleCase($s.ToLower()) }

$projects = New-Object System.Collections.Generic.List[object]
foreach ($key in @($byItem.Keys)) {
    $item = [int]($key.Substring(1))
    $stages = $byItem[$key]
    $sumCuotas = 0; $lats = @(); $lngs = @(); $areas = New-Object System.Collections.Generic.List[string]
    foreach ($s in $stages) {
        $sumCuotas += [int]$s["F"]
        $la = Dms-ToDec $s["D"]; $lo = Dms-ToDec $s["E"]
        if ($la -ne $null) { $lats += $la }; if ($lo -ne $null) { $lngs += $lo }
        $a = $s["G"]; if ($a -and -not $areas.Contains($a)) { $areas.Add($a) }
    }
    $lat = [Math]::Round(($lats | Measure-Object -Average).Average, 6)
    $lng = [Math]::Round(($lngs | Measure-Object -Average).Average, 6)
    $vereda = Title $stages[0]["C"]
    $stageList = @()
    if ($stages.Count -gt 1) {
        foreach ($s in $stages) { $stageList += [ordered]@{ nombre = (Title $s["B"]); cuotasPartes = [int]$s["F"]; area = $s["G"]; lat = (Dms-ToDec $s["D"]); lng = (Dms-ToDec $s["E"]) } }
    }
    $type = switch ($item) {
        { $_ -in 1, 2, 12, 16, 20 } { "Terrenos"; break }
        default { "Parcelas y campestres" }
    }
    $ofertasArr = @()
    if ($offers.ContainsKey($item)) { $ofertasArr = @($offers[$item]) }
    $projects.Add([ordered]@{
        num          = $item.ToString("00")
        id           = ($displayNames[$item].ToLower() -replace "[^a-z0-9]+", "-").Trim("-")
        name         = $displayNames[$item]
        type         = $type
        vereda       = $vereda
        lat          = $lat
        lng          = $lng
        cuotasPartes = $sumCuotas
        areaModal    = ($areas -join " · ")
        etapas       = $stageList
        ofertas      = $ofertasArr
        active       = ($item -eq 1)
    })
}

$total = ($projects | ForEach-Object { $_.cuotasPartes } | Measure-Object -Sum).Sum
Write-Output ("Projects: " + $projects.Count + " | total cuotas partes: " + $total)
$atlas = [ordered]@{ fuente = "PROYECTOS CUOTAS PARES UBICACION.xlsx + INVENTARIO COMERCIAL .xlsx"; proyectos = $projects }
$json = $atlas | ConvertTo-Json -Depth 8 -Compress
[System.IO.File]::WriteAllText((Join-Path $webDir "assets\atlas-data.js"), ("window.MARUZ_ATLAS = " + $json + ";"), $utf8NoBom)

# Remove previously unverified blocks from the Pentecostes dataset
foreach ($p in @("assets\pentecostes-data.js", "data\pentecostes-inventory.json")) {
    $path = Join-Path $webDir $p
    $txt = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $isJs = $p.EndsWith(".js")
    if ($isJs) { $txt = $txt -replace "^window\.PENTECOSTES_DATA\s*=\s*", "" -replace ";\s*$", "" }
    $obj = $txt | ConvertFrom-Json
    foreach ($rm in @("maruzProjects", "maruzAtlas21")) { if ($obj.PSObject.Properties[$rm]) { $obj.PSObject.Properties.Remove($rm) } }
    # Contact data was never verified from source files -> blank until configured in site-config.js
    $obj.project.whatsapp = ""; $obj.project.whatsappDisplay = ""; $obj.project.addressOffice = ""; $obj.project.slogan = ""
    $out = $obj | ConvertTo-Json -Depth 9 -Compress
    if ($isJs) { $out = "window.PENTECOSTES_DATA = " + $out + ";" }
    [System.IO.File]::WriteAllText($path, $out, $utf8NoBom)
}
Write-Output "Pentecostes dataset cleaned (no unverified projects/contact)."

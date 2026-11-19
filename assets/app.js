(() => {
  'use strict';

  const DATA = window.PENTECOSTES_DATA;
  if (!DATA || !Array.isArray(DATA.lots)) {
    console.error('No se encontró window.PENTECOSTES_DATA');
    return;
  }

  const COP = new Intl.NumberFormat('es-CO', {
    style: 'currency',
    currency: 'COP',
    maximumFractionDigits: 0
  });
  const NUM = new Intl.NumberFormat('es-CO', { maximumFractionDigits: 2 });

  const formatCOP = (val) => COP.format(Math.round(val || 0));

  const MONTHS_ES = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];

  function addMonthsFormatted(baseDate, monthsToAdd) {
    const d = new Date(baseDate.getFullYear(), baseDate.getMonth() + monthsToAdd, 1);
    return `${MONTHS_ES[d.getMonth()]} ${d.getFullYear()}`;
  }

  // Official Pricing Formula (Base 90 m²: $30M Financiado / $25M Contado)
  const RULES = DATA.project.pricingRules;
  function calcPricesByArea(areaM2) {
    const a = Math.max(1, Number(areaM2) || 90);
    const financiado = Math.round(a * (RULES.baseFinanciado / RULES.baseAreaM2));
    const contado = Math.round(a * (RULES.baseContado / RULES.baseAreaM2));
    return {
      area: a,
      financiado,
      contado,
      ahorro: financiado - contado
    };
  }

  // State Management
  const state = {
    viewMode: 'comercial', // 'comercial' | 'auditoria'
    pulseAvailable: false,
    filterManzana: 'ALL',
    filterStatus: 'ALL',
    filterArea: 'ALL',
    selectedLotId: null,
    cartIds: new Set(),

    // Viewport state (SVG coordinates 0..8702 x 0..11811)
    vb: { x: 1220, y: 1820, w: 6150, h: 8750 },
    defaultVb: { x: 1220, y: 1820, w: 6150, h: 8750 },
    animFrame: null,

    // Calculator state
    calcSource: 'lot', // 'lot' | 'custom' | 'cart'
    calcLotId: null,
    customArea: 90,
    payMode: 'financiado', // 'financiado' | 'contado'
    cuotaInicial: 10000000,
    separacion: 1000000,
    plazoInicial: 1,
    driver: 'cuota', // 'cuota' | 'plazo'
    cuotaMensual: 350000,
    plazoMeses: 57,
    abonoSemestral: 0,

    // Inventory table state
    tableSearch: '',
    tableStatus: 'COTIZABLES',
    tablePage: 1,
    tablePageSize: 18,

    // Ecosystem filter
    ecoCat: 'ALL'
  };

  // Lookup Maps
  const lotsById = new Map();
  const polyElemById = new Map();
  const lotsByManzana = new Map();

  DATA.lots.forEach((lot) => {
    lotsById.set(lot.id, lot);
    const mzKey = String(lot.manzana);
    if (!lotsByManzana.has(mzKey)) lotsByManzana.set(mzKey, []);
    lotsByManzana.get(mzKey).push(lot);
  });

  // DOM References & Hybrid 60/120 FPS Map Engine Instance
  const svg = document.getElementById('masterplanSvg');
  const mapViewport = document.getElementById('mapViewport');
  const viewerShell = document.getElementById('viewerShell');
  const tooltip = document.getElementById('lotTooltip');
  let mapEngine = null;

  // =========================================================================
  // 1. INITIALIZE HERO KPIs & POLYGON SVG ELEMENTS WITH ATTRIBUTES
  // =========================================================================
  function initHeroStats() {
    const total = DATA.lots.length;
    const sold = DATA.lots.filter((l) => l.status === 'VENDIDO').length;
    const avail = DATA.lots.filter((l) => l.status === 'DISPONIBLE' || l.status === 'LIBERADO').length;
    const proc = DATA.lots.filter((l) => l.status === 'PROCESO').length;

    const soldPct = ((sold / total) * 100).toFixed(1).replace('.', ',');
    document.getElementById('heroSoldPct').textContent = `${soldPct}% Vendido`;
    document.getElementById('heroBarSold').style.width = `${(sold / total) * 100}%`;
    document.getElementById('heroBarProc').style.width = `${(proc / total) * 100}%`;
    document.getElementById('heroBarAvail').style.width = `${(avail / total) * 100}%`;

    document.getElementById('kpiTotalLots').textContent = total;
    document.getElementById('kpiSoldLots').textContent = sold;
    document.getElementById('kpiAvailLots').textContent = avail;
    document.getElementById('kpiProcLots').textContent = proc;
  }

  function rawSlug(rawStatus) {
    if (!rawStatus) return 'vacio';
    const s = rawStatus.toUpperCase();
    if (s.includes('CLAUSULA')) return 'clausula';
    if (s.includes('DEVOLUCION')) return 'devolucion';
    if (s.includes('CAMBIO') || s.includes('REUBICADO')) return 'reubicado';
    if (s.includes('CESION')) return 'cesion';
    if (s.includes('SEPARADO') || s.includes('PENDIENTE')) return 'separado';
    if (s.includes('VENDIDO')) return 'vendido';
    return 'otro';
  }

  function initHybridMapEngine() {
    mapEngine = new window.PentecostesHybridEngine({
      viewportEl: mapViewport,
      canvasEl: document.getElementById('terrainHybridCanvas'),
      semanticSvgEl: svg,
      minimapCanvasEl: document.getElementById('minimapCanvas'),
      telemetryEl: document.getElementById('perfTelemetryPill'),
      worldW: DATA.mapConfig.canvasWidth || 8702,
      worldH: DATA.mapConfig.canvasHeight || 11811,
      initialBounds: { x: 1220, y: 1820, w: 6150, h: 8750 },
      lots: DATA.lots,
      manzanaCenters: DATA.mapConfig.manzanaCenters || [],
      tilesBasePath: 'assets/tiles',
      filterPredicate: lotMatchesFilters,
      onHoverLot: (lot, sx, sy) => {
        if (!lot) {
          tooltip.classList.add('hidden');
          return;
        }
        const badgeBg =
          lot.status === 'VENDIDO' ? '#dc2626' :
          lot.status === 'PROCESO' ? '#f59e0b' : '#16a34a';

        const mzText = lot.isSuperLote ? `Super Lote ${lot.lote}` : `Mz ${lot.manzana} · Lote ${lot.lote}`;
        const cornerTag = lot.esEsquinero ? ' · Esquinero' : '';
        tooltip.innerHTML = `
          <div class="tt-head">
            <strong>${mzText}</strong>
            <span class="tt-badge" style="background:${badgeBg};color:#ffffff">${lot.statusLabel}</span>
          </div>
          <div class="tt-row"><span>Área:</span><strong>${lot.area} m²${cornerTag}</strong></div>
          <div class="tt-row"><span>Contado:</span><strong>${formatCOP(lot.precioContado)}</strong></div>
          <div class="tt-row"><span>Financiado:</span><strong>${formatCOP(lot.precioFinanciado)}</strong></div>
          <div class="tt-row"><span>Cuota fija:</span><strong style="color:#34d399">${formatCOP(lot.cuotaMensual)}/mes</strong></div>
        `;
        tooltip.classList.remove('hidden');

        const vpW = mapViewport.clientWidth;
        const vpH = mapViewport.clientHeight;
        let left = sx + 16;
        let top = sy + 16;
        if (left + 230 > vpW) left = sx - 230;
        if (top + 140 > vpH) top = sy - 140;
        tooltip.style.left = `${Math.max(8, left)}px`;
        tooltip.style.top = `${Math.max(8, top)}px`;
      },
      onSelectLot: (lot) => {
        selectLot(lot.id, { syncCalculator: true, zoom: false });
      },
      onSelectManzana: (mzStr) => {
        document.getElementById('filterManzanaSelect').value = mzStr;
        state.filterManzana = mzStr;
        applyMapFilters();
        zoomToManzana(mzStr);
      }
    });

    // Populate polyElemById from semantic SVG built by hybrid engine
    DATA.lots.forEach((l) => {
      const el = mapEngine.getPolygonDomElement(l.id);
      if (el) polyElemById.set(l.id, el);
    });

    // Zoom & HUD Buttons
    document.getElementById('btnZoomIn').addEventListener('click', () => mapEngine.zoomStep(1.42));
    document.getElementById('btnZoomOut').addEventListener('click', () => mapEngine.zoomStep(0.70));
    document.getElementById('btnZoomReset').addEventListener('click', () => mapEngine.resetCamera(true));

    document.getElementById('polyOpacityRange').addEventListener('input', (e) => {
      const val = Number(e.target.value) / 100;
      document.documentElement.style.setProperty('--poly-opacity', val.toFixed(2));
      mapEngine.setPolyOpacity(val);
    });

    const btnPulse = document.getElementById('btnPulseAvailable');
    btnPulse.addEventListener('click', () => {
      state.pulseAvailable = !state.pulseAvailable;
      btnPulse.classList.toggle('active', state.pulseAvailable);
      mapEngine.setPulseAvailable(state.pulseAvailable);
    });

    const btnFs = document.getElementById('btnFullscreenMap');
    btnFs.addEventListener('click', () => {
      viewerShell.classList.toggle('is-fullscreen');
      btnFs.querySelector('span').textContent = viewerShell.classList.contains('is-fullscreen')
        ? 'Salir Pantalla Completa'
        : 'Pantalla Completa';
      setTimeout(() => mapEngine.requestRender(), 40);
    });
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && viewerShell.classList.contains('is-fullscreen')) {
        viewerShell.classList.remove('is-fullscreen');
        btnFs.querySelector('span').textContent = 'Pantalla Completa';
        setTimeout(() => mapEngine.requestRender(), 40);
      }
    });
  }

  function zoomToLot(lot, tight = true) {
    if (mapEngine) mapEngine.flyToLot(lot, tight);
  }

  function zoomToManzana(mzKey) {
    if (!mapEngine) return;
    if (mzKey === 'ALL') {
      mapEngine.resetCamera(true);
      return;
    }
    const list = lotsByManzana.get(String(mzKey));
    if (!list || !list.length) return;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    list.forEach((l) => {
      l.pts.forEach((pt) => {
        if (pt[0] < minX) minX = pt[0];
        if (pt[0] > maxX) maxX = pt[0];
        if (pt[1] < minY) minY = pt[1];
        if (pt[1] > maxY) maxY = pt[1];
      });
    });
    mapEngine.flyToBounds(minX, minY, maxX, maxY, 260);
  }

  // =========================================================================
  // 3. LEGEND, VIEW MODES & MAP FILTERS
  // =========================================================================
  function renderLegend() {
    const container = document.getElementById('legendItemsContainer');
    const items = state.viewMode === 'comercial'
      ? [
          { key: 'ALL', label: 'Todos (839)', color: '#94a3b8' },
          { key: 'DISPONIBLE', label: 'Disponible Inmediato (24)', color: '#10b981' },
          { key: 'LIBERADO', label: 'Liberado / Reasignación (95)', color: '#14b8a6' },
          { key: 'PROCESO', label: 'Separado / En Trámite (25)', color: '#f59e0b' },
          { key: 'VENDIDO', label: 'Vendido (695)', color: '#ef4444' }
        ]
      : [
          { key: 'ALL', label: 'Todos (839)', color: '#94a3b8' },
          { key: 'DISPONIBLE', label: 'Vacío en Excel (24)', color: '#10b981' },
          { key: 'RAW_DEVOLUCION', label: 'Devolución (22)', color: '#22c55e' },
          { key: 'RAW_CLAUSULA', label: 'Cláusula (67)', color: '#0ea5e9' },
          { key: 'RAW_REUBICADO', label: 'Cambio / Reubicado (6)', color: '#a855f7' },
          { key: 'PROCESO', label: 'Cesión / Separado / Pend. (25)', color: '#f59e0b' },
          { key: 'VENDIDO', label: 'Vendido (695)', color: '#ef4444' }
        ];

    const countFor = (key) => {
      if (key === 'ALL') return DATA.lots.length;
      if (key.startsWith('RAW_')) return DATA.lots.filter((l) => rawSlug(l.rawStatus) === key.slice(4).toLowerCase()).length;
      return DATA.lots.filter((l) => l.status === key).length;
    };
    items.forEach((it) => { it.label = it.label.replace(/\(\d+\)/, `(${countFor(it.key)})`); });

    container.innerHTML = items.map((it) => `
      <button type="button" class="legend-chip ${state.filterStatus === it.key ? 'active' : ''}" data-legend-filter="${it.key}">
        <span class="legend-swatch" style="background:${it.color}"></span>
        <span>${it.label}</span>
      </button>
    `).join('');

    container.querySelectorAll('.legend-chip').forEach((btn) => {
      btn.addEventListener('click', () => {
        const k = btn.dataset.legendFilter;
        state.filterStatus = state.filterStatus === k ? 'ALL' : k;
        const sel = document.getElementById('filterStatusSelect');
        if ([...sel.options].some((o) => o.value === state.filterStatus)) {
          sel.value = state.filterStatus;
        }
        renderLegend();
        applyMapFilters();
      });
    });
  }

  function lotMatchesFilters(lot) {
    if (state.filterManzana !== 'ALL' && String(lot.manzana) !== state.filterManzana) {
      return false;
    }
    if (state.filterStatus !== 'ALL') {
      if (state.filterStatus === 'COTIZABLES') {
        if (lot.status !== 'DISPONIBLE' && lot.status !== 'LIBERADO') return false;
      } else if (state.filterStatus.startsWith('RAW_')) {
        const slug = state.filterStatus.replace('RAW_', '').toLowerCase();
        if (rawSlug(lot.rawStatus) !== slug) return false;
      } else if (lot.status !== state.filterStatus) {
        return false;
      }
    }
    if (state.filterArea !== 'ALL') {
      if (state.filterArea === '90' && lot.area !== 90) return false;
      if (state.filterArea === '91-170' && (lot.area <= 90 || lot.area > 200)) return false;
      if (state.filterArea === 'SUPER' && !lot.isSuperLote) return false;
    }
    return true;
  }

  function applyMapFilters() {
    if (mapEngine) mapEngine.invalidateFilters();
  }

  function initHudControls() {
    // Populate Manzana Select
    const mzSel = document.getElementById('filterManzanaSelect');
    for (let m = 1; m <= 28; m++) {
      const list = lotsByManzana.get(String(m)) || [];
      const avail = list.filter((l) => l.status !== 'VENDIDO').length;
      const opt = document.createElement('option');
      opt.value = String(m);
      opt.textContent = `Manzana ${String(m).padStart(2, '0')} (${list.length} lotes · ${avail} no vendidos)`;
      mzSel.appendChild(opt);
    }
    const slOpt = document.createElement('option');
    slOpt.value = 'SUPER LOTE';
    slOpt.textContent = 'Super Lotes SL-01 a SL-17 (715–1.470 m²)';
    mzSel.appendChild(slOpt);

    mzSel.addEventListener('change', () => {
      state.filterManzana = mzSel.value;
      applyMapFilters();
      zoomToManzana(mzSel.value);
    });

    document.getElementById('filterStatusSelect').addEventListener('change', (e) => {
      state.filterStatus = e.target.value;
      renderLegend();
      applyMapFilters();
    });

    document.getElementById('filterAreaSelect').addEventListener('change', (e) => {
      state.filterArea = e.target.value;
      applyMapFilters();
    });

    // View mode buttons
    document.querySelectorAll('[data-view-mode]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.viewMode = btn.dataset.viewMode;
        document.querySelectorAll('[data-view-mode]').forEach((b) => b.classList.toggle('active', b === btn));
        if (mapEngine) mapEngine.setViewMode(state.viewMode);
        state.filterStatus = 'ALL';
        document.getElementById('filterStatusSelect').value = 'ALL';
        renderLegend();
        applyMapFilters();
      });
    });

    // Quick Search (supports "1-17", "MZ01-L17", "14 31", "SL-3", etc.)
    const searchInput = document.getElementById('mapSearchInput');
    function executeQuickSearch() {
      const raw = searchInput.value.trim().toUpperCase();
      if (!raw) return;

      let found = lotsById.get(raw);
      if (!found) {
        const slMatch = raw.match(/SL\s*-?\s*(\d+)/);
        if (slMatch) {
          const code = `SL-${String(parseInt(slMatch[1], 10)).padStart(2, '0')}`;
          found = lotsById.get(code);
        } else {
          const nums = raw.match(/(\d+)\D+(\d+)/);
          if (nums) {
            const mz = parseInt(nums[1], 10);
            const lt = parseInt(nums[2], 10);
            const code = `MZ${String(mz).padStart(2, '0')}-L${String(lt).padStart(2, '0')}`;
            found = lotsById.get(code);
          }
        }
      }
      if (found) {
        selectLot(found.id, { syncCalculator: true, zoom: true });
      } else {
        searchInput.style.borderColor = '#ef4444';
        setTimeout(() => { searchInput.style.borderColor = ''; }, 900);
      }
    }

    document.getElementById('btnMapSearchGo').addEventListener('click', executeQuickSearch);
    searchInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') executeQuickSearch();
    });

    // Quick Available Suggestions in Empty Inspector
    const quickChips = document.getElementById('quickAvailableChips');
    const sampleAvail = DATA.lots.filter((l) => l.status === 'DISPONIBLE').slice(0, 8);
    quickChips.innerHTML = sampleAvail.map((l) => `
      <button type="button" class="qp-chip" data-pick-id="${l.id}">
        Mz ${l.manzana} · L${l.lote} (${l.area}m²)
      </button>
    `).join('');
    quickChips.querySelectorAll('.qp-chip').forEach((b) => {
      b.addEventListener('click', () => selectLot(b.dataset.pickId, { syncCalculator: true, zoom: true }));
    });
  }

  // =========================================================================
  // 4. LOT SELECTION INSPECTOR & MULTI-LOT CART
  // =========================================================================
  function selectLot(lotId, opts = { syncCalculator: true, zoom: false }) {
    const lot = lotsById.get(lotId);
    if (!lot) return;

    state.selectedLotId = lot.id;
    const poly = polyElemById.get(lot.id);
    if (mapEngine) mapEngine.setSelectedLot(lot);

    if (opts.zoom) zoomToLot(lot, true);

    // Populate Inspector Card
    document.getElementById('inspectorEmpty').classList.add('hidden');
    document.getElementById('inspectorDetail').classList.remove('hidden');

    document.getElementById('inspCode').textContent = lot.id;
    document.getElementById('inspTitle').textContent = lot.isSuperLote
      ? `Super Lote ${String(lot.lote).padStart(2, '0')}`
      : `Manzana ${lot.manzana} · Lote ${lot.lote}`;

    const pill = document.getElementById('inspStatusPill');
    pill.textContent = lot.statusLabel;
    pill.className = `status-pill pill-st-${lot.status.toLowerCase()}`;

    document.getElementById('inspArea').textContent = `${lot.area} m²`;
    document.getElementById('inspDims').textContent = lot.dimensions;
    document.getElementById('inspM2Contado').textContent = `${formatCOP(lot.precioContado / lot.area)}/m²`;
    document.getElementById('inspRawStatus').textContent = lot.rawStatus || 'Disponible (Libre)';

    document.getElementById('inspSaveTag').textContent = `Ahorras ${formatCOP(lot.ahorroContado)}`;
    document.getElementById('inspPriceContado').textContent = formatCOP(lot.precioContado);
    document.getElementById('inspPriceFinanciado').textContent = formatCOP(lot.precioFinanciado);
    document.getElementById('inspInicial').textContent = formatCOP(lot.cuotaInicial);
    document.getElementById('inspSaldo').textContent = formatCOP(lot.saldoFinanciar);
    document.getElementById('inspCuota').textContent = `${formatCOP(lot.cuotaMensual)} / mes`;

    const fullInst = Math.floor(lot.saldoFinanciar / lot.cuotaMensual);
    const rem = lot.saldoFinanciar - fullInst * lot.cuotaMensual;
    document.getElementById('inspNumCuotas').textContent = rem > 0
      ? `${fullInst} cuotas + ajuste ${formatCOP(rem)}`
      : `${fullInst} cuotas exactas`;

    // Show actual SVG DOM element attributes
    if (poly) {
      const attrsText = [
        `<polygon id="${poly.id}"`,
        `  data-id="${poly.dataset.id}"`,
        `  data-manzana="${poly.dataset.manzana}"`,
        `  data-lote="${poly.dataset.lote}"`,
        `  data-area="${poly.dataset.area}"`,
        `  data-estado="${poly.dataset.estado}"`,
        `  data-estado-excel="${poly.dataset.estadoExcel}"`,
        `  data-precio-contado="${poly.dataset.precioContado}"`,
        `  data-precio-financiado="${poly.dataset.precioFinanciado}"`,
        `  data-cuota-inicial="${poly.dataset.cuotaInicial}"`,
        `  data-cuota-mensual="${poly.dataset.cuotaMensual}" />`
      ].join('\n');
      document.getElementById('inspDomAttrsPreview').textContent = attrsText;
    }

    updateCartButtonsUI();

    fillTechSheet(lot);
    const waMsg = encodeURIComponent(
      `Hola Inversora Maruz, estoy viendo en el plano interactivo de Urbanización Pentecostés el lote ${lot.id} (${lot.isSuperLote ? 'Super Lote ' + lot.lote : 'Manzana ' + lot.manzana + ' Lote ' + lot.lote}) de ${lot.area} m² [Estado: ${lot.statusLabel}]. Valor contado: ${formatCOP(lot.precioContado)} | Financiado: ${formatCOP(lot.precioFinanciado)} (Inicial ${formatCOP(lot.cuotaInicial)} + cuotas de ${formatCOP(lot.cuotaMensual)}). ¿Me brindan asesoría?`
    );
    document.getElementById('btnWhatsappLot').href = waUrl(waMsg);

    if (opts.syncCalculator && state.cartIds.size === 0) {
      loadLotIntoCalculator(lot.id, false);
    }
  }

  function updateCartButtonsUI() {
    if (mapEngine) mapEngine.setCartIds(state.cartIds);
    const btnToggle = document.getElementById('btnToggleCartLot');
    if (state.selectedLotId && state.cartIds.has(state.selectedLotId)) {
      btnToggle.textContent = '✓ En Comparador (Quitar)';
    } else {
      btnToggle.textContent = '➕ Agregar a Comparador';
    }

    const bar = document.getElementById('multiCartBar');
    if (state.cartIds.size > 0) {
      bar.classList.remove('hidden');
      const items = [...state.cartIds].map((id) => lotsById.get(id)).filter(Boolean);
      const sumArea = items.reduce((acc, l) => acc + l.area, 0);
      document.getElementById('cartCountBadge').textContent = String(items.length);
      document.getElementById('cartSummaryText').textContent = `${items.length} lote(s) · ${sumArea} m² totales`;
    } else {
      bar.classList.add('hidden');
    }
  }

  function initInspectorActions() {
    document.getElementById('btnLoadIntoCalculator').addEventListener('click', () => {
      if (!state.selectedLotId) return;
      state.cartIds.clear();
      DATA.lots.forEach((l) => polyElemById.get(l.id)?.classList.remove('in-cart'));
      updateCartButtonsUI();
      loadLotIntoCalculator(state.selectedLotId, true);
    });

    document.getElementById('btnToggleCartLot').addEventListener('click', () => {
      if (!state.selectedLotId) return;
      const poly = polyElemById.get(state.selectedLotId);
      if (state.cartIds.has(state.selectedLotId)) {
        state.cartIds.delete(state.selectedLotId);
        poly?.classList.remove('in-cart');
      } else {
        state.cartIds.add(state.selectedLotId);
        poly?.classList.add('in-cart');
      }
      updateCartButtonsUI();
    });

    document.getElementById('btnSendCartToCalc').addEventListener('click', () => {
      if (state.cartIds.size === 0) return;
      state.calcSource = 'cart';
      const items = [...state.cartIds].map((id) => lotsById.get(id)).filter(Boolean);
      // Scale suggested initial payment proportionally to number of lots ($10M per lot)
      state.cuotaInicial = 10000000 * items.length;
      state.cuotaMensual = 350000 * items.length;
      syncCalculatorInputsUI();
      recalculateAndRender();
      document.getElementById('calculadora').scrollIntoView({ behavior: 'smooth' });
    });

    document.getElementById('btnClearCart').addEventListener('click', () => {
      state.cartIds.clear();
      DATA.lots.forEach((l) => polyElemById.get(l.id)?.classList.remove('in-cart'));
      if (state.calcSource === 'cart') state.calcSource = 'lot';
      updateCartButtonsUI();
      recalculateAndRender();
    });
  }

  // =========================================================================
  // 5. EVERIA-STYLE DYNAMIC CALCULATOR ENGINE
  // =========================================================================
  function populateCalcSelectors() {
    const mzSel = document.getElementById('calcManzanaSelect');
    mzSel.innerHTML = '';
    for (let m = 1; m <= 28; m++) {
      const opt = document.createElement('option');
      opt.value = String(m);
      opt.textContent = `Manzana ${String(m).padStart(2, '0')}`;
      mzSel.appendChild(opt);
    }
    const slOpt = document.createElement('option');
    slOpt.value = 'SUPER LOTE';
    slOpt.textContent = 'Super Lotes (SL-01..SL-17)';
    mzSel.appendChild(slOpt);

    // Pick first available lot (e.g. MZ01-L17) as default
    const defaultLot = DATA.lots.find((l) => l.status === 'DISPONIBLE') || DATA.lots[0];
    state.calcLotId = defaultLot.id;
    mzSel.value = String(defaultLot.manzana);
    populateCalcLotesForManzana(String(defaultLot.manzana), defaultLot.id);

    mzSel.addEventListener('change', () => {
      const list = lotsByManzana.get(mzSel.value) || [];
      const preferred = list.find((l) => l.status !== 'VENDIDO') || list[0];
      if (preferred) {
        state.calcLotId = preferred.id;
        state.calcSource = 'lot';
        populateCalcLotesForManzana(mzSel.value, preferred.id);
        recalculateAndRender();
      }
    });

    document.getElementById('calcLoteSelect').addEventListener('change', (e) => {
      state.calcLotId = e.target.value;
      state.calcSource = 'lot';
      recalculateAndRender();
    });

    document.getElementById('btnFocusSelectedOnMap').addEventListener('click', () => {
      if (!state.calcLotId) return;
      selectLot(state.calcLotId, { syncCalculator: false, zoom: true });
      document.getElementById('visor-mapa').scrollIntoView({ behavior: 'smooth' });
    });
  }

  function populateCalcLotesForManzana(mzKey, selectedId) {
    const ltSel = document.getElementById('calcLoteSelect');
    const list = lotsByManzana.get(String(mzKey)) || [];
    ltSel.innerHTML = list.map((l) => {
      const tag = l.status === 'VENDIDO' ? '🔴 Vendido' : l.status === 'PROCESO' ? '🟡 En Trámite' : '🟢 Disponible';
      const lbl = l.isSuperLote ? `SL-${String(l.lote).padStart(2, '0')}` : `Lote ${String(l.lote).padStart(2, '0')}`;
      return `<option value="${l.id}" ${l.id === selectedId ? 'selected' : ''}>${lbl} · ${l.area} m² (${tag})</option>`;
    }).join('');
  }

  function loadLotIntoCalculator(lotId, scroll) {
    const lot = lotsById.get(lotId);
    if (!lot) return;
    state.calcSource = 'lot';
    state.calcLotId = lot.id;
    document.getElementById('tabCalcByLot').classList.add('active');
    document.getElementById('tabCalcCustomArea').classList.remove('active');
    document.getElementById('calcLotSelectorBox').classList.remove('hidden');
    document.getElementById('calcCustomAreaBox').classList.add('hidden');

    document.getElementById('calcManzanaSelect').value = String(lot.manzana);
    populateCalcLotesForManzana(String(lot.manzana), lot.id);

    // Ensure cuotaInicial fits lot price cleanly
    if (state.cuotaInicial >= lot.precioFinanciado) {
      state.cuotaInicial = 10000000;
    }
    syncCalculatorInputsUI();
    recalculateAndRender();
    if (scroll) {
      document.getElementById('calculadora').scrollIntoView({ behavior: 'smooth' });
    }
  }

  function syncCalculatorInputsUI() {
    document.getElementById('calcInicialInput').value = state.cuotaInicial;
    document.getElementById('calcInicialSlider').value = state.cuotaInicial;
    document.getElementById('calcCuotaInput').value = state.cuotaMensual;
    document.getElementById('calcCuotaSlider').value = Math.min(2000000, state.cuotaMensual);
    document.getElementById('calcMesesInput').value = state.plazoMeses;
    document.getElementById('calcMesesSlider').value = state.plazoMeses;
    document.getElementById('customAreaInput').value = state.customArea;
    document.getElementById('customAreaSlider').value = Math.min(500, state.customArea);
  }

  function getActiveSubject() {
    if (state.calcSource === 'cart' && state.cartIds.size > 0) {
      const items = [...state.cartIds].map((id) => lotsById.get(id)).filter(Boolean);
      const totalArea = items.reduce((s, l) => s + l.area, 0);
      const codes = items.map((l) => l.id).join(', ');
      return {
        title: `Paquete ${items.length} Lotes (${codes})`,
        subtitle: `Área combinada: ${totalArea} m²`,
        area: totalArea,
        statusInfo: `${items.length} polígonos seleccionados`
      };
    }
    if (state.calcSource === 'custom') {
      return {
        title: `Simulación Personalizada (${state.customArea} m²)`,
        subtitle: `Cálculo proporcional sobre base oficial de 90 m²`,
        area: state.customArea,
        statusInfo: 'Simulación libre por metraje'
      };
    }
    const lot = lotsById.get(state.calcLotId) || DATA.lots[0];
    const title = lot.isSuperLote
      ? `Super Lote ${String(lot.lote).padStart(2, '0')} (${lot.area} m²)`
      : `Manzana ${lot.manzana} · Lote ${lot.lote} (${lot.area} m²)`;
    return {
      title,
      subtitle: `Área oficial: ${lot.area} m² · ${lot.dimensions} · ${lot.statusLabel}`,
      area: lot.area,
      statusInfo: lot.statusLabel,
      lot
    };
  }

  function recalculateAndRender() {
    const subj = getActiveSubject();
    const prices = calcPricesByArea(subj.area);

    // Update Banner if in lot/cart mode
    if (state.calcSource !== 'custom') {
      document.getElementById('calcBannerTitle').textContent = subj.title;
      document.getElementById('calcBannerSub').textContent = subj.subtitle;
    }

    // Update Inicial Slider max dynamically (up to 90% of financiado price)
    const maxInicial = Math.max(10000000, Math.floor((prices.financiado * 0.9) / 500000) * 500000);
    const iniSlider = document.getElementById('calcInicialSlider');
    iniSlider.max = String(maxInicial);
    if (state.cuotaInicial > prices.financiado - 500000) {
      state.cuotaInicial = Math.max(1000000, prices.financiado - 1000000);
      document.getElementById('calcInicialInput').value = state.cuotaInicial;
      iniSlider.value = state.cuotaInicial;
    }

    document.getElementById('resHeaderTitle').textContent = subj.title;
    document.getElementById('resContadoRef').textContent = `${formatCOP(prices.contado)} COP`;
    const savePct = ((prices.ahorro / prices.financiado) * 100).toFixed(1).replace('.', ',');
    document.getElementById('resAhorroRef').textContent = `${formatCOP(prices.ahorro)} COP (${savePct}%)`;

    const baseNow = new Date(2026, 10, 18); // Nov 2026
    const schedule = [];

    if (state.payMode === 'contado') {
      document.getElementById('financingControlsWrap').classList.add('hidden');
      document.getElementById('resTotalLabel').textContent = 'Valor Total de Contado';
      document.getElementById('resTotalValue').textContent = formatCOP(prices.contado);
      document.getElementById('resFormulaText').textContent = `${NUM.format(subj.area)} m² × $277.778 / m²`;

      document.getElementById('resMonthlyLabel').textContent = 'Ahorro Directo Obtenido';
      document.getElementById('resMonthlyValue').textContent = formatCOP(prices.ahorro);
      document.getElementById('resInstallmentsText').textContent = 'Pago único de contado · Escrituración directa';

      document.getElementById('barLblInicial').textContent = 'Pago de Contado (100%)';
      document.getElementById('barLblSaldo').textContent = 'Saldo Financiado (0%)';
      document.getElementById('barSegInicial').style.width = '100%';
      document.getElementById('barSegSaldo').style.width = '0%';

      const sep = Math.min(state.separacion, prices.contado);
      const remContado = prices.contado - sep;
      document.getElementById('resSeparacionVal').textContent = `${formatCOP(sep)} COP`;
      document.getElementById('resRestoInicialVal').textContent = `${formatCOP(remContado)} COP (Contra promesa)`;
      document.getElementById('resSaldoNetoVal').textContent = '$0 COP (Libre de cuotas)';
      document.getElementById('resEndDateVal').textContent = `${addMonthsFormatted(baseNow, 1)} (Pago inmediato)`;

      schedule.push({
        num: 1,
        concept: 'Separación de Lote (Contado)',
        date: addMonthsFormatted(baseNow, 0),
        amount: sep,
        balance: remContado
      });
      if (remContado > 0) {
        schedule.push({
          num: 2,
          concept: 'Cancelación Total Escritura Contado',
          date: addMonthsFormatted(baseNow, 1),
          amount: remContado,
          balance: 0
        });
      }
    } else {
      // FINANCIADO 0% INTERÉS
      document.getElementById('financingControlsWrap').classList.remove('hidden');
      document.getElementById('resTotalLabel').textContent = 'Valor Total Financiado';
      document.getElementById('resTotalValue').textContent = formatCOP(prices.financiado);
      document.getElementById('resFormulaText').textContent = `${NUM.format(subj.area)} m² × $333.333 / m²`;

      const inicial = Math.max(1000000, Math.min(prices.financiado, state.cuotaInicial));
      const saldo = Math.max(0, prices.financiado - inicial);
      const sep = Math.min(inicial, state.separacion);
      const restoInicial = Math.max(0, inicial - sep);

      let monthlyInstallment = state.cuotaMensual;
      if (state.driver === 'plazo') {
        monthlyInstallment = Math.max(50000, Math.ceil(saldo / Math.max(1, state.plazoMeses)));
      }

      // Build exact amortization schedule (0% interest + optional semestral extra payments)
      let runningBalance = prices.financiado;
      let stepNum = 1;
      let monthOffset = 0;

      runningBalance -= sep;
      schedule.push({
        num: stepNum++,
        concept: 'Separación de Terreno',
        date: addMonthsFormatted(baseNow, monthOffset),
        amount: sep,
        balance: runningBalance
      });

      if (restoInicial > 0) {
        const parts = Math.max(1, state.plazoInicial);
        const partVal = Math.round(restoInicial / parts);
        let remIni = restoInicial;
        for (let p = 1; p <= parts; p++) {
          monthOffset++;
          const pay = p === parts ? remIni : partVal;
          remIni -= pay;
          runningBalance -= pay;
          schedule.push({
            num: stepNum++,
            concept: parts === 1 ? 'Completar Cuota Inicial' : `Cuota Inicial (${p}/${parts})`,
            date: addMonthsFormatted(baseNow, monthOffset),
            amount: pay,
            balance: runningBalance
          });
        }
      }

      let regularCount = 0;
      let lastAdjust = 0;
      while (runningBalance > 0 && regularCount < 240) {
        monthOffset++;
        regularCount++;
        let pay = Math.min(runningBalance, monthlyInstallment);
        if (pay < monthlyInstallment) lastAdjust = pay;
        runningBalance -= pay;

        schedule.push({
          num: stepNum++,
          concept: pay < monthlyInstallment ? `Cuota Final de Ajuste #${regularCount}` : `Cuota Fija Mensual #${regularCount}`,
          date: addMonthsFormatted(baseNow, monthOffset),
          amount: pay,
          balance: runningBalance
        });

        if (state.abonoSemestral > 0 && regularCount % 6 === 0 && runningBalance > 0) {
          const extra = Math.min(runningBalance, state.abonoSemestral);
          runningBalance -= extra;
          schedule.push({
            num: stepNum++,
            concept: '⭐ Abono Extraordinario Semestral',
            date: addMonthsFormatted(baseNow, monthOffset),
            amount: extra,
            balance: runningBalance
          });
        }
      }

      document.getElementById('resMonthlyLabel').textContent = 'Cuota Fija Mensual';
      document.getElementById('resMonthlyValue').textContent = formatCOP(monthlyInstallment);

      if (lastAdjust > 0 && regularCount > 1) {
        document.getElementById('resInstallmentsText').textContent =
          `${regularCount - 1} cuotas de ${formatCOP(monthlyInstallment)} + ajuste ${formatCOP(lastAdjust)}`;
      } else {
        document.getElementById('resInstallmentsText').textContent =
          `${regularCount} cuotas mensuales sin intereses`;
      }

      const pctIni = ((inicial / prices.financiado) * 100).toFixed(1);
      const pctSal = (100 - Number(pctIni)).toFixed(1);
      document.getElementById('barLblInicial').textContent = `Cuota Inicial (${pctIni.replace('.', ',')}%)`;
      document.getElementById('barLblSaldo').textContent = `Saldo Financiado (${pctSal.replace('.', ',')}%)`;
      document.getElementById('barSegInicial').style.width = `${pctIni}%`;
      document.getElementById('barSegSaldo').style.width = `${pctSal}%`;

      document.getElementById('resSeparacionVal').textContent = `${formatCOP(sep)} COP`;
      document.getElementById('resRestoInicialVal').textContent = restoInicial > 0
        ? `${formatCOP(restoInicial)} COP (${state.plazoInicial} mes${state.plazoInicial > 1 ? 'es' : ''})`
        : '$0 COP (Cubierta con separación)';
      document.getElementById('resSaldoNetoVal').textContent = `${formatCOP(saldo)} COP`;
      const years = (monthOffset / 12).toFixed(1).replace('.', ',');
      document.getElementById('resEndDateVal').textContent = `${addMonthsFormatted(baseNow, monthOffset)} (~${years} años)`;

      // Build WhatsApp message for Financiado
      const waFin = encodeURIComponent(
        `Hola Inversora Maruz, simulé mi inversión en Urbanización Pentecostés:\n` +
        `• Terreno: ${subj.title}\n` +
        `• Modalidad: Financiado Directo (0% Interés)\n` +
        `• Valor Total: ${formatCOP(prices.financiado)}\n` +
        `• Cuota Inicial: ${formatCOP(inicial)} (Separación: ${formatCOP(sep)})\n` +
        `• Saldo: ${formatCOP(saldo)} en ${regularCount} cuotas de ${formatCOP(monthlyInstallment)}/mes\n` +
        `¿Podemos agendar para separar este terreno?`
      );
      document.getElementById('btnCalcWhatsapp').href = waUrl(waFin);
    }

    if (state.payMode === 'contado') {
      const waCont = encodeURIComponent(
        `Hola Inversora Maruz, quiero cotizar de CONTADO en Urbanización Pentecostés:\n` +
        `• Terreno: ${subj.title}\n` +
        `• Valor Contado: ${formatCOP(prices.contado)} (Ahorro: ${formatCOP(prices.ahorro)})\n` +
        `¿Me confirman disponibilidad inmediata para separar?`
      );
      document.getElementById('btnCalcWhatsapp').href = waUrl(waCont);
    }

    updateReconcileBox(prices, schedule);

    // Render Schedule Table
    document.getElementById('scheduleCountBadge').textContent = `${schedule.length} pagos`;
    document.getElementById('scheduleTableBody').innerHTML = schedule.map((row) => `
      <tr>
        <td>${row.num}</td>
        <td><strong>${row.concept}</strong></td>
        <td>${row.date}</td>
        <td>${formatCOP(row.amount)}</td>
        <td>${formatCOP(row.balance)}</td>
      </tr>
    `).join('');

    // Prepare Formal Printable Quote Sheet
    preparePrintableQuote(subj, prices, schedule);
  }

  function preparePrintableQuote(subj, prices, schedule) {
    const nowStr = new Date().toLocaleDateString('es-CO', { year: 'numeric', month: 'long', day: 'numeric' });
    document.getElementById('pqDate').textContent = `Fecha: ${nowStr}`;
    document.getElementById('pqRef').textContent = `Ref: PENT-${Math.floor(100000 + Math.random() * 900000)}`;

    const rowsHtml = schedule.slice(0, 65).map((r) => `
      <tr>
        <td>${r.num}</td>
        <td>${r.concept}</td>
        <td>${r.date}</td>
        <td>${formatCOP(r.amount)}</td>
        <td>${formatCOP(r.balance)}</td>
      </tr>
    `).join('');

    document.getElementById('pqBodyContent').innerHTML = `
      <div class="pq-grid">
        <div class="pq-box">
          <strong>Unidad / Terreno Cotizado:</strong><br/>
          ${subj.title}<br/>
          <small>${subj.subtitle}</small>
        </div>
        <div class="pq-box">
          <strong>Resumen Económico (${state.payMode === 'contado' ? 'PAGO DE CONTADO' : 'FINANCIADO 0% INTERÉS'}):</strong><br/>
          Valor Contado: <strong>${formatCOP(prices.contado)}</strong> | Valor Financiado: <strong>${formatCOP(prices.financiado)}</strong><br/>
          ${state.payMode === 'financiado'
            ? `Cuota Inicial: <strong>${formatCOP(state.cuotaInicial)}</strong> | Saldo: <strong>${formatCOP(Math.max(0, prices.financiado - state.cuotaInicial))}</strong>`
            : `Ahorro inmediato aplicado: <strong>${formatCOP(prices.ahorro)}</strong>`}
        </div>
      </div>
      <h3>Proyección de Pagos</h3>
      <table class="pq-table">
        <thead>
          <tr><th>#</th><th>Concepto</th><th>Mes Estimado</th><th>Valor Cuota</th><th>Saldo</th></tr>
        </thead>
        <tbody>${rowsHtml}</tbody>
      </table>
    `;
  }

  function initCalculatorEvents() {
    // Source Tabs (Lot vs Custom Area)
    document.getElementById('tabCalcByLot').addEventListener('click', () => {
      state.calcSource = state.cartIds.size > 0 ? 'cart' : 'lot';
      document.getElementById('tabCalcByLot').classList.add('active');
      document.getElementById('tabCalcCustomArea').classList.remove('active');
      document.getElementById('calcLotSelectorBox').classList.remove('hidden');
      document.getElementById('calcCustomAreaBox').classList.add('hidden');
      recalculateAndRender();
    });

    document.getElementById('tabCalcCustomArea').addEventListener('click', () => {
      state.calcSource = 'custom';
      document.getElementById('tabCalcCustomArea').classList.add('active');
      document.getElementById('tabCalcByLot').classList.remove('active');
      document.getElementById('calcCustomAreaBox').classList.remove('hidden');
      document.getElementById('calcLotSelectorBox').classList.add('hidden');
      recalculateAndRender();
    });

    // Custom Area Slider & Input + Presets
    const areaIn = document.getElementById('customAreaInput');
    const areaSl = document.getElementById('customAreaSlider');
    areaIn.addEventListener('input', () => {
      state.customArea = Math.max(40, Number(areaIn.value) || 90);
      areaSl.value = Math.min(500, state.customArea);
      recalculateAndRender();
    });
    areaSl.addEventListener('input', () => {
      state.customArea = Number(areaSl.value);
      areaIn.value = state.customArea;
      recalculateAndRender();
    });
    document.querySelectorAll('[data-area-preset]').forEach((chip) => {
      chip.addEventListener('click', () => {
        document.querySelectorAll('[data-area-preset]').forEach((c) => c.classList.toggle('active', c === chip));
        state.customArea = Number(chip.dataset.areaPreset);
        areaIn.value = state.customArea;
        areaSl.value = Math.min(500, state.customArea);
        recalculateAndRender();
      });
    });

    // Payment Mode Toggle (Financiado vs Contado)
    document.querySelectorAll('[data-pay-mode]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.payMode = btn.dataset.payMode;
        document.querySelectorAll('[data-pay-mode]').forEach((b) => b.classList.toggle('active', b === btn));
        recalculateAndRender();
      });
    });

    // Cuota Inicial Input & Slider
    const iniIn = document.getElementById('calcInicialInput');
    const iniSl = document.getElementById('calcInicialSlider');
    iniIn.addEventListener('input', () => {
      state.cuotaInicial = Math.max(1000000, Number(iniIn.value) || 10000000);
      iniSl.value = state.cuotaInicial;
      recalculateAndRender();
    });
    iniSl.addEventListener('input', () => {
      state.cuotaInicial = Number(iniSl.value);
      iniIn.value = state.cuotaInicial;
      recalculateAndRender();
    });

    document.getElementById('btnResetOfficialTerms').addEventListener('click', () => {
      state.cuotaInicial = 10000000;
      state.cuotaMensual = 350000;
      state.driver = 'cuota';
      document.getElementById('btnDriverCuota').classList.add('active');
      document.getElementById('btnDriverPlazo').classList.remove('active');
      document.getElementById('driverCuotaBox').classList.remove('hidden');
      document.getElementById('driverPlazoBox').classList.add('hidden');
      syncCalculatorInputsUI();
      recalculateAndRender();
    });

    document.getElementById('calcSeparacionInput').addEventListener('change', (e) => {
      state.separacion = Number(e.target.value);
      recalculateAndRender();
    });
    document.getElementById('calcPlazoInicialSelect').addEventListener('change', (e) => {
      state.plazoInicial = Number(e.target.value);
      recalculateAndRender();
    });

    // Driver Tabs (Cuota vs Plazo)
    document.getElementById('btnDriverCuota').addEventListener('click', () => {
      state.driver = 'cuota';
      document.getElementById('btnDriverCuota').classList.add('active');
      document.getElementById('btnDriverPlazo').classList.remove('active');
      document.getElementById('driverCuotaBox').classList.remove('hidden');
      document.getElementById('driverPlazoBox').classList.add('hidden');
      recalculateAndRender();
    });
    document.getElementById('btnDriverPlazo').addEventListener('click', () => {
      state.driver = 'plazo';
      document.getElementById('btnDriverPlazo').classList.add('active');
      document.getElementById('btnDriverCuota').classList.remove('active');
      document.getElementById('driverPlazoBox').classList.remove('hidden');
      document.getElementById('driverCuotaBox').classList.add('hidden');
      recalculateAndRender();
    });

    // Cuota Mensual Slider & Input + Presets
    const cuoIn = document.getElementById('calcCuotaInput');
    const cuoSl = document.getElementById('calcCuotaSlider');
    cuoIn.addEventListener('input', () => {
      state.cuotaMensual = Math.max(150000, Number(cuoIn.value) || 350000);
      cuoSl.value = Math.min(2000000, state.cuotaMensual);
      recalculateAndRender();
    });
    cuoSl.addEventListener('input', () => {
      state.cuotaMensual = Number(cuoSl.value);
      cuoIn.value = state.cuotaMensual;
      recalculateAndRender();
    });
    document.querySelectorAll('[data-cuota-preset]').forEach((chip) => {
      chip.addEventListener('click', () => {
        document.querySelectorAll('[data-cuota-preset]').forEach((c) => c.classList.toggle('active', c === chip));
        state.cuotaMensual = Number(chip.dataset.cuotaPreset);
        cuoIn.value = state.cuotaMensual;
        cuoSl.value = state.cuotaMensual;
        recalculateAndRender();
      });
    });

    // Plazo Meses Slider & Input + Presets
    const mesIn = document.getElementById('calcMesesInput');
    const mesSl = document.getElementById('calcMesesSlider');
    mesIn.addEventListener('input', () => {
      state.plazoMeses = Math.max(1, Math.min(120, Number(mesIn.value) || 57));
      mesSl.value = Math.min(72, state.plazoMeses);
      recalculateAndRender();
    });
    mesSl.addEventListener('input', () => {
      state.plazoMeses = Number(mesSl.value);
      mesIn.value = state.plazoMeses;
      recalculateAndRender();
    });
    document.querySelectorAll('[data-meses-preset]').forEach((chip) => {
      chip.addEventListener('click', () => {
        document.querySelectorAll('[data-meses-preset]').forEach((c) => c.classList.toggle('active', c === chip));
        state.plazoMeses = Number(chip.dataset.mesesPreset);
        mesIn.value = state.plazoMeses;
        mesSl.value = state.plazoMeses;
        recalculateAndRender();
      });
    });

    document.getElementById('calcAbonoSemestral').addEventListener('change', (e) => {
      state.abonoSemestral = Number(e.target.value);
      recalculateAndRender();
    });

    document.getElementById('btnPrintQuote').addEventListener('click', () => {
      window.print();
    });
  }

  // =========================================================================
  // 6. MANZANAS OVERVIEW CARDS & SEARCHABLE INVENTORY TABLE
  // =========================================================================
  function renderManzanaCards() {
    const grid = document.getElementById('manzanasCardsGrid');
    const keys = [];
    for (let m = 1; m <= 28; m++) keys.push(String(m));
    keys.push('SUPER LOTE');

    grid.innerHTML = keys.map((k) => {
      const list = lotsByManzana.get(k) || [];
      const total = list.length;
      const sold = list.filter((l) => l.status === 'VENDIDO').length;
      const cotizables = list.filter((l) => l.status === 'DISPONIBLE' || l.status === 'LIBERADO').length;
      const proc = total - sold - cotizables;

      const title = k === 'SUPER LOTE' ? 'Super Lotes' : `Manzana ${k.padStart(2, '0')}`;
      return `
        <div class="mz-card" data-jump-mz="${k}">
          <div class="mz-card-top">
            <strong>${title}</strong>
            <span class="mz-avail-tag ${cotizables > 0 ? 'has-avail' : 'sold-out'}">
              ${cotizables > 0 ? `${cotizables} cotizable${cotizables === 1 ? '' : 's'}` : '100% colocado'}
            </span>
          </div>
          <div class="mz-mini-bar">
            <div style="width:${(sold / total) * 100}%;background:#ef4444"></div>
            <div style="width:${(proc / total) * 100}%;background:#f59e0b"></div>
            <div style="width:${(cotizables / total) * 100}%;background:#10b981"></div>
          </div>
          <div class="mz-card-meta">
            <span>${sold}/${total} vendidos</span>
            <span>Ver plano ↗</span>
          </div>
        </div>
      `;
    }).join('');

    grid.querySelectorAll('.mz-card').forEach((card) => {
      card.addEventListener('click', () => {
        const mz = card.dataset.jumpMz;
        document.getElementById('filterManzanaSelect').value = mz;
        state.filterManzana = mz;
        applyMapFilters();
        zoomToManzana(mz);
        document.getElementById('visor-mapa').scrollIntoView({ behavior: 'smooth' });
      });
    });
  }

  function getFilteredTableLots() {
    const q = state.tableSearch.trim().toUpperCase();
    return DATA.lots.filter((l) => {
      if (state.tableStatus === 'COTIZABLES') {
        if (l.status !== 'DISPONIBLE' && l.status !== 'LIBERADO') return false;
      } else if (state.tableStatus !== 'ALL' && l.status !== state.tableStatus) {
        return false;
      }
      if (q) {
        const hay = `${l.id} MANZANA ${l.manzana} LOTE ${l.lote} ${l.area}M2 ${l.statusLabel} ${l.rawStatus}`.toUpperCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }

  function renderInventoryTable() {
    const filtered = getFilteredTableLots();
    document.getElementById('tableResultCount').textContent = `Mostrando ${filtered.length} lote(s)`;

    const totalPages = Math.max(1, Math.ceil(filtered.length / state.tablePageSize));
    if (state.tablePage > totalPages) state.tablePage = totalPages;

    const start = (state.tablePage - 1) * state.tablePageSize;
    const slice = filtered.slice(start, start + state.tablePageSize);

    const tbody = document.getElementById('inventoryTableBody');
    tbody.innerHTML = slice.map((l) => `
      <tr>
        <td><code>${l.id}</code></td>
        <td>${l.isSuperLote ? 'SUPER LOTE' : `Manzana ${l.manzana}`}</td>
        <td><strong>${l.lote}</strong></td>
        <td>${l.area} m²</td>
        <td><span class="status-pill pill-st-${l.status.toLowerCase()}">${l.statusLabel}</span></td>
        <td>${l.rawStatus || 'DISPONIBLE'}</td>
        <td><strong>${formatCOP(l.precioContado)}</strong></td>
        <td>${formatCOP(l.precioFinanciado)}</td>
        <td class="text-emerald"><strong>${formatCOP(l.cuotaMensual)}</strong></td>
        <td>
          <button type="button" class="btn btn-ghost btn-xs" data-tbl-locate="${l.id}">📍 Plano</button>
          <button type="button" class="btn btn-primary btn-xs" data-tbl-calc="${l.id}">🧮 Cotizar</button>
        </td>
      </tr>
    `).join('');

    tbody.querySelectorAll('[data-tbl-locate]').forEach((b) => {
      b.addEventListener('click', () => {
        selectLot(b.dataset.tblLocate, { syncCalculator: true, zoom: true });
        document.getElementById('visor-mapa').scrollIntoView({ behavior: 'smooth' });
      });
    });

    tbody.querySelectorAll('[data-tbl-calc]').forEach((b) => {
      b.addEventListener('click', () => {
        selectLot(b.dataset.tblCalc, { syncCalculator: false, zoom: false });
        loadLotIntoCalculator(b.dataset.tblCalc, true);
      });
    });

    // Pagination buttons
    const pag = document.getElementById('tablePagination');
    if (totalPages <= 1) {
      pag.innerHTML = '';
    } else {
      let html = '';
      for (let p = 1; p <= Math.min(totalPages, 12); p++) {
        html += `<button type="button" class="btn ${p === state.tablePage ? 'btn-primary' : 'btn-ghost'} btn-xs" data-page="${p}">${p}</button>`;
      }
      if (totalPages > 12) {
        html += `<span style="padding:4px 8px;color:#6f8ea3;font-size:0.78rem">… de ${totalPages}</span>`;
      }
      pag.innerHTML = html;
      pag.querySelectorAll('[data-page]').forEach((btn) => {
        btn.addEventListener('click', () => {
          state.tablePage = Number(btn.dataset.page);
          renderInventoryTable();
        });
      });
    }
  }

  function initInventoryControls() {
    document.getElementById('tableSearchInput').addEventListener('input', (e) => {
      state.tableSearch = e.target.value;
      state.tablePage = 1;
      renderInventoryTable();
    });

    document.getElementById('tableStatusFilter').addEventListener('change', (e) => {
      state.tableStatus = e.target.value;
      state.tablePage = 1;
      renderInventoryTable();
    });

    document.getElementById('btnExportFilteredCsv').addEventListener('click', () => {
      const rows = getFilteredTableLots();
      const header = ['CODIGO', 'MANZANA', 'LOTE', 'AREA_M2', 'ESTADO_GRUPO', 'ESTADO_EXCEL', 'PRECIO_CONTADO', 'PRECIO_FINANCIADO', 'CUOTA_INICIAL', 'CUOTA_MENSUAL'];
      const csvLines = [header.join(',')];
      rows.forEach((l) => {
        csvLines.push([
          l.id, `"${l.manzana}"`, l.lote, l.area, `"${l.statusLabel}"`, `"${l.rawStatus || 'DISPONIBLE'}"`,
          l.precioContado, l.precioFinanciado, l.cuotaInicial, l.cuotaMensual
        ].join(','));
      });
      const blob = new Blob(['\uFEFF' + csvLines.join('\n')], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `pentecostes-inventario-${state.tableStatus.toLowerCase()}.csv`;
      a.click();
      URL.revokeObjectURL(url);
    });
  }

  // =========================================================================
  // 7. MARUZ ECOSYSTEM PORTFOLIO & KML GPS BOUNDARY VISUALIZER
  // =========================================================================
  function renderKmlBoundarySvg() {
    const kmlSvg = document.getElementById('kmlBoundarySvg');
    const coords = DATA.project.gpsBoundary || [];
    if (!coords.length) return;

    let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
    coords.forEach(([lat, lng]) => {
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    });

    const W = 600, H = 420, pad = 42;
    const spanLng = Math.max(1e-6, maxLng - minLng);
    const spanLat = Math.max(1e-6, maxLat - minLat);
    const scale = Math.min((W - pad * 2) / spanLng, (H - pad * 2) / spanLat);

    const offX = (W - spanLng * scale) / 2;
    const offY = (H - spanLat * scale) / 2;

    const pts = coords.map(([lat, lng]) => {
      const x = offX + (lng - minLng) * scale;
      const y = H - (offY + (lat - minLat) * scale);
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    }).join(' ');

    // Subtle radar grid + real KML polygon
    let gridLines = '';
    for (let x = 60; x < W; x += 60) {
      gridLines += `<line x1="${x}" y1="0" x2="${x}" y2="${H}" stroke="rgba(56,189,248,0.08)" stroke-width="1"/>`;
    }
    for (let y = 60; y < H; y += 60) {
      gridLines += `<line x1="0" y1="${y}" x2="${W}" y2="${y}" stroke="rgba(56,189,248,0.08)" stroke-width="1"/>`;
    }

    kmlSvg.innerHTML = `
      ${gridLines}
      <polygon points="${pts}" fill="rgba(16, 185, 129, 0.22)" stroke="#34d399" stroke-width="3" stroke-linejoin="round" />
      <circle cx="${W / 2}" cy="${H / 2}" r="6" fill="#ffffff" stroke="#10b981" stroke-width="3" />
      <text x="${W / 2}" y="${H / 2 - 14}" fill="#ffffff" font-family="Outfit, sans-serif" font-size="14" font-weight="700" text-anchor="middle">
        URBANIZACIÓN PENTECOSTÉS
      </text>
      <text x="${W / 2}" y="${H / 2 + 22}" fill="#6ee7b7" font-family="JetBrains Mono, monospace" font-size="11" text-anchor="middle">
        5°14'36.24"N · 72°24'35.74"O
      </text>
    `;
  }

  // =========================================================================
  // ETAPA 3 · Contacto, fichas técnicas, control administrativo, caja Everia y Atlas Maruz
  // =========================================================================
  const CFG = window.SITE_CONFIG || {};
  const WA_NUM = String(CFG.whatsapp || '').replace(/\D/g, '');
  function waUrl(encodedText) {
    return WA_NUM
      ? `https://wa.me/${WA_NUM}?text=${encodedText}`
      : `https://wa.me/?text=${encodedText}`;
  }

  function initContact() {
    const msg = encodeURIComponent('Hola Inversora Maruz, quiero información sobre Urbanización Pentecostés.');
    const ribbonWa = document.getElementById('ribbonWa');
    if (ribbonWa) {
      ribbonWa.href = waUrl(msg);
      if (WA_NUM && CFG.whatsappDisplay) ribbonWa.textContent = `WhatsApp ${CFG.whatsappDisplay}`;
    }
    if (CFG.officeAddress) {
      const o = document.getElementById('ribbonOffice');
      if (o) o.textContent = CFG.officeAddress;
      const f = document.getElementById('footerOffice');
      if (f) f.textContent += ` · ${CFG.officeAddress}`;
      const pq = document.getElementById('pqContactLine');
      if (pq) pq.textContent = `Vereda San Rafael de Morichal, Casanare | ${CFG.officeAddress}`;
    }
    const fw = document.getElementById('footerWa');
    if (fw && WA_NUM && CFG.whatsappDisplay) {
      fw.innerHTML = `WhatsApp: <a href="https://wa.me/${WA_NUM}" target="_blank" rel="noopener">${CFG.whatsappDisplay}</a>`;
    }
  }

  // ---- Ficha técnica + enlace compartible ----
  function fillTechSheet(lot) {
    const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
    set('tsRef', lot.fichaRef || lot.id);
    set('tsPerim', lot.perimetroM ? `${NUM.format(lot.perimetroM)} m (aprox.)` : '—');
    set('tsFrenteFondo', lot.frenteM && lot.fondoM ? `${NUM.format(lot.frenteM)} × ${NUM.format(lot.fondoM)} m` : '—');
    set('tsGps', lot.lat ? `${lot.lat}, ${lot.lng} (aprox.)` : '—');
    const l = lot.linderos || {};
    set('tsNorte', l.norte || '—');
    set('tsSur', l.sur || '—');
    set('tsOriente', l.oriente || '—');
    set('tsOccidente', l.occidente || '—');
    const badge = document.getElementById('inspCornerBadge');
    if (badge) badge.classList.toggle('hidden', !lot.esEsquinero);
    try { history.replaceState(null, '', `#lote=${lot.id}`); } catch (e) { /* file:// sin historial */ }
  }

  function initShareButton() {
    const btn = document.getElementById('btnShareLot');
    btn.addEventListener('click', async () => {
      if (!state.selectedLotId) return;
      const url = `${location.href.split('#')[0]}#lote=${state.selectedLotId}`;
      let ok = false;
      try { await navigator.clipboard.writeText(url); ok = true; } catch (e) { /* sin portapapeles */ }
      if (!ok) { window.prompt('Copia el enlace del lote:', url); return; }
      const prev = btn.textContent;
      btn.textContent = '✓ Enlace copiado';
      setTimeout(() => { btn.textContent = prev; }, 1600);
    });
  }

  function openFromHash() {
    const m = location.hash.match(/#lote=([A-Za-z0-9-]+)/);
    if (m && lotsById.has(m[1])) selectLot(m[1], { syncCalculator: true, zoom: true });
  }

  // ---- Control administrativo (estado del lote, solo en este navegador) ----
  const OVERRIDE_KEY = 'pent_status_overrides_v1';
  const originalState = new Map();
  DATA.lots.forEach((l) => originalState.set(l.id, { status: l.status, statusLabel: l.statusLabel }));

  function loadOverrides() {
    try { return JSON.parse(localStorage.getItem(OVERRIDE_KEY) || '{}'); } catch (e) { return {}; }
  }
  function saveOverrides(o) {
    try { localStorage.setItem(OVERRIDE_KEY, JSON.stringify(o)); } catch (e) { /* almacenamiento bloqueado */ }
  }
  function setLotStatus(lot, newStatus) {
    const orig = originalState.get(lot.id);
    if (newStatus === 'VENDIDO') { lot.status = 'VENDIDO'; lot.statusLabel = 'Vendido'; }
    else if (newStatus === 'DISPONIBLE') { lot.status = 'DISPONIBLE'; lot.statusLabel = 'Disponible'; }
    else { lot.status = orig.status; lot.statusLabel = orig.statusLabel; }
    const el = polyElemById.get(lot.id);
    if (el) el.setAttribute('data-estado', lot.status);
  }
  function applyStoredOverrides() {
    const o = loadOverrides();
    Object.keys(o).forEach((id) => { const lot = lotsById.get(id); if (lot) setLotStatus(lot, o[id]); });
  }
  function refreshStatusViews() {
    initHeroStats();
    renderLegend();
    renderManzanaCards();
    renderInventoryTable();
    if (mapEngine) mapEngine.invalidateFilters();
  }
  async function sha256Hex(text) {
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
  }
  function initAdminBox() {
    const msg = document.getElementById('adminMsg');
    const actions = document.getElementById('adminActions');
    const isOk = () => sessionStorage.getItem('pent_admin_ok') === '1';
    const sync = () => actions.classList.toggle('hidden', !isOk());
    sync();

    document.getElementById('btnAdminValidate').addEventListener('click', async () => {
      if (!CFG.adminTokenSha256) {
        msg.textContent = 'Panel deshabilitado: define adminTokenSha256 en assets/site-config.js.';
        return;
      }
      if (!(window.crypto && window.crypto.subtle)) {
        msg.textContent = 'Validar el token requiere HTTPS o localhost.';
        return;
      }
      const hash = await sha256Hex(document.getElementById('adminTokenInput').value);
      if (hash === String(CFG.adminTokenSha256).toLowerCase()) {
        sessionStorage.setItem('pent_admin_ok', '1');
        msg.textContent = 'Token válido. Los cambios se guardan solo en este navegador.';
      } else {
        sessionStorage.removeItem('pent_admin_ok');
        msg.textContent = 'Token incorrecto.';
      }
      sync();
    });

    const change = (st) => {
      if (!isOk() || !state.selectedLotId) return;
      const lot = lotsById.get(state.selectedLotId);
      const o = loadOverrides();
      if (st) o[lot.id] = st; else delete o[lot.id];
      saveOverrides(o);
      setLotStatus(lot, st);
      refreshStatusViews();
      selectLot(lot.id, { syncCalculator: false, zoom: false });
    };
    document.getElementById('btnMarkAvailable').addEventListener('click', () => change('DISPONIBLE'));
    document.getElementById('btnMarkSold').addEventListener('click', () => change('VENDIDO'));
    document.getElementById('btnClearOverride').addEventListener('click', () => change(null));
  }

  // ---- Caja de conciliación estilo Everia ----
  function updateReconcileBox(prices, schedule) {
    const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
    const isContado = state.payMode === 'contado';
    let sep = 0; let resto = 0; let cuotas = 0; let nCuotas = 0; let extras = 0;
    schedule.forEach((r) => {
      if (r.concept.startsWith('Separación')) sep += r.amount;
      else if (r.concept.startsWith('Completar') || r.concept.startsWith('Cuota Inicial') || r.concept.startsWith('Cancelación')) resto += r.amount;
      else {
        cuotas += r.amount;
        if (r.concept.indexOf('Abono') === -1) nCuotas += 1; else extras += 1;
      }
    });
    const total = isContado ? prices.contado : prices.financiado;
    const diff = Math.abs(sep + resto + cuotas - total);

    set('mrSep', formatCOP(sep));
    set('mrResto', formatCOP(resto));
    set('mrRestoLbl', isContado
      ? 'Resto al escriturar'
      : (state.plazoInicial <= 1 ? 'Saldo de la inicial, 30 días' : `Saldo de la inicial, ${state.plazoInicial} pagos`));
    const cuotasRow = document.getElementById('mrCuotasLbl').parentElement;
    cuotasRow.style.display = isContado ? 'none' : '';
    set('mrCuotasLbl', `Las ${nCuotas} cuotas, juntas${extras ? ' + abonos extra' : ''}`);
    set('mrCuotas', formatCOP(cuotas));
    set('mrTotal', formatCOP(total));
    set('mrCheck', diff <= 1 ? '✓' : '⚠');

    const pctEl = document.getElementById('calcInicialPct');
    if (pctEl) {
      pctEl.textContent = isContado
        ? ''
        : ` · ${((Math.min(state.cuotaInicial, prices.financiado) / prices.financiado) * 100).toFixed(1).replace('.', ',')}%`;
    }
  }

  // ---- Atlas Maruz (21 proyectos) ----
  function initAtlas() {
    const A = (window.MARUZ_ATLAS && window.MARUZ_ATLAS.proyectos) || [];
    if (!A.length) return;
    const listEl = document.getElementById('atlasList');
    const svgEl = document.getElementById('atlasSvg');
    const searchEl = document.getElementById('atlasSearch');
    const dlg = document.getElementById('projectDossier');
    const fmtN = (n) => new Intl.NumberFormat('es-CO', { maximumFractionDigits: 2 }).format(n);
    const norm = (s) => String(s).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    let cat = 'ALL';
    let q = '';
    let activeId = null;

    document.getElementById('atlasKpiProj').textContent = A.length;
    document.getElementById('atlasKpiCp').textContent = fmtN(A.reduce((s, p) => s + p.cuotasPartes, 0));

    const W = 600; const H = 560; const pad = 46;
    const lats = A.map((p) => p.lat); const lngs = A.map((p) => p.lng);
    const minLat = Math.min(...lats); const maxLat = Math.max(...lats);
    const minLng = Math.min(...lngs); const maxLng = Math.max(...lngs);
    const sc = Math.min((W - pad * 2) / (maxLng - minLng), (H - pad * 2) / (maxLat - minLat));
    const ox = (W - (maxLng - minLng) * sc) / 2;
    const oy = (H - (maxLat - minLat) * sc) / 2;
    const proj = (p) => ({ x: ox + (p.lng - minLng) * sc, y: H - (oy + (p.lat - minLat) * sc) });

    function matches(p) {
      if (cat !== 'ALL' && p.type !== cat) return false;
      if (q && !norm(`${p.name} ${p.vereda}`).includes(q)) return false;
      return true;
    }

    function renderMap() {
      let g = '';
      for (let lat = Math.ceil(minLat * 10) / 10; lat <= maxLat; lat += 0.1) {
        const y = proj({ lat, lng: minLng }).y;
        g += `<line x1="0" y1="${y.toFixed(1)}" x2="${W}" y2="${y.toFixed(1)}" stroke="rgba(255,252,247,0.08)"/><text x="6" y="${(y - 3).toFixed(1)}" fill="#8f98a5" font-size="9" font-family="Outfit">${lat.toFixed(1)}°N</text>`;
      }
      for (let lng = Math.ceil(minLng * 10) / 10; lng <= maxLng; lng += 0.1) {
        const x = proj({ lat: minLat, lng }).x;
        g += `<line x1="${x.toFixed(1)}" y1="0" x2="${x.toFixed(1)}" y2="${H}" stroke="rgba(255,252,247,0.08)"/><text x="${(x + 3).toFixed(1)}" y="${H - 6}" fill="#8f98a5" font-size="9" font-family="Outfit">${Math.abs(lng).toFixed(1)}°O</text>`;
      }
      const pins = A.map((p) => {
        const c = proj(p);
        const cls = `atlas-pin${matches(p) ? '' : ' is-dim'}${p.id === activeId ? ' is-active' : ''}`;
        return `<g class="${cls}" data-pin="${p.id}" transform="translate(${c.x.toFixed(1)} ${c.y.toFixed(1)})"><title>${p.name}</title><circle r="${p.active ? 14 : 11}"/><text>${p.num}</text></g>`;
      }).join('');
      svgEl.innerHTML = g + pins;
      svgEl.querySelectorAll('[data-pin]').forEach((el) => {
        el.addEventListener('click', () => openDossier(A.find((p) => p.id === el.dataset.pin)));
        el.addEventListener('pointerenter', () => listEl.querySelector(`[data-item="${el.dataset.pin}"]`)?.classList.add('is-hover'));
        el.addEventListener('pointerleave', () => listEl.querySelector(`[data-item="${el.dataset.pin}"]`)?.classList.remove('is-hover'));
      });
    }

    function renderList() {
      listEl.innerHTML = A.filter(matches).map((p) => `
        <button type="button" class="atlas-item${p.id === activeId ? ' is-active' : ''}" data-item="${p.id}">
          <span class="atlas-num">${p.num}</span>
          <span><span class="atlas-name">${p.name}</span><span class="atlas-sub">${p.vereda} · ${p.type}</span></span>
          <span class="atlas-cp">${fmtN(p.cuotasPartes)}</span>
        </button>`).join('') || '<p style="color:#5e6b78;font-size:.85rem">Sin resultados.</p>';
      listEl.querySelectorAll('[data-item]').forEach((el) => {
        el.addEventListener('click', () => openDossier(A.find((p) => p.id === el.dataset.item)));
        el.addEventListener('pointerenter', () => svgEl.querySelector(`[data-pin="${el.dataset.item}"]`)?.classList.add('is-hover'));
        el.addEventListener('pointerleave', () => svgEl.querySelector(`[data-pin="${el.dataset.item}"]`)?.classList.remove('is-hover'));
      });
    }

    function openDossier(p) {
      if (!p) return;
      activeId = p.id;
      renderMap();
      renderList();
      const mapsUrl = `https://www.google.com/maps?q=${p.lat},${p.lng}`;
      const waMsg = encodeURIComponent(`Hola Inversora Maruz, quiero información del proyecto ${p.name} (${p.vereda}).`);
      const toArr = (x) => (Array.isArray(x) ? x : (x ? [x] : []));
      const ofertas = toArr(p.ofertas).map((o) => `
        <div class="offer-card">
          <h4>${o.label}</h4>
          <div class="offer-grid">
            <div><span>Crédito</span><strong>${formatCOP(o.credito)}</strong></div>
            <div><span>Contado</span><strong>${formatCOP(o.contado)}</strong></div>
            <div><span>Inicial</span><strong>${formatCOP(o.inicial)}</strong></div>
            <div><span>Financiación</span><strong>${fmtN(o.nCuotas)} cuotas de ${formatCOP(o.cuota)}</strong></div>
          </div>
          ${o.validar ? '<span class="offer-flag">Dato por validar en el inventario</span>' : ''}
        </div>`).join('') || '<p class="dossier-note">Este proyecto no tiene oferta comercial cargada en el inventario. Consulta con un asesor.</p>';
      const etapas = toArr(p.etapas).length
        ? `<div class="dossier-note"><strong>Etapas:</strong><br>${toArr(p.etapas).map((e) => `${e.nombre} · ${fmtN(e.cuotasPartes)} cuotas partes · ${e.area}`).join('<br>')}</div>`
        : '';
      const pentNote = p.id === 'pentecostes'
        ? '<div class="dossier-note">Se comercializa por cuotas partes. El plano PDF es la referencia más cercana: la zona baja junto al río pudo variar y las cuotas mayores a 2.000 m² pudieron subdividirse.</div>'
        : '';
      document.getElementById('dossierContent').innerHTML = `
        <div class="dossier-hero">
          <button type="button" class="dossier-close" id="dossierClose">Cerrar</button>
          <div class="dossier-watermark">${p.num}</div>
          <span class="section-kicker" style="color:#c4a15a">${p.type} · Vereda ${p.vereda}</span>
          <h3 id="dossierTitle">${p.name}</h3>
        </div>
        <div class="dossier-body">
          <div class="dossier-stats">
            <div class="dossier-stat"><span>Cuotas partes</span><strong>${fmtN(p.cuotasPartes)}</strong></div>
            <div class="dossier-stat"><span>Área más común</span><strong style="font-size:.95rem">${p.areaModal}</strong></div>
            <div class="dossier-stat"><span>Coordenadas</span><strong style="font-size:.95rem">${p.lat}, ${p.lng}</strong></div>
          </div>
          <h4 style="margin-bottom:8px">Ficha comercial</h4>
          ${ofertas}
          ${etapas}
          ${pentNote}
          <div class="dossier-actions">
            ${p.active ? '<button type="button" class="btn btn-primary" id="dossierExplore">🗺️ Explorar polígonos</button><a class="btn btn-outline" href="assets/plano-original-pentecostes.pdf" target="_blank" rel="noopener">Plano PDF</a>' : ''}
            <a class="btn btn-outline" href="${mapsUrl}" target="_blank" rel="noopener">📍 Google Maps</a>
            <a class="btn btn-whatsapp" href="${waUrl(waMsg)}" target="_blank" rel="noopener">💬 Consultar por WhatsApp</a>
          </div>
        </div>`;
      document.getElementById('dossierClose').addEventListener('click', () => dlg.close());
      const ex = document.getElementById('dossierExplore');
      if (ex) ex.addEventListener('click', () => { dlg.close(); document.getElementById('visor-mapa').scrollIntoView({ behavior: 'smooth' }); });
      if (typeof dlg.showModal === 'function') { if (!dlg.open) dlg.showModal(); } else dlg.setAttribute('open', '');
    }

    dlg.addEventListener('click', (e) => { if (e.target === dlg) dlg.close(); });
    searchEl.addEventListener('input', () => { q = norm(searchEl.value.trim()); renderMap(); renderList(); });
    document.querySelectorAll('[data-atlas-cat]').forEach((tab) => {
      tab.addEventListener('click', () => {
        cat = tab.dataset.atlasCat;
        document.querySelectorAll('[data-atlas-cat]').forEach((t) => t.classList.toggle('active', t === tab));
        renderMap();
        renderList();
      });
    });
    renderMap();
    renderList();
  }

  // =========================================================================
  // BOOTSTRAP APPLICATION
  // =========================================================================
  function init() {
    initHybridMapEngine();
    applyStoredOverrides();
    initHeroStats();
    renderLegend();
    initHudControls();
    initInspectorActions();
    initShareButton();
    initAdminBox();
    populateCalcSelectors();
    initCalculatorEvents();
    recalculateAndRender();
    renderManzanaCards();
    renderInventoryTable();
    initInventoryControls();
    initAtlas();
    renderKmlBoundarySvg();
    initContact();
    openFromHash();
    window.addEventListener('hashchange', openFromHash);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

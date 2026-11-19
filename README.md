# Urbanización Pentecostés · Visor interactivo y cotizador

Sitio web estático (HTML + CSS + JavaScript, **sin dependencias, sin build y sin CDN**) con el plano de **Urbanización Pentecostés** (Inversora Maruz S.A.S.) sobre la ortofoto real: **839 polígonos** con atributos, calculadora de financiación estilo Everia y un atlas de los 21 proyectos del listado de Maruz. Incluye intro de marca en video a pantalla completa.

## Ejecutar en local

Abrir `index.html`, o servir la carpeta con cualquier servidor estático:

```
npx serve .          # o: python -m http.server 8765
```

> Con `file://` todo funciona salvo la validación del token administrativo (requiere `https` o `localhost`) y el muestreo de color del video de intro (cae al azul de marca).

## Publicar en GitHub Pages

1. Crear el repositorio en GitHub y subir esta carpeta a la rama `main`.
2. En el repositorio: **Settings → Pages → Build and deployment → Source: GitHub Actions**.
3. El workflow `.github/workflows/pages.yml` publica en cada `push` a `main`. La URL queda en `https://<usuario>.github.io/<repositorio>/`.

Todas las rutas son relativas, así que funciona igual en una subcarpeta, en Netlify, Vercel o Cloudflare Pages (directorio raíz = esta carpeta, sin comando de build).

## Intro de marca

`assets/intro.js` + `assets/media/maruz-intro.mp4` (10 s, ~18,7 MB): se reproduce al abrir la página, a pantalla completa y sin controles; al terminar se desvanece (1,2 s) y revela el sitio mientras éste ya cargó detrás.

- **Sonido:** los navegadores bloquean el audio automático hasta que el usuario interactúa con la página. La intro intenta arrancar con sonido; si el navegador lo impide, arranca en silencio y aparece el botón «Activar sonido» (también se activa con el primer clic, toque o tecla).
- Si el video no arranca en 20 s o falla la carga, la intro se omite. Quien tiene activada la preferencia «reducir movimiento» no la ve.
- Para quitarla: eliminar el bloque `#introOverlay` y la línea `assets/intro.js` de `index.html`.

## Configuración (`assets/site-config.js`)

| Campo | Qué hace |
| :--- | :--- |
| `whatsapp`, `whatsappDisplay` | Número comercial para todos los botones de WhatsApp. |
| `officeAddress` | Dirección visible en cabecera, pie y cotización PDF. |
| `adminTokenSha256` | SHA-256 del token que habilita marcar lotes Disponible/Vendido. Vacío = deshabilitado. |

> **Control administrativo:** los cambios de estado se guardan en `localStorage` del navegador de quien los hace; no es un sistema multiusuario ni seguro (el hash va en el cliente y un token corto se puede deducir del hash). Para estados compartidos y seguros hace falta un backend.

## Estructura

```
index.html                 Página única
assets/
  intro.js, media/maruz-intro.mp4   Intro de marca
  styles.css, theme-editorial.css   Estilos
  fonts.css, fonts/                 Fraunces, Outfit, Plus Jakarta Sans, JetBrains Mono (auto-hospedadas, OFL)
  app.js                   UI, calculadora, inspector, atlas, administración
  map-engine.js            Motor Canvas2D + índice espacial + cámara inercial
  pentecostes-data.js      839 polígonos + atributos (generado)
  atlas-data.js            21 proyectos de Maruz (generado)
  site-config.js           Configuración editable
  tiles/                   Pirámide LOD-0 / LOD-1 / 16 teselas LOD-2
  terreno-pentecostes.jpg  Ortofoto de respaldo
  logo-*.png|jpg, favicon.png, plano-original-pentecostes.pdf
data/pentecostes-inventory.json   Mismo dataset en JSON
tools/                     Scripts PowerShell que regeneran los datos y recursos
.github/workflows/pages.yml
```

## Fuentes de datos

- **Polígonos:** vectorizados desde `1 - PENTECOSTES plano.pdf`. 28 manzanas + 17 super lotes = 839.
- **Áreas:** columna `M2` de `JAVIER NUÑEZ.xlsx` y cuadro de áreas del plano.
- **Estados:** columna `ESTADO` del mismo Excel. 695 `VENDIDO` (rojo).
- **Atlas:** `PROYECTOS CUOTAS PARES UBICACION.xlsx` (ubicación, cuotas partes, área) y hoja `PROYECTOS` de `INVENTARIO COMERCIAL .xlsx` (ofertas). Sin oferta cargada = «Consultar».
- **Precios (Pentecostés):** `área × $30.000.000 / 90` financiado y `área × $25.000.000 / 90` contado; inicial base $10.000.000, cuota $350.000, separación $1.000.000 dentro de la inicial.

Los archivos fuente (Excel y KMZ) **no** se incluyen en el repositorio; los scripts de `tools/` los esperan en las rutas indicadas al inicio de cada uno.

## Supuestos y límites conocidos

1. **Estados distintos de `VENDIDO`:** `CLAUSULA`, `DEVOLUCION`, `CAMBIO DE PARCELA`, `REUBICADO` → «Liberado»; `SEPARADO`, `PENDIENTE`, `CESION DE APORTES` → «En trámite»; vacío → «Disponible». Es una interpretación; el modo «Auditoría Excel» muestra cada estado por separado.
2. **Medidas, perímetro, GPS y linderos por lote** son aproximados (derivados de la geometría del plano; 6×15 m se asume para lotes de 90 m²). El área en m² es la oficial.
3. **Lotes esquineros:** heurística por adyacencia (68 detectados), no un dato oficial.
4. **«Zona verde»** del visor es una aproximación dibujada sobre la ortofoto.
5. El plano PDF es la referencia más cercana al terreno: la zona baja junto al río pudo variar y las cuotas mayores a 2.000 m² pudieron subdividirse.
6. La «Oferta 3» de Shalom (crédito $30M, contado $10M) está marcada «por validar»: así figura en el inventario.

## Regenerar datos

Scripts de `tools/` (Windows PowerShell 5, numerados en orden; usan rutas de la máquina de origen, ajustar al inicio de cada uno). `bench_spatial_index.js` mide el índice espacial con Node.

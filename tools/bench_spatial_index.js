const fs = require('fs');
const path = require('path');
const { performance } = require('perf_hooks');

const webDir = 'c:/Users/proye/Downloads/pentecostes-maruz';
const inv = JSON.parse(fs.readFileSync(path.join(webDir, 'data/pentecostes-inventory.json'), 'utf8'));

// Load SpatialGridIndex algorithm test directly against all 839 real polygons
const worldW = inv.mapConfig.canvasWidth;
const worldH = inv.mapConfig.canvasHeight;
const cols = 36, rows = 48;
const cellW = worldW / cols, cellH = worldH / rows;
const cells = Array.from({ length: cols * rows }, () => []);
const seenStamp = new Int32Array(inv.lots.length);
let currentStamp = 1;

inv.lots.forEach((lot, idx) => {
  const b = lot.bbox;
  const c0 = Math.max(0, Math.min(cols - 1, Math.floor(b[0] / cellW)));
  const c1 = Math.max(0, Math.min(cols - 1, Math.floor(b[2] / cellW)));
  const r0 = Math.max(0, Math.min(rows - 1, Math.floor(b[1] / cellH)));
  const r1 = Math.max(0, Math.min(rows - 1, Math.floor(b[3] / cellH)));
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) cells[r * cols + c].push(idx);
  }
});

function pointInPolygon(x, y, pts) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const xi = pts[i][0], yi = pts[i][1];
    const xj = pts[j][0], yj = pts[j][1];
    const intersect = ((yi > y) !== (yj > y)) && (x < ((xj - xi) * (y - yi)) / (yj - yi + 1e-12) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

function hitTest(wx, wy) {
  const c = Math.max(0, Math.min(cols - 1, Math.floor(wx / cellW)));
  const r = Math.max(0, Math.min(rows - 1, Math.floor(wy / cellH)));
  const bucket = cells[r * cols + c];
  for (let i = bucket.length - 1; i >= 0; i--) {
    const lot = inv.lots[bucket[i]];
    const b = lot.bbox;
    if (wx < b[0] || wx > b[2] || wy < b[1] || wy > b[3]) continue;
    if (pointInPolygon(wx, wy, lot.pts)) return lot;
  }
  return null;
}

// 1. Verify centroid hit-test accuracy across all 839 lots!
let exactHits = 0;
for (const lot of inv.lots) {
  const found = hitTest(lot.cx, lot.cy);
  if (found && found.id === lot.id) exactHits++;
}
console.log(`Centroid Spatial Hit-Test Accuracy: ${exactHits} / ${inv.lots.length}`);

// 2. Benchmark 50,000 random pointer hover hit-tests
const N = 50000;
const t0 = performance.now();
let hitCount = 0;
for (let i = 0; i < N; i++) {
  const rx = 1250 + ((i * 7919) % 6100);
  const ry = 1850 + ((i * 6271) % 8700);
  if (hitTest(rx, ry)) hitCount++;
}
const dtHit = performance.now() - t0;
console.log(`50,000 Spatial Hit-Tests: ${dtHit.toFixed(2)} ms total (${((dtHit * 1000) / N).toFixed(2)} microseconds/query, hits=${hitCount})`);

// 3. Benchmark 5,000 Frustum Culling Queries (simulating zoomed-in 120 FPS pan)
const out = [];
const t1 = performance.now();
for (let f = 0; f < 5000; f++) {
  out.length = 0;
  const stamp = ++currentStamp;
  const minX = 2800 + (f % 1500), minY = 3800 + (f % 2000);
  const maxX = minX + 1600, maxY = minY + 1100;
  const c0 = Math.max(0, Math.min(cols - 1, Math.floor(minX / cellW)));
  const c1 = Math.max(0, Math.min(cols - 1, Math.floor(maxX / cellW)));
  const r0 = Math.max(0, Math.min(rows - 1, Math.floor(minY / cellH)));
  const r1 = Math.max(0, Math.min(rows - 1, Math.floor(maxY / cellH)));
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      const bkt = cells[r * cols + c];
      for (let k = 0; k < bkt.length; k++) {
        const idx = bkt[k];
        if (seenStamp[idx] !== stamp) {
          seenStamp[idx] = stamp;
          const b = inv.lots[idx].bbox;
          if (b[2] >= minX && b[0] <= maxX && b[3] >= minY && b[1] <= maxY) out.push(inv.lots[idx]);
        }
      }
    }
  }
}
const dtFrust = performance.now() - t1;
console.log(`5,000 Frustum Culling Queries: ${dtFrust.toFixed(2)} ms total (${((dtFrust * 1000) / 5000).toFixed(2)} microseconds/frame)`);

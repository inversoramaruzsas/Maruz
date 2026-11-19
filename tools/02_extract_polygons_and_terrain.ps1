$ErrorActionPreference = "Stop"

$csharpCode = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.IO;
using System.Text;
using System.Linq;

public class FinalMasterBuilder {
    public class CircleSpec {
        public int mz;
        public double refX, refY;
        public double gridAngleDeg;
        public string lote1Rule;
        public bool clockwise;
        public int expectedCount;
        public CircleSpec(int m, double x, double y, double a, string r1, bool cw, int cnt) {
            mz = m; refX = x; refY = y; gridAngleDeg = a; lote1Rule = r1; clockwise = cw; expectedCount = cnt;
        }
    }

    public class PolyLot {
        public int cid;
        public int mz;
        public int lote;
        public int pixelArea;
        public int minX, minY, maxX, maxY;
        public double cx, cy;
        public List<PointF> vertices;
    }

    public static void BuildAll(string rawPath, string scratchDir, string webAssetsDir) {
        Directory.CreateDirectory(webAssetsDir);

        List<CircleSpec> specs = new List<CircleSpec>() {
            new CircleSpec(1,  5087, 9239, 32.5,  "maxY",      true,  25),
            new CircleSpec(2,  4021, 8566, 32.5,  "maxY",      true,  38),
            new CircleSpec(3,  2827, 7807, 32.5,  "maxY",      true,  32),
            new CircleSpec(4,  5584, 8929, 32.5,  "maxY",      true,  11),
            new CircleSpec(5,  5190, 8598, 122.5, "maxY",      false, 11),
            new CircleSpec(6,  4749, 8319, 122.5, "maxY",      false, 14),
            new CircleSpec(7,  4307, 8040, 122.5, "maxY",      false, 18),
            new CircleSpec(8,  3946, 7635, 122.5, "maxY",      false, 24),
            new CircleSpec(9,  3509, 7355, 122.5, "maxY",      false, 29),
            new CircleSpec(10, 3080, 7085, 122.5, "maxY",      false, 23),
            new CircleSpec(11, 4263, 6059, 42.0,  "minX",      false, 19),
            new CircleSpec(12, 4612, 5674, 42.0,  "minX",      false, 26),
            new CircleSpec(13, 4967, 5282, 42.0,  "minX",      false, 34),
            new CircleSpec(14, 5319, 4897, 42.0,  "minX",      false, 43),
            new CircleSpec(15, 5668, 4508, 42.0,  "minX",      false, 54),
            new CircleSpec(16, 6016, 4128, 42.0,  "minY",      false, 45),
            new CircleSpec(17, 6368, 3736, 42.0,  "minX",      false, 33),
            new CircleSpec(18, 6720, 3353, 42.0,  "minX",      false, 22),
            new CircleSpec(19, 3305, 5890, 42.0,  "maxY",      true,  29),
            new CircleSpec(20, 3654, 5507, 42.0,  "maxXplusHalfY", true, 40),
            new CircleSpec(21, 4006, 5124, 42.0,  "maxXplusHalfY", true, 49),
            new CircleSpec(22, 4358, 4732, 42.0,  "maxY",      true,  40),
            new CircleSpec(23, 4707, 4347, 42.0,  "maxY",      true,  37),
            new CircleSpec(24, 5062, 3960, 42.0,  "maxY",      true,  35),
            new CircleSpec(25, 5412, 3575, 42.0,  "maxY",      true,  33),
            new CircleSpec(26, 5762, 3185, 42.0,  "maxY",      true,  26),
            new CircleSpec(27, 6111, 2795, 42.0,  "maxY",      true,  16),
            new CircleSpec(28, 6700, 2700, 42.0,  "maxY",      true,  16)
        };

        Bitmap bmp = new Bitmap(rawPath);
        int W = bmp.Width, H = bmp.Height;

        // A. Extract clean transparent PNG of Pentecostes Urbanizacion logo from [995..3570, 160..2520]
        ExtractTransparentLogo(bmp, Path.Combine(webAssetsDir, "logo-pentecostes.png"), Path.Combine(webAssetsDir, "logo-pentecostes-white.png"));

        BitmapData bd = bmp.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadWrite, PixelFormat.Format24bppRgb);
        int stride = bd.Stride;
        byte[] rgb = new byte[stride * H];
        Marshal.Copy(bd.Scan0, rgb, 0, rgb.Length);

        int X0 = 1250, Y0 = 1850, X1 = 7350, Y1 = 10550;
        int RW = X1 - X0, RH = Y1 - Y0;

        // 1. Detect black circles
        byte[] dark = new byte[RW * RH];
        for (int y = 0; y < RH; y++) {
            int rowOff = (y + Y0) * stride + X0 * 3;
            int mOff = y * RW;
            for (int x = 0; x < RW; x++) {
                int gx = x + X0, gy = y + Y0;
                if ((gx <= 3560 && gy <= 2680) || (gx >= 6150 && gy >= 5980)) continue;
                if (rgb[rowOff + x * 3] < 45 && rgb[rowOff + x * 3 + 1] < 45 && rgb[rowOff + x * 3 + 2] < 45)
                    dark[mOff + x] = 1;
            }
        }

        int[] vis = new int[RW * RH];
        int[] q = new int[RW * RH];
        Dictionary<int, double[]> circleGeom = new Dictionary<int, double[]>();

        for (int i = 0; i < dark.Length; i++) {
            if (dark[i] == 1 && vis[i] == 0) {
                int head = 0, tail = 0;
                q[tail++] = i; vis[i] = 1;
                int minX = RW, minY = RH, maxX = 0, maxY = 0;
                while (head < tail) {
                    int curr = q[head++];
                    int cy = curr / RW, cx = curr % RW;
                    if (cx < minX) minX = cx; if (cx > maxX) maxX = cx;
                    if (cy < minY) minY = cy; if (cy > maxY) maxY = cy;
                    if (cx > 0 && dark[curr - 1] == 1 && vis[curr - 1] == 0) { vis[curr - 1] = 1; q[tail++] = curr - 1; }
                    if (cx + 1 < RW && dark[curr + 1] == 1 && vis[curr + 1] == 0) { vis[curr + 1] = 1; q[tail++] = curr + 1; }
                    if (cy > 0 && dark[curr - RW] == 1 && vis[curr - RW] == 0) { vis[curr - RW] = 1; q[tail++] = curr - RW; }
                    if (cy + 1 < RH && dark[curr + RW] == 1 && vis[curr + RW] == 0) { vis[curr + RW] = 1; q[tail++] = curr + RW; }
                }
                int bw = maxX - minX + 1, bh = maxY - minY + 1;
                if (tail >= 5000 && tail <= 26000 && bw >= 90 && bw <= 185 && bh >= 90 && bh <= 185 && Math.Abs(bw - bh) <= 25) {
                    double gcx = (minX + maxX) * 0.5 + X0, gcy = (minY + maxY) * 0.5 + Y0, gr = (bw + bh) * 0.25;
                    int bestMz = -1; double bestDist = 1e9;
                    foreach (var sp in specs) {
                        double d = Math.Sqrt((gcx - sp.refX) * (gcx - sp.refX) + (gcy - sp.refY) * (gcy - sp.refY));
                        if (d < bestDist) { bestDist = d; bestMz = sp.mz; }
                    }
                    circleGeom[bestMz] = new double[] { gcx, gcy, gr };
                }
            }
        }

        // 2. White CAD line mask (with cream-white threshold inside Mz 10's warm-tinted region!)
        byte[] white = new byte[RW * RH];
        for (int y = 0; y < RH; y++) {
            int rowOff = (y + Y0) * stride + X0 * 3;
            int mOff = y * RW;
            for (int x = 0; x < RW; x++) {
                int gx = x + X0, gy = y + Y0;
                if ((gx <= 3560 && gy <= 2680) || (gx >= 6150 && gy >= 5980)) {
                    white[mOff + x] = 1; continue;
                }
                int b = rgb[rowOff + x * 3], g = rgb[rowOff + x * 3 + 1], r = rgb[rowOff + x * 3 + 2];
                int mx = Math.Max(r, Math.Max(g, b)), mn = Math.Min(r, Math.Min(g, b));
                bool isStdWhite = (r >= 220 && g >= 220 && b >= 212 && (mx - mn) <= 28);
                // Mz 10 warm cream CAD lines: strictly inside Mz 10 polygon zone!
                bool inMz10Box = (gx >= 2660 && gx <= 3520 && gy >= 6460 && gy <= 7540);
                bool isCreamWhite = inMz10Box && (r >= 224 && g >= 216 && b >= 186 && (r - b) <= 46);
                if (isStdWhite || isCreamWhite) white[mOff + x] = 1;
            }
        }

        // 3. Reconstruct white lines across each of the 28 black circles
        foreach (var sp in specs) {
            double[] cg = circleGeom[sp.mz];
            double lx = cg[0] - X0, ly = cg[1] - Y0, R = cg[2];

            int ir = (int)Math.Ceiling(R + 3);
            for (int dy = -ir; dy <= ir; dy++) {
                int py = (int)Math.Round(ly) + dy;
                if (py < 0 || py >= RH) continue;
                for (int dx = -ir; dx <= ir; dx++) {
                    if (dx * dx + dy * dy <= (R + 2.5) * (R + 2.5)) {
                        int px = (int)Math.Round(lx) + dx;
                        if (px >= 0 && px < RW) white[py * RW + px] = 0;
                    }
                }
            }

            double bestAng = sp.gridAngleDeg, bestSc = -1;
            for (double da = -3.0; da <= 3.0; da += 0.2) {
                double rad = (sp.gridAngleDeg + da) * Math.PI / 180.0;
                double cs = Math.Cos(rad), sn = Math.Sin(rad);
                int[] histV = new int[240];
                for (int dy = -110; dy <= 110; dy++) {
                    for (int dx = -110; dx <= 110; dx++) {
                        double d2 = dx * dx + dy * dy;
                        if (d2 < (R + 4) * (R + 4) || d2 > 110 * 110) continue;
                        int px = (int)Math.Round(lx) + dx, py = (int)Math.Round(ly) + dy;
                        if (px >= 0 && px < RW && py >= 0 && py < RH && white[py * RW + px] == 1) {
                            int bv = (int)Math.Round(-dx * sn + dy * cs) + 120;
                            if (bv >= 0 && bv < 240) histV[bv]++;
                        }
                    }
                }
                double sc = 0;
                for (int b = 1; b < 239; b++) { double s = histV[b - 1] + histV[b] + histV[b + 1]; sc += s * s; }
                if (sc > bestSc) { bestSc = sc; bestAng = sp.gridAngleDeg + da; }
            }

            double csS = Math.Cos(bestAng * Math.PI / 180.0);
            double snS = Math.Sin(bestAng * Math.PI / 180.0);

            int maxOff = (sp.mz == 28) ? (int)(R - 3) : 28;
            int vSpine = 0; double bestSpine = -1;
            for (int off = -maxOff; off <= maxOff; off++) {
                double chord = Math.Sqrt(Math.Max(0, (R + 4) * (R + 4) - off * off));
                int lCnt = 0, rCnt = 0;
                for (int t = (int)chord + 2; t <= (int)chord + 42; t++) {
                    for (int w = -2; w <= 2; w++) {
                        int xL = (int)Math.Round(lx + (-t) * csS - (off + w) * snS);
                        int yL = (int)Math.Round(ly + (-t) * snS + (off + w) * csS);
                        int xR = (int)Math.Round(lx + (t) * csS - (off + w) * snS);
                        int yR = (int)Math.Round(ly + (t) * snS + (off + w) * csS);
                        if (xL >= 0 && xL < RW && yL >= 0 && yL < RH && white[yL * RW + xL] == 1) lCnt++;
                        if (xR >= 0 && xR < RW && yR >= 0 && yR < RH && white[yR * RW + xR] == 1) rCnt++;
                    }
                }
                double sc = Math.Min(lCnt, rCnt) * (lCnt + rCnt);
                if (sc > bestSpine) { bestSpine = sc; vSpine = off; }
            }

            double extraSpan = (sp.mz == 10) ? 16.0 : 7.0;
            double chordS = Math.Sqrt(Math.Max(0, (R + extraSpan) * (R + extraSpan) - vSpine * vSpine));
            DrawLocalSegment(white, RW, RH, lx, ly, csS, snS, -chordS, vSpine, +chordS, vSpine, 3);

            int minSupport = (sp.mz == 10) ? 24 : 36;
            for (int side = -1; side <= 1; side += 2) {
                if (sp.mz == 28 && side == -1) continue;
                int[] uSup = new int[201];
                for (int u = -(int)R; u <= (int)R; u++) {
                    double rimV = side * Math.Sqrt(Math.Max(0, (R + 4) * (R + 4) - u * u));
                    if (side * (rimV - vSpine) <= 2) continue;
                    int cnt = 0;
                    for (int step = 2; step <= 34; step++) {
                        double vv = rimV + side * step;
                        for (int w = -1; w <= 1; w++) {
                            int px = (int)Math.Round(lx + (u + w) * csS - vv * snS);
                            int py = (int)Math.Round(ly + (u + w) * snS + vv * csS);
                            if (px >= 0 && px < RW && py >= 0 && py < RH && white[py * RW + px] == 1) cnt++;
                        }
                    }
                    uSup[u + 100] = cnt;
                }
                for (int u = -(int)R; u <= (int)R; u++) {
                    int val = uSup[u + 100];
                    if (val >= minSupport) {
                        bool isMax = true;
                        for (int nb = -9; nb <= 9; nb++) {
                            int idx = u + 100 + nb;
                            if (idx >= 0 && idx <= 200 && (uSup[idx] > val || (uSup[idx] == val && nb < 0))) { isMax = false; break; }
                        }
                        if (isMax) {
                            double rimV = side * Math.Sqrt(Math.Max(0, (R + 7) * (R + 7) - u * u));
                            DrawLocalSegment(white, RW, RH, lx, ly, csS, snS, u, vSpine, u, rimV, 3);
                        }
                    }
                }
            }
        }

        byte[] whiteClosed = (byte[])white.Clone();
        for (int y = 1; y < RH - 1; y++) {
            int off = y * RW;
            for (int x = 1; x < RW - 1; x++) {
                if (white[off + x] == 0) {
                    if ((white[off + x - 1] == 1 && white[off + x + 1] == 1) ||
                        (white[off + x - RW] == 1 && white[off + x + RW] == 1) ||
                        (white[off + x - RW - 1] == 1 && white[off + x + RW + 1] == 1) ||
                        (white[off + x - RW + 1] == 1 && white[off + x + RW - 1] == 1))
                        whiteClosed[off + x] = 1;
                }
            }
        }

        // 4. Connected components
        int[] compMap = new int[RW * RH];
        List<PolyLot> rawLots = new List<PolyLot>();
        int nextCid = 1;

        for (int i = 0; i < whiteClosed.Length; i++) {
            if (whiteClosed[i] == 0 && compMap[i] == 0) {
                int head = 0, tail = 0;
                int cid = nextCid++;
                q[tail++] = i; compMap[i] = cid;
                int minX = RW, minY = RH, maxX = 0, maxY = 0;
                long sumX = 0, sumY = 0, tint = 0;
                while (head < tail) {
                    int curr = q[head++];
                    int cy = curr / RW, cx = curr % RW;
                    if (cx < minX) minX = cx; if (cx > maxX) maxX = cx;
                    if (cy < minY) minY = cy; if (cy > maxY) maxY = cy;
                    sumX += cx; sumY += cy;
                    int pOff = (cy + Y0) * stride + (cx + X0) * 3;
                    int b = rgb[pOff], g = rgb[pOff + 1], r = rgb[pOff + 2];
                    if ((g > r + 5 && g > b + 3) || (r > b + 15 && g > b + 7 && r > 135)) tint++;

                    if (cx > 0 && whiteClosed[curr - 1] == 0 && compMap[curr - 1] == 0) { compMap[curr - 1] = cid; q[tail++] = curr - 1; }
                    if (cx + 1 < RW && whiteClosed[curr + 1] == 0 && compMap[curr + 1] == 0) { compMap[curr + 1] = cid; q[tail++] = curr + 1; }
                    if (cy > 0 && whiteClosed[curr - RW] == 0 && compMap[curr - RW] == 0) { compMap[curr - RW] = cid; q[tail++] = curr - RW; }
                    if (cy + 1 < RH && whiteClosed[curr + RW] == 0 && compMap[curr + RW] == 0) { compMap[curr + RW] = cid; q[tail++] = curr + RW; }
                }

                int bw = maxX - minX + 1, bh = maxY - minY + 1;
                double boxFill = (double)tail / ((double)bw * bh);
                double tintRatio = (double)tint / tail;
                double gcx = (double)sumX / tail + X0, gcy = (double)sumY / tail + Y0;
                bool touchesBorder = (minX <= 2 || minY <= 2 || maxX >= RW - 3 || maxY >= RH - 3);
                bool validArea = (tail >= 3200 && tail <= 26000) || (tail >= 50000 && tail <= 230000);
                int maxAllowedDim = (tail >= 50000) ? 1250 : 500;
                bool inMz10Zone = (gcx >= 2660 && gcx <= 3520 && gcy >= 6460 && gcy <= 7540 && tail >= 5500 && tail <= 16500 && boxFill >= 0.32);

                if (!touchesBorder && validArea && bw <= maxAllowedDim && bh <= maxAllowedDim && boxFill >= 0.24 && (tintRatio >= 0.42 || inMz10Zone)) {
                    PolyLot pl = new PolyLot();
                    pl.cid = cid;
                    pl.pixelArea = tail;
                    pl.minX = minX + X0; pl.minY = minY + Y0;
                    pl.maxX = maxX + X0; pl.maxY = maxY + Y0;
                    pl.cx = gcx; pl.cy = gcy;
                    pl.vertices = TraceAndSimplify(compMap, RW, RH, X0, Y0, cid, minX, minY, maxX, maxY, pl.cx, pl.cy);
                    rawLots.Add(pl);
                }
            }
        }
        Console.WriteLine("Total extracted valid lot polygons: " + rawLots.Count + " (expected 839)");

        List<PolyLot> superLotes = rawLots.Where(p => p.pixelArea >= 50000).ToList();
        List<PolyLot> regLots = rawLots.Where(p => p.pixelArea < 50000).ToList();
        Console.WriteLine("Super Lotes: " + superLotes.Count + " (expected 17) | Regular Lots: " + regLots.Count + " (expected 822)");

        PolyLot sl01 = superLotes.OrderBy(s => s.cy).First();
        sl01.mz = 99; sl01.lote = 1;
        var slRest = superLotes.Where(s => s != sl01).OrderBy(s => s.cx).ToList();
        for (int i = 0; i < slRest.Count; i++) { slRest[i].mz = 99; slRest[i].lote = i + 2; }

        int nReg = regLots.Count;
        int[] parent = new int[nReg];
        for (int i = 0; i < nReg; i++) parent[i] = i;
        Func<int, int> find = null;
        find = (x) => parent[x] == x ? x : (parent[x] = find(parent[x]));

        for (int i = 0; i < nReg; i++) {
            for (int j = i + 1; j < nReg; j++) {
                if (find(i) == find(j)) continue;
                int gx = Math.Max(0, Math.Max(regLots[i].minX - regLots[j].maxX, regLots[j].minX - regLots[i].maxX));
                int gy = Math.Max(0, Math.Max(regLots[i].minY - regLots[j].maxY, regLots[j].minY - regLots[i].maxY));
                if (gx <= 24 && gy <= 24) {
                    if (PolyDistSq(regLots[i].vertices, regLots[j].vertices) <= 24.0 * 24.0)
                        parent[find(i)] = find(j);
                }
            }
        }

        Dictionary<int, List<PolyLot>> clusters = new Dictionary<int, List<PolyLot>>();
        for (int i = 0; i < nReg; i++) {
            int root = find(i);
            if (!clusters.ContainsKey(root)) clusters[root] = new List<PolyLot>();
            clusters[root].Add(regLots[i]);
        }
        Console.WriteLine("Regular lot clusters formed: " + clusters.Count + " (expected 28)");

        Dictionary<int, List<PolyLot>> mzLots = new Dictionary<int, List<PolyLot>>();
        foreach (var kv in clusters) {
            var list = kv.Value;
            int bestMz = -1; double bestD = 1e9;
            foreach (var sp in specs) {
                double[] cg = circleGeom[sp.mz];
                double dMin = list.Min(l => Math.Sqrt((l.cx - cg[0]) * (l.cx - cg[0]) + (l.cy - cg[1]) * (l.cy - cg[1])));
                if (dMin < bestD) { bestD = dMin; bestMz = sp.mz; }
            }
            if (!mzLots.ContainsKey(bestMz)) mzLots[bestMz] = new List<PolyLot>();
            mzLots[bestMz].AddRange(list);
        }

        int okMz = 0;
        foreach (var sp in specs.OrderBy(s => s.mz)) {
            var list = mzLots[sp.mz];
            bool match = (list.Count == sp.expectedCount);
            if (match) okMz++;
            Console.WriteLine(string.Format("  Mz {0,2}: found={1,2} expected={2,2} [{3}]", sp.mz, list.Count, sp.expectedCount, match ? "EXACT" : "MISMATCH!"));
            NumberByConvexHullAndAnchor(list, sp);
        }
        Console.WriteLine("Exact Manzana counts: " + okMz + " / 28");

        // Save closeup verification of Mz 10!
        // Also seamlessly restore natural aerial terrain over the 2 white print boxes on rgb[] before saving web map!
        // Box 1 (Top-Left Logo white box): x in [945, 3625], y in [105, 2555] from pure forest [3660..5960, 120..1870]
        SeamlessPatchFill(rgb, W, H, stride, 945, 105, 3625, 2555, 3660, 120, 2250, 1720, 85);

        // Box 2 (Bottom-Right Cuadro de Areas white box): x in [6175, W-1], y in [5955, H-1] from pure road-free savanna [5080..6130, 6180..7780]
        SeamlessSavannaFill(rgb, W, H, stride, 6175, 5955, W - 1, H - 1, 5080, 6180, 1040, 1580, 120);

        Marshal.Copy(rgb, 0, bd.Scan0, rgb.Length);
        bmp.UnlockBits(bd);

        // Save closeup verification of Mz 10
        using (Bitmap mz10Ver = new Bitmap(600, 650, PixelFormat.Format24bppRgb)) {
            using (Graphics g = Graphics.FromImage(mz10Ver)) {
                g.DrawImage(bmp, new Rectangle(0, 0, 600, 650), new Rectangle(2600, 6400, 1000, 1083), GraphicsUnit.Pixel);
                Font f = new Font("Arial", 9, FontStyle.Bold);
                StringFormat sf = new StringFormat() { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                foreach (var pl in mzLots[10]) {
                    PointF[] pts = pl.vertices.Select(p => new PointF((p.X - 2600) * 0.6f, (p.Y - 6400) * (650f / 1083f))).ToArray();
                    g.FillPolygon(new SolidBrush(Color.FromArgb(65, 16, 185, 129)), pts);
                    g.DrawPolygon(new Pen(Color.Cyan, 2f), pts);
                    g.DrawString("10-" + pl.lote, f, Brushes.Yellow, (float)((pl.cx - 2600) * 0.6), (float)((pl.cy - 6400) * (650.0 / 1083.0)), sf);
                }
            }
            mz10Ver.Save(Path.Combine(scratchDir, "verify_mz10.jpg"), ImageFormat.Jpeg);
        }

        // Save high-resolution clean aerial terrain web image (3481 x 4724 at exact 0.4x scale, JPEG quality 88 -> ~3.2 MB ultra-crisp!)
        int webW = (int)Math.Round(W * 0.4); // 3481
        int webH = (int)Math.Round(H * 0.4); // 4724
        using (Bitmap webBmp = new Bitmap(webW, webH, PixelFormat.Format24bppRgb)) {
            using (Graphics g = Graphics.FromImage(webBmp)) {
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                g.DrawImage(bmp, new Rectangle(0, 0, webW, webH), new Rectangle(0, 0, W, H), GraphicsUnit.Pixel);
            }
            ImageCodecInfo jpgEncoder = ImageCodecInfo.GetImageDecoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
            EncoderParameters encParams = new EncoderParameters(1);
            encParams.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 88L);
            webBmp.Save(Path.Combine(webAssetsDir, "terreno-pentecostes.jpg"), jpgEncoder, encParams);

            // Also save a small preview to scratch to inspect terrain restoration visually
            using (Bitmap prev = new Bitmap(webBmp, 870, 1181)) {
                prev.Save(Path.Combine(scratchDir, "terreno_clean_preview.jpg"), ImageFormat.Jpeg);
            }
        }
        bmp.Dispose();

        // Export extracted_polygons.json + circle centers JSON
        StringBuilder sb = new StringBuilder();
        sb.AppendLine("{");
        sb.AppendLine("  \"canvasWidth\": " + W + ",");
        sb.AppendLine("  \"canvasHeight\": " + H + ",");
        sb.AppendLine("  \"manzanaCenters\": [");
        var spOrdered = specs.OrderBy(s => s.mz).ToList();
        for (int i = 0; i < spOrdered.Count; i++) {
            int mz = spOrdered[i].mz;
            double[] cg = circleGeom[mz];
            sb.Append(string.Format(System.Globalization.CultureInfo.InvariantCulture,
                "    {{\"mz\":{0},\"cx\":{1:F1},\"cy\":{2:F1},\"r\":{3:F1}}}", mz, cg[0], cg[1], cg[2]));
            if (i + 1 < spOrdered.Count) sb.AppendLine(","); else sb.AppendLine();
        }
        sb.AppendLine("  ],");
        sb.AppendLine("  \"polygons\": [");
        var orderedAll = rawLots.OrderBy(l => l.mz).ThenBy(l => l.lote).ToList();
        for (int idx = 0; idx < orderedAll.Count; idx++) {
            var pl = orderedAll[idx];
            string mzStr = (pl.mz == 99) ? "\"SUPER LOTE\"" : pl.mz.ToString();
            string ptsStr = string.Join(",", pl.vertices.Select(p => string.Format(System.Globalization.CultureInfo.InvariantCulture, "[{0:F0},{1:F0}]", p.X, p.Y)));
            sb.Append(string.Format(System.Globalization.CultureInfo.InvariantCulture,
                "    {{\"mz\":{0},\"lote\":{1},\"cx\":{2:F0},\"cy\":{3:F0},\"pxArea\":{4},\"pts\":[{5}]}}",
                mzStr, pl.lote, pl.cx, pl.cy, pl.pixelArea, ptsStr));
            if (idx + 1 < orderedAll.Count) sb.AppendLine(","); else sb.AppendLine();
        }
        sb.AppendLine("  ]");
        sb.AppendLine("}");
        File.WriteAllText(Path.Combine(scratchDir, "extracted_polygons.json"), sb.ToString(), Encoding.UTF8);
        Console.WriteLine("All assets built successfully!");
    }

    private static void ExtractTransparentLogo(Bitmap fullBmp, string darkLogoPath, string whiteLogoPath) {
        // Logo box in pentecostes_raw.jpg is [1030..3540, 190..2480] -> 2510 x 2290
        int lx = 1040, ly = 195, lw = 2480, lh = 2240;
        int outW = 620, outH = 560;
        using (Bitmap sub = new Bitmap(outW, outH, PixelFormat.Format32bppArgb))
        using (Bitmap subWhite = new Bitmap(outW, outH, PixelFormat.Format32bppArgb)) {
            using (Bitmap tmp = new Bitmap(outW, outH, PixelFormat.Format24bppRgb)) {
                using (Graphics g = Graphics.FromImage(tmp)) {
                    g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                    g.DrawImage(fullBmp, new Rectangle(0, 0, outW, outH), new Rectangle(lx, ly, lw, lh), GraphicsUnit.Pixel);
                }
                for (int y = 0; y < outH; y++) {
                    for (int x = 0; x < outW; x++) {
                        Color c = tmp.GetPixel(x, y);
                        int lum = (c.R * 299 + c.G * 587 + c.B * 114) / 1000;
                        if (lum >= 244) {
                            sub.SetPixel(x, y, Color.FromArgb(0, 255, 255, 255));
                            subWhite.SetPixel(x, y, Color.FromArgb(0, 255, 255, 255));
                        } else {
                            int alpha = Math.Min(255, (248 - lum) * 255 / 45);
                            sub.SetPixel(x, y, Color.FromArgb(alpha, c.R, c.G, c.B));
                            // For dark-header version: convert very dark black text/roof to crisp white, keep teal wave bright cyan-teal!
                            bool isTeal = (c.B > c.R + 18 || c.G > c.R + 14);
                            if (isTeal) {
                                subWhite.SetPixel(x, y, Color.FromArgb(alpha, Math.Min(255, c.R + 35), Math.Min(255, c.G + 65), Math.Min(255, c.B + 70)));
                            } else {
                                subWhite.SetPixel(x, y, Color.FromArgb(alpha, 248, 250, 252));
                            }
                        }
                    }
                }
            }
            sub.Save(darkLogoPath, ImageFormat.Png);
            subWhite.Save(whiteLogoPath, ImageFormat.Png);
        }
    }

    private static void SeamlessPatchFill(byte[] rgb, int W, int H, int stride, int x0, int y0, int x1, int y1, int sx0, int sy0, int sw, int sh, int feather) {
        for (int y = y0; y <= y1; y++) {
            if (y < 0 || y >= H) continue;
            // Mirrored wrap inside source patch
            int ry = (y - y0) % (sh * 2);
            if (ry >= sh) ry = sh * 2 - 1 - ry;
            int srcY = sy0 + ry;

            double wy = 1.0;
            if (y - y0 < feather) wy = Math.Min(wy, (double)(y - y0) / feather);
            if (y1 - y < feather) wy = Math.Min(wy, (double)(y1 - y) / feather);

            for (int x = x0; x <= x1; x++) {
                if (x < 0 || x >= W) continue;
                // Notice at bottom of logo box (x in [2550..2950], y > 2460) is the white access road — feather preserves it smoothly!
                int rx = (x - x0) % (sw * 2);
                if (rx >= sw) rx = sw * 2 - 1 - rx;
                int srcX = sx0 + rx;

                double wx = 1.0;
                if (x - x0 < feather) wx = Math.Min(wx, (double)(x - x0) / feather);
                if (x1 - x < feather) wx = Math.Min(wx, (double)(x1 - x) / feather);
                double alpha = wx * wy;
                alpha = alpha * alpha * (3.0 - 2.0 * alpha); // smoothstep

                int dOff = y * stride + x * 3;
                int sOff = srcY * stride + srcX * 3;
                rgb[dOff]     = (byte)Math.Round(rgb[dOff] * (1.0 - alpha) + rgb[sOff] * alpha);
                rgb[dOff + 1] = (byte)Math.Round(rgb[dOff + 1] * (1.0 - alpha) + rgb[sOff + 1] * alpha);
                rgb[dOff + 2] = (byte)Math.Round(rgb[dOff + 2] * (1.0 - alpha) + rgb[sOff + 2] * alpha);
            }
        }
    }

    private static void SeamlessSavannaFill(byte[] rgb, int W, int H, int stride, int x0, int y0, int x1, int y1, int sx0, int sy0, int sw, int sh, int feather) {
        for (int y = y0; y <= y1; y++) {
            if (y < 0 || y >= H) continue;
            int ry = (y - y0) % (sh * 2);
            if (ry >= sh) ry = sh * 2 - 1 - ry;
            int srcY = sy0 + ry;

            double wy = 1.0;
            if (y - y0 < feather) wy = Math.Min(wy, (double)(y - y0) / feather);
            if (y1 - y < feather && y1 < H - 50) wy = Math.Min(wy, (double)(y1 - y) / feather);

            for (int x = x0; x <= x1; x++) {
                if (x < 0 || x >= W) continue;
                int rx = (x - x0) % (sw * 2);
                if (rx >= sw) rx = sw * 2 - 1 - rx;
                int srcX = sx0 + rx;

                double wx = 1.0;
                if (x - x0 < feather) wx = Math.Min(wx, (double)(x - x0) / feather);
                if (x1 - x < feather && x1 < W - 80) wx = Math.Min(wx, (double)(x1 - x) / feather);
                double alpha = wx * wy;
                alpha = alpha * alpha * (3.0 - 2.0 * alpha);

                int dOff = y * stride + x * 3;
                int sOff = srcY * stride + srcX * 3;
                rgb[dOff]     = (byte)Math.Round(rgb[dOff] * (1.0 - alpha) + rgb[sOff] * alpha);
                rgb[dOff + 1] = (byte)Math.Round(rgb[dOff + 1] * (1.0 - alpha) + rgb[sOff + 1] * alpha);
                rgb[dOff + 2] = (byte)Math.Round(rgb[dOff + 2] * (1.0 - alpha) + rgb[sOff + 2] * alpha);
            }
        }
    }

    private static void NumberByConvexHullAndAnchor(List<PolyLot> list, CircleSpec sp) {
        foreach (var l in list) l.mz = sp.mz;
        if (sp.mz == 28) {
            double rad = sp.gridAngleDeg * Math.PI / 180.0;
            double cs = Math.Cos(rad), sn = Math.Sin(rad);
            var sorted = list.OrderByDescending(l => l.cx * cs + l.cy * sn).ToList();
            for (int i = 0; i < sorted.Count; i++) sorted[i].lote = i + 1;
            return;
        }

        List<PointF> allPts = new List<PointF>();
        foreach (var l in list) allPts.AddRange(l.vertices);
        List<PointF> hull = ConvexHullCW(allPts);
        if (!sp.clockwise) hull.Reverse();

        int Hn = hull.Count;
        double[] segLen = new double[Hn];
        double[] cumLen = new double[Hn + 1];
        for (int i = 0; i < Hn; i++) {
            PointF a = hull[i], b = hull[(i + 1) % Hn];
            segLen[i] = Math.Sqrt((b.X - a.X) * (b.X - a.X) + (b.Y - a.Y) * (b.Y - a.Y));
            cumLen[i + 1] = cumLen[i] + segLen[i];
        }
        double totalPerim = cumLen[Hn];

        Dictionary<PolyLot, double> lotArclength = new Dictionary<PolyLot, double>();
        foreach (var l in list) {
            List<double> sSamples = new List<double>();
            int vn = l.vertices.Count;
            for (int i = 0; i < vn; i++) {
                PointF a = l.vertices[i], b = l.vertices[(i + 1) % vn];
                double elen = Math.Sqrt((b.X - a.X) * (b.X - a.X) + (b.Y - a.Y) * (b.Y - a.Y));
                int steps = Math.Max(1, (int)(elen / 4.0));
                for (int k = 0; k < steps; k++) {
                    double t = (k + 0.5) / steps;
                    PointF p = new PointF((float)(a.X + (b.X - a.X) * t), (float)(a.Y + (b.Y - a.Y) * t));
                    double bestDist2 = 1e12, bestS = 0;
                    for (int h = 0; h < Hn; h++) {
                        PointF ha = hull[h], hb = hull[(h + 1) % Hn];
                        double vx = hb.X - ha.X, vy = hb.Y - ha.Y;
                        double l2 = vx * vx + vy * vy;
                        double u = (l2 > 1e-6) ? Math.Max(0.0, Math.Min(1.0, ((p.X - ha.X) * vx + (p.Y - ha.Y) * vy) / l2)) : 0.0;
                        double qx = ha.X + u * vx, qy = ha.Y + u * vy;
                        double d2 = (p.X - qx) * (p.X - qx) + (p.Y - qy) * (p.Y - qy);
                        if (d2 < bestDist2) { bestDist2 = d2; bestS = cumLen[h] + u * segLen[h]; }
                    }
                    if (bestDist2 <= 22.0 * 22.0) sSamples.Add(bestS);
                }
            }
            double sumCos = 0, sumSin = 0;
            foreach (double s in sSamples) {
                double ang = 2.0 * Math.PI * s / totalPerim;
                sumCos += Math.Cos(ang); sumSin += Math.Sin(ang);
            }
            double meanAng = Math.Atan2(sumSin, sumCos);
            if (meanAng < 0) meanAng += 2.0 * Math.PI;
            lotArclength[l] = meanAng;
        }

        var ring = list.OrderBy(l => lotArclength[l]).ToList();
        PolyLot lote1 = null;
        if (sp.lote1Rule == "maxY") lote1 = ring.OrderByDescending(l => l.cy).First();
        else if (sp.lote1Rule == "minY") lote1 = ring.OrderBy(l => l.cy).First();
        else if (sp.lote1Rule == "minX") lote1 = ring.OrderBy(l => l.cx).First();
        else if (sp.lote1Rule == "maxXplusHalfY") lote1 = ring.OrderByDescending(l => l.cx + 0.5 * l.cy).First();

        int idx1 = ring.IndexOf(lote1);
        int N = ring.Count;
        for (int k = 0; k < N; k++) ring[(idx1 + k) % N].lote = k + 1;
    }

    private static List<PointF> ConvexHullCW(List<PointF> pts) {
        var sorted = pts.OrderBy(p => p.X).ThenBy(p => p.Y).ToList();
        List<PointF> lower = new List<PointF>();
        foreach (var p in sorted) {
            while (lower.Count >= 2 && Cross(lower[lower.Count - 2], lower[lower.Count - 1], p) <= 0)
                lower.RemoveAt(lower.Count - 1);
            lower.Add(p);
        }
        List<PointF> upper = new List<PointF>();
        for (int i = sorted.Count - 1; i >= 0; i--) {
            var p = sorted[i];
            while (upper.Count >= 2 && Cross(upper[upper.Count - 2], upper[upper.Count - 1], p) <= 0)
                upper.RemoveAt(upper.Count - 1);
            upper.Add(p);
        }
        lower.RemoveAt(lower.Count - 1);
        upper.RemoveAt(upper.Count - 1);
        lower.AddRange(upper);
        return lower;
    }

    private static double Cross(PointF O, PointF A, PointF B) {
        return (double)(A.X - O.X) * (B.Y - O.Y) - (double)(A.Y - O.Y) * (B.X - O.X);
    }

    private static double PolyDistSq(List<PointF> A, List<PointF> B) {
        double best = 1e12;
        for (int i = 0; i < A.Count; i++) {
            for (int j = 0; j < B.Count; j++) {
                double d = PtSegDistSq(A[i], B[j], B[(j + 1) % B.Count]);
                if (d < best) best = d;
            }
        }
        for (int j = 0; j < B.Count; j++) {
            for (int i = 0; i < A.Count; i++) {
                double d = PtSegDistSq(B[j], A[i], A[(i + 1) % A.Count]);
                if (d < best) best = d;
            }
        }
        return best;
    }

    private static double PtSegDistSq(PointF p, PointF a, PointF b) {
        double vx = b.X - a.X, vy = b.Y - a.Y;
        double wx = p.X - a.X, wy = p.Y - a.Y;
        double c1 = vx * wx + vy * wy;
        if (c1 <= 0) return wx * wx + wy * wy;
        double c2 = vx * vx + vy * vy;
        if (c2 <= c1) return (p.X - b.X) * (p.X - b.X) + (p.Y - b.Y) * (p.Y - b.Y);
        double t = c1 / c2;
        double px = a.X + t * vx, py = a.Y + t * vy;
        return (p.X - px) * (p.X - px) + (p.Y - py) * (p.Y - py);
    }

    private static List<PointF> TraceAndSimplify(int[] compMap, int RW, int RH, int X0, int Y0, int cid, int minX, int minY, int maxX, int maxY, double cx, double cy) {
        int startX = -1, startY = minY;
        for (int x = minX; x <= maxX; x++) {
            if (compMap[startY * RW + x] == cid) { startX = x; break; }
        }
        int[] dx8 = { 1, 1, 0, -1, -1, -1, 0, 1 };
        int[] dy8 = { 0, 1, 1, 1, 0, -1, -1, -1 };
        List<PointF> contour = new List<PointF>();
        int curX = startX, curY = startY, backDir = 6;
        for (int step = 0; step < 20000; step++) {
            contour.Add(new PointF(curX + X0, curY + Y0));
            int searchStart = (backDir + 1) % 8, foundDir = -1;
            for (int k = 0; k < 8; k++) {
                int d = (searchStart + k) % 8;
                int nx = curX + dx8[d], ny = curY + dy8[d];
                if (nx >= 0 && nx < RW && ny >= 0 && ny < RH && compMap[ny * RW + nx] == cid) { foundDir = d; break; }
            }
            if (foundDir == -1) break;
            curX += dx8[foundDir]; curY += dy8[foundDir];
            backDir = (foundDir + 4) % 8;
            if (curX == startX && curY == startY && contour.Count > 4) break;
        }
        List<PointF> simp = SimplifyClosedPolygon(contour, 4.5f);
        List<PointF> expanded = new List<PointF>();
        foreach (var p in simp) {
            double vx = p.X - cx, vy = p.Y - cy;
            double len = Math.Sqrt(vx * vx + vy * vy);
            if (len > 1.0) expanded.Add(new PointF((float)(p.X + vx / len * 2.5), (float)(p.Y + vy / len * 2.5)));
            else expanded.Add(p);
        }
        return expanded;
    }

    private static List<PointF> SimplifyClosedPolygon(List<PointF> pts, float eps) {
        if (pts.Count <= 4) return pts;
        int iA = 0, iB = pts.Count / 2;
        double maxD = -1;
        int step = Math.Max(1, pts.Count / 60);
        for (int i = 0; i < pts.Count; i += step) {
            for (int j = i + 1; j < pts.Count; j += step) {
                double d = (pts[i].X - pts[j].X) * (pts[i].X - pts[j].X) + (pts[i].Y - pts[j].Y) * (pts[i].Y - pts[j].Y);
                if (d > maxD) { maxD = d; iA = i; iB = j; }
            }
        }
        if (iA > iB) { int tmp = iA; iA = iB; iB = tmp; }
        List<PointF> chain1 = new List<PointF>();
        for (int i = iA; i <= iB; i++) chain1.Add(pts[i]);
        List<PointF> chain2 = new List<PointF>();
        for (int i = iB; i < pts.Count; i++) chain2.Add(pts[i]);
        for (int i = 0; i <= iA; i++) chain2.Add(pts[i]);

        List<PointF> s1 = RDP(chain1, eps);
        List<PointF> s2 = RDP(chain2, eps);
        List<PointF> res = new List<PointF>();
        for (int i = 0; i < s1.Count - 1; i++) res.Add(s1[i]);
        for (int i = 0; i < s2.Count - 1; i++) res.Add(s2[i]);
        return res;
    }

    private static List<PointF> RDP(List<PointF> pts, float eps) {
        if (pts.Count <= 2) return new List<PointF>(pts);
        double maxDist = 0; int index = 0;
        PointF a = pts[0], b = pts[pts.Count - 1];
        for (int i = 1; i < pts.Count - 1; i++) {
            double d = Math.Sqrt(PtSegDistSq(pts[i], a, b));
            if (d > maxDist) { maxDist = d; index = i; }
        }
        if (maxDist > eps) {
            List<PointF> left = RDP(pts.GetRange(0, index + 1), eps);
            List<PointF> right = RDP(pts.GetRange(index, pts.Count - index), eps);
            left.RemoveAt(left.Count - 1);
            left.AddRange(right);
            return left;
        } else return new List<PointF>() { a, b };
    }

    private static void DrawLocalSegment(byte[] mask, int RW, int RH, double lx, double ly, double cs, double sn, double u0, double v0, double u1, double v1, int halfThick) {
        double len = Math.Sqrt((u1 - u0) * (u1 - u0) + (v1 - v0) * (v1 - v0));
        int steps = (int)Math.Ceiling(len * 2) + 1;
        for (int s = 0; s <= steps; s++) {
            double t = (double)s / steps;
            double u = u0 + (u1 - u0) * t, v = v0 + (v1 - v0) * t;
            int px = (int)Math.Round(lx + u * cs - v * sn), py = (int)Math.Round(ly + u * sn + v * cs);
            for (int dy = -halfThick; dy <= halfThick; dy++) {
                int yy = py + dy;
                if (yy < 0 || yy >= RH) continue;
                for (int dx = -halfThick; dx <= halfThick; dx++) {
                    int xx = px + dx;
                    if (xx >= 0 && xx < RW) mask[yy * RW + xx] = 1;
                }
            }
        }
    }
}
"@

Add-Type -TypeDefinition $csharpCode -ReferencedAssemblies System.Drawing, System.Core
$raw = "C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\scratch\pentecostes_raw.jpg"
$scratchDir = "C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\scratch"
$webAssetsDir = "c:\Users\proye\Downloads\pentecostes-maruz\assets"
[FinalMasterBuilder]::BuildAll($raw, $scratchDir, $webAssetsDir)

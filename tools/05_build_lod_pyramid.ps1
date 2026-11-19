$ErrorActionPreference = "Stop"

$csharpCode = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.IO;
using System.Linq;

public class LodPyramidBuilder {
    public static void BuildPyramid(string rawPath, string tilesDir) {
        Directory.CreateDirectory(tilesDir);

        Console.WriteLine("Loading 102.7 MP master orthophoto...");
        Bitmap bmp = new Bitmap(rawPath);
        int W = bmp.Width;  // 8702
        int H = bmp.Height; // 11811

        BitmapData bd = bmp.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadWrite, PixelFormat.Format24bppRgb);
        int stride = bd.Stride;
        byte[] rgb = new byte[stride * H];
        Marshal.Copy(bd.Scan0, rgb, 0, rgb.Length);

        // Seamlessly restore natural forest over top-left print logo box & natural savanna over bottom-right Cuadro de Areas
        SeamlessPatchFill(rgb, W, H, stride, 945, 105, 3625, 2555, 3660, 120, 2250, 1720, 85);
        SeamlessSavannaFill(rgb, W, H, stride, 6175, 5955, W - 1, H - 1, 5080, 6180, 1040, 1580, 120);

        Marshal.Copy(rgb, 0, bd.Scan0, rgb.Length);
        bmp.UnlockBits(bd);

        ImageCodecInfo jpgEnc = ImageCodecInfo.GetImageDecoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);

        // 1. LOD-0: Ultra-fast instant progressive base (544 x 738 px, Q=76 -> ~45 KB!)
        SaveScaledJpg(bmp, 0, 0, W, H, 544, 738, Path.Combine(tilesDir, "lod0.jpg"), jpgEnc, 76L);
        Console.WriteLine("Generated LOD-0 (544x738)");

        // 2. LOD-1: Crisp 2K overview (2176 x 2953 px, Q=84 -> ~750 KB!)
        SaveScaledJpg(bmp, 0, 0, W, H, 2176, 2953, Path.Combine(tilesDir, "lod1.jpg"), jpgEnc, 84L);
        Console.WriteLine("Generated LOD-1 (2176x2953)");

        // 3. LOD-2: 4x4 Tile Grid (16 tiles covering 6528 x 8860 = 58 MP total, each tile 1632 x 2215 px, Q=86)
        int cols = 4, rows = 4;
        int outTileW = 1632, outTileH = 2215;
        for (int r = 0; r < rows; r++) {
            int sy0 = (int)Math.Round((double)r * H / rows);
            int sy1 = (int)Math.Round((double)(r + 1) * H / rows);
            int sh = sy1 - sy0;
            for (int c = 0; c < cols; c++) {
                int sx0 = (int)Math.Round((double)c * W / cols);
                int sx1 = (int)Math.Round((double)(c + 1) * W / cols);
                int sw = sx1 - sx0;
                string tilePath = Path.Combine(tilesDir, string.Format("z2_{0}_{1}.jpg", c, r));
                SaveScaledJpg(bmp, sx0, sy0, sw, sh, outTileW, outTileH, tilePath, jpgEnc, 86L);
            }
        }
        Console.WriteLine("Generated 16 LOD-2 HD tiles (4x4 grid, 6528x8860 effective resolution)!");

        bmp.Dispose();
    }

    private static void SaveScaledJpg(Bitmap src, int sx, int sy, int sw, int sh, int dw, int dh, string outPath, ImageCodecInfo enc, long quality) {
        using (Bitmap dst = new Bitmap(dw, dh, PixelFormat.Format24bppRgb)) {
            using (Graphics g = Graphics.FromImage(dst)) {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.SmoothingMode = SmoothingMode.HighQuality;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(src, new Rectangle(0, 0, dw, dh), new Rectangle(sx, sy, sw, sh), GraphicsUnit.Pixel);
            }
            EncoderParameters ep = new EncoderParameters(1);
            ep.Param[0] = new EncoderParameter(Encoder.Quality, quality);
            dst.Save(outPath, enc, ep);
        }
    }

    private static void SeamlessPatchFill(byte[] rgb, int W, int H, int stride, int x0, int y0, int x1, int y1, int sx0, int sy0, int sw, int sh, int feather) {
        for (int y = y0; y <= y1; y++) {
            if (y < 0 || y >= H) continue;
            int ry = (y - y0) % (sh * 2);
            if (ry >= sh) ry = sh * 2 - 1 - ry;
            int srcY = sy0 + ry;
            double wy = 1.0;
            if (y - y0 < feather) wy = Math.Min(wy, (double)(y - y0) / feather);
            if (y1 - y < feather) wy = Math.Min(wy, (double)(y1 - y) / feather);
            for (int x = x0; x <= x1; x++) {
                if (x < 0 || x >= W) continue;
                int rx = (x - x0) % (sw * 2);
                if (rx >= sw) rx = sw * 2 - 1 - rx;
                int srcX = sx0 + rx;
                double wx = 1.0;
                if (x - x0 < feather) wx = Math.Min(wx, (double)(x - x0) / feather);
                if (x1 - x < feather) wx = Math.Min(wx, (double)(x1 - x) / feather);
                double a = wx * wy;
                a = a * a * (3.0 - 2.0 * a);
                int dOff = y * stride + x * 3, sOff = srcY * stride + srcX * 3;
                rgb[dOff]     = (byte)Math.Round(rgb[dOff] * (1.0 - a) + rgb[sOff] * a);
                rgb[dOff + 1] = (byte)Math.Round(rgb[dOff + 1] * (1.0 - a) + rgb[sOff + 1] * a);
                rgb[dOff + 2] = (byte)Math.Round(rgb[dOff + 2] * (1.0 - a) + rgb[sOff + 2] * a);
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
            for (int x = x0; x <= x1; x++) {
                if (x < 0 || x >= W) continue;
                int rx = (x - x0) % (sw * 2);
                if (rx >= sw) rx = sw * 2 - 1 - rx;
                int srcX = sx0 + rx;
                double wx = 1.0;
                if (x - x0 < feather) wx = Math.Min(wx, (double)(x - x0) / feather);
                double a = wx * wy;
                a = a * a * (3.0 - 2.0 * a);
                int dOff = y * stride + x * 3, sOff = srcY * stride + srcX * 3;
                rgb[dOff]     = (byte)Math.Round(rgb[dOff] * (1.0 - a) + rgb[sOff] * a);
                rgb[dOff + 1] = (byte)Math.Round(rgb[dOff + 1] * (1.0 - a) + rgb[sOff + 1] * a);
                rgb[dOff + 2] = (byte)Math.Round(rgb[dOff + 2] * (1.0 - a) + rgb[sOff + 2] * a);
            }
        }
    }
}
"@

Add-Type -TypeDefinition $csharpCode -ReferencedAssemblies System.Drawing, System.Core
$raw = "C:\Users\proye\.gemini\antigravity\brain\d48cef7d-2090-4247-b841-6d9c6f024227\scratch\pentecostes_raw.jpg"
$tilesDir = "c:\Users\proye\Downloads\pentecostes-maruz\assets\tiles"
[LodPyramidBuilder]::BuildPyramid($raw, $tilesDir)
Get-ChildItem $tilesDir | Select-Object Name, @{N="KB";E={[Math]::Round($_.Length/1024,1)}} | Format-Table -AutoSize

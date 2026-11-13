using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using SkiaSharp;

namespace MiniCodex.Render.Rendering;

public class SkiaPreviewRenderer : IPreviewRenderer
{
    public byte[] Render(MeshGeometry mesh, int width, int height,
        float yawDegrees, float pitchDegrees, float zoom = 1.0f, RenderStyle? style = null,
        int supersample = 2)
    {
        style ??= new RenderStyle();
        if (zoom < 0.1f) zoom = 0.1f;
        if (supersample < 1) supersample = 1;
        if (supersample > 4) supersample = 4;

        var renderW = width * supersample;
        var renderH = height * supersample;

        byte bgA = (byte)((style.BackgroundArgb >> 24) & 0xFF);
        byte bgR = (byte)((style.BackgroundArgb >> 16) & 0xFF);
        byte bgG = (byte)((style.BackgroundArgb >> 8) & 0xFF);
        byte bgB = (byte)(style.BackgroundArgb & 0xFF);
        byte modelR = (byte)((style.ModelArgb >> 16) & 0xFF);
        byte modelG = (byte)((style.ModelArgb >> 8) & 0xFF);
        byte modelB = (byte)(style.ModelArgb & 0xFF);

        var verts = Transform(mesh.Vertices, yawDegrees, pitchDegrees);

        var min = new Vector3(float.MaxValue);
        var max = new Vector3(float.MinValue);
        foreach (var v in verts) { min = Vector3.Min(min, v); max = Vector3.Max(max, v); }
        var size = max - min;
        var center = (min + max) * 0.5f;
        var maxDim = MathF.Max(size.X, MathF.Max(size.Y, size.Z));
        var safeMaxDim = maxDim > 1e-6f ? maxDim : 1.0f;
        var fit = (MathF.Min(renderW, renderH) * 0.8f) / safeMaxDim;
        var scale = fit * zoom;

        var screen = new Vector2[verts.Length];
        var depth = new float[verts.Length];
        for (int i = 0; i < verts.Length; i++)
        {
            var p = verts[i] - center;
            screen[i] = new Vector2(renderW * 0.5f + p.X * scale, renderH * 0.5f - p.Y * scale);
            depth[i] = p.Z;
        }

        var zBuffer = new float[renderW * renderH];
        for (int i = 0; i < zBuffer.Length; i++) zBuffer[i] = float.NegativeInfinity;

        var pixels = new uint[renderW * renderH];
        var bgPacked = PackPremul(bgR, bgG, bgB, bgA);
        for (int i = 0; i < pixels.Length; i++) pixels[i] = bgPacked;

        float bgLum = (0.299f * bgR + 0.587f * bgG + 0.114f * bgB) / 255f;
        uint wireColor = bgLum > 0.5f ? PackPremul(40, 40, 40) : PackPremul(220, 220, 220);

        var keyDir = Vector3.Normalize(new Vector3(-0.4f, 0.6f, 1f));

        float[]? vertexLambert = null;
        if (mesh.HasVertexNormals)
        {
            vertexLambert = new float[verts.Length];
            for (int i = 0; i < verts.Length; i++)
            {
                var n = TransformNormal(mesh.VertexNormals[i], yawDegrees, pitchDegrees);
                var keyL = MathF.Abs(Vector3.Dot(n, keyDir));
                vertexLambert[i] = MathF.Max(style.MinLambert, keyL);
            }
        }

        for (int t = 0; t < mesh.Indices.Length; t += 3)
        {
            int i0 = mesh.Indices[t], i1 = mesh.Indices[t + 1], i2 = mesh.Indices[t + 2];
            var v0 = screen[i0]; var v1 = screen[i1]; var v2 = screen[i2];

            if (style.Wireframe)
            {
                DrawLine(pixels, zBuffer, renderW, renderH, v0, v1, depth[i0], depth[i1], wireColor);
                DrawLine(pixels, zBuffer, renderW, renderH, v1, v2, depth[i1], depth[i2], wireColor);
                DrawLine(pixels, zBuffer, renderW, renderH, v2, v0, depth[i2], depth[i0], wireColor);
                continue;
            }

            float l0, l1, l2;
            if (vertexLambert != null)
            {
                l0 = vertexLambert[i0];
                l1 = vertexLambert[i1];
                l2 = vertexLambert[i2];
            }
            else
            {
                var edge1 = verts[i1] - verts[i0];
                var edge2 = verts[i2] - verts[i0];
                var normal = Vector3.Cross(edge1, edge2);
                if (normal.LengthSquared() < 1e-10f) normal = Vector3.UnitZ;
                else normal = Vector3.Normalize(normal);
                var keyL = MathF.Abs(Vector3.Dot(normal, keyDir));
                var lam = MathF.Max(style.MinLambert, keyL);
                l0 = l1 = l2 = lam;
            }

            RasterizeTriangleGouraud(pixels, zBuffer, renderW, renderH,
                v0, v1, v2, depth[i0], depth[i1], depth[i2],
                l0, l1, l2, modelR, modelG, modelB);
        }

        uint[] finalPixels;
        if (supersample == 1)
        {
            finalPixels = pixels;
        }
        else
        {
            finalPixels = new uint[width * height];
            int n = supersample * supersample;
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    int accR = 0, accG = 0, accB = 0;
                    for (int dy = 0; dy < supersample; dy++)
                    {
                        int rowBase = (y * supersample + dy) * renderW;
                        for (int dx = 0; dx < supersample; dx++)
                        {
                            var p = pixels[rowBase + x * supersample + dx];
                            accR += (int)(p & 0xFF);
                            accG += (int)((p >> 8) & 0xFF);
                            accB += (int)((p >> 16) & 0xFF);
                        }
                    }
                    byte rr = (byte)(accR / n);
                    byte gg = (byte)(accG / n);
                    byte bb = (byte)(accB / n);
                    finalPixels[y * width + x] = PackPremul(rr, gg, bb);
                }
            }
        }

        using var bitmap = new SKBitmap(width, height, SKColorType.Rgba8888, SKAlphaType.Premul);
        unsafe
        {
            var dst = (uint*)bitmap.GetPixels().ToPointer();
            for (int i = 0; i < finalPixels.Length; i++) dst[i] = finalPixels[i];
        }

        using var image = SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SKEncodedImageFormat.Png, 90);
        return data.ToArray();
    }

    private static uint PackPremul(byte r, byte g, byte b, byte a = 255)
        => ((uint)a << 24) | ((uint)b << 16) | ((uint)g << 8) | r;

    private static Vector3[] Transform(Vector3[] verts, float yawDeg, float pitchDeg)
    {
        var cy = MathF.Cos(yawDeg * MathF.PI / 180f);
        var sy = MathF.Sin(yawDeg * MathF.PI / 180f);
        var cp = MathF.Cos(pitchDeg * MathF.PI / 180f);
        var sp = MathF.Sin(pitchDeg * MathF.PI / 180f);
        var result = new Vector3[verts.Length];
        for (int i = 0; i < verts.Length; i++)
        {
            var v = verts[i];
            var x0 = v.X; var y0 = v.Z; var z0 = -v.Y;
            var x1 = x0 * cy + z0 * sy;
            var z1 = -x0 * sy + z0 * cy;
            var y2 = y0 * cp - z1 * sp;
            var z2 = y0 * sp + z1 * cp;
            result[i] = new Vector3(x1, y2, z2);
        }
        return result;
    }

    private static Vector3 TransformNormal(Vector3 n, float yawDeg, float pitchDeg)
    {
        var cy = MathF.Cos(yawDeg * MathF.PI / 180f);
        var sy = MathF.Sin(yawDeg * MathF.PI / 180f);
        var cp = MathF.Cos(pitchDeg * MathF.PI / 180f);
        var sp = MathF.Sin(pitchDeg * MathF.PI / 180f);
        var x0 = n.X; var y0 = n.Z; var z0 = -n.Y;
        var x1 = x0 * cy + z0 * sy;
        var z1 = -x0 * sy + z0 * cy;
        var y2 = y0 * cp - z1 * sp;
        var z2 = y0 * sp + z1 * cp;
        var result = new Vector3(x1, y2, z2);
        if (result.LengthSquared() > 1e-12f) result = Vector3.Normalize(result);
        else result = Vector3.UnitZ;
        return result;
    }

    private static void RasterizeTriangleGouraud(
        uint[] pixels, float[] zBuffer, int width, int height,
        Vector2 p0, Vector2 p1, Vector2 p2,
        float z0, float z1, float z2,
        float l0, float l1, float l2,
        byte modelR, byte modelG, byte modelB)
    {
        var minX = Math.Max(0, (int)MathF.Floor(MathF.Min(p0.X, MathF.Min(p1.X, p2.X))));
        var maxX = Math.Min(width - 1, (int)MathF.Ceiling(MathF.Max(p0.X, MathF.Max(p1.X, p2.X))));
        var minY = Math.Max(0, (int)MathF.Floor(MathF.Min(p0.Y, MathF.Min(p1.Y, p2.Y))));
        var maxY = Math.Min(height - 1, (int)MathF.Ceiling(MathF.Max(p0.Y, MathF.Max(p1.Y, p2.Y))));
        if (minX > maxX || minY > maxY) return;

        var spanX = maxX - minX + 1;
        var spanY = maxY - minY + 1;

        if (spanX * spanY <= 9)
        {
            var lam = (l0 + l1 + l2) / 3f;
            byte r = (byte)MathF.Min(255, modelR * lam);
            byte g = (byte)MathF.Min(255, modelG * lam);
            byte b = (byte)MathF.Min(255, modelB * lam);
            var color = PackPremul(r, g, b);
            var zMax = MathF.Max(z0, MathF.Max(z1, z2));
            for (int py = minY; py <= maxY; py++)
            {
                int rowBase = py * width;
                for (int px = minX; px <= maxX; px++)
                {
                    var idx = rowBase + px;
                    if (zMax > zBuffer[idx]) { zBuffer[idx] = zMax; pixels[idx] = color; }
                }
            }
            return;
        }

        var denom = (p1.Y - p2.Y) * (p0.X - p2.X) + (p2.X - p1.X) * (p0.Y - p2.Y);
        if (MathF.Abs(denom) < 1e-6f) return;

        for (int y = minY; y <= maxY; y++)
        {
            for (int x = minX; x <= maxX; x++)
            {
                float px = x + 0.5f, py = y + 0.5f;
                var w0 = ((p1.Y - p2.Y) * (px - p2.X) + (p2.X - p1.X) * (py - p2.Y)) / denom;
                var w1 = ((p2.Y - p0.Y) * (px - p2.X) + (p0.X - p2.X) * (py - p2.Y)) / denom;
                var w2 = 1f - w0 - w1;
                if (w0 < 0 || w1 < 0 || w2 < 0) continue;
                var z = w0 * z0 + w1 * z1 + w2 * z2;
                var idx = y * width + x;
                if (z > zBuffer[idx])
                {
                    var lam = w0 * l0 + w1 * l1 + w2 * l2;
                    byte r = (byte)MathF.Min(255, modelR * lam);
                    byte g = (byte)MathF.Min(255, modelG * lam);
                    byte b = (byte)MathF.Min(255, modelB * lam);
                    pixels[idx] = PackPremul(r, g, b);
                    zBuffer[idx] = z;
                }
            }
        }
    }

    private static void DrawLine(
        uint[] pixels, float[] zBuffer, int width, int height,
        Vector2 a, Vector2 b, float zA, float zB, uint color)
    {
        int x0 = (int)MathF.Round(a.X);
        int y0 = (int)MathF.Round(a.Y);
        int x1 = (int)MathF.Round(b.X);
        int y1 = (int)MathF.Round(b.Y);

        int dx = Math.Abs(x1 - x0);
        int dy = Math.Abs(y1 - y0);
        int sx = x0 < x1 ? 1 : -1;
        int sy = y0 < y1 ? 1 : -1;
        int err = dx - dy;

        int totalDist = Math.Max(dx, dy);
        int step = 0;

        while (true)
        {
            if (x0 >= 0 && x0 < width && y0 >= 0 && y0 < height)
            {
                float t = totalDist > 0 ? (float)step / totalDist : 0f;
                float z = zA + (zB - zA) * t;
                var idx = y0 * width + x0;
                if (z >= zBuffer[idx]) { zBuffer[idx] = z; pixels[idx] = color; }
            }

            if (x0 == x1 && y0 == y1) break;
            int e2 = 2 * err;
            if (e2 > -dy) { err -= dy; x0 += sx; }
            if (e2 < dx) { err += dx; y0 += sy; }
            step++;
        }
    }
}
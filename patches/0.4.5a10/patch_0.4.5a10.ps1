#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a10 - File normals + Gouraud shading + SS=2 fixed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a10'
$ProjectRoot = 'D:\AI\MiniCodex'
$PatchDir    = Join-Path $ProjectRoot "patches\$Version"
$BackupRoot  = Join-Path $ProjectRoot 'backups'
$LogFile     = Join-Path $PatchDir 'patch.log'
$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $BackupRoot "${Version}_${Timestamp}"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $rel = $Path.Substring($ProjectRoot.Length).TrimStart('\')
    $dst = Join-Path $BackupDir $rel
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $Path -Destination $dst -Force
    Write-Log "Backup: $rel"
}

function Write-Text {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

# ============ MeshGeometry.cs ============
$meshGeomCs = @'
using System.Numerics;

namespace MiniCodex.Core.Models;

public class MeshGeometry
{
    public Vector3[] Vertices { get; set; } = Array.Empty<Vector3>();
    public Vector3[] VertexNormals { get; set; } = Array.Empty<Vector3>();
    public int[] Indices { get; set; } = Array.Empty<int>();
    public int TriangleCount => Indices.Length / 3;
    public bool HasVertexNormals => VertexNormals.Length == Vertices.Length;
}
'@

# ============ AssimpMeshLoader.cs (populate VertexNormals) ============
$loaderCs = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Numerics;
using Assimp;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;

namespace MiniCodex.Render.Loaders;

public class AssimpMeshLoader : IMeshLoader, IMeshGeometryLoader
{
    private static readonly HashSet<string> _extensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "stl", "obj", "3mf", "ply"
    };

    public IReadOnlyCollection<string> SupportedExtensions => _extensions;

    public MeshInfo? Load(string filePath)
    {
        var sw = Stopwatch.StartNew();
        var scene = ImportScene(filePath);
        if (scene == null)
        {
            Log.Warn("[Assimp] Load null-scene path=" + SafeName(filePath) + " took=" + sw.ElapsedMilliseconds + "ms");
            return null;
        }

        try
        {
            var polygonCount = 0;
            var min = new Vector3D(float.MaxValue, float.MaxValue, float.MaxValue);
            var max = new Vector3D(float.MinValue, float.MinValue, float.MinValue);
            var hasVertices = false;

            foreach (var mesh in scene.Meshes)
            {
                polygonCount += mesh.FaceCount;
                foreach (var v in mesh.Vertices)
                {
                    hasVertices = true;
                    if (v.X < min.X) min.X = v.X;
                    if (v.Y < min.Y) min.Y = v.Y;
                    if (v.Z < min.Z) min.Z = v.Z;
                    if (v.X > max.X) max.X = v.X;
                    if (v.Y > max.Y) max.Y = v.Y;
                    if (v.Z > max.Z) max.Z = v.Z;
                }
            }

            if (!hasVertices) return null;

            Log.Info("[Assimp] Load ok path=" + SafeName(filePath) + " polys=" + polygonCount + " took=" + sw.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
            return new MeshInfo
            {
                PolygonCount = polygonCount,
                FileSizeBytes = new FileInfo(filePath).Length,
                BoundingBoxMin = new[] { min.X, min.Y, min.Z },
                BoundingBoxMax = new[] { max.X, max.Y, max.Z },
            };
        }
        catch (Exception ex)
        {
            Log.Exception("[Assimp] Load failed path=" + SafeName(filePath), ex);
            return null;
        }
    }

    public MeshGeometry? LoadGeometry(string filePath)
    {
        var sw = Stopwatch.StartNew();
        var scene = ImportScene(filePath);
        if (scene == null)
        {
            Log.Warn("[Assimp] LoadGeometry null-scene path=" + SafeName(filePath) + " took=" + sw.ElapsedMilliseconds + "ms");
            return null;
        }

        try
        {
            var allVerts = new List<Vector3>();
            var allNormals = new List<Vector3>();
            var allIndices = new List<int>();
            var hasAnyNormals = true;

            foreach (var mesh in scene.Meshes)
            {
                var offset = allVerts.Count;
                var meshHasNormals = mesh.NormalCount == mesh.VertexCount && mesh.VertexCount > 0;

                if (meshHasNormals)
                {
                    for (int i = 0; i < mesh.VertexCount; i++)
                    {
                        var v = mesh.Vertices[i];
                        var n = mesh.Normals[i];
                        allVerts.Add(new Vector3(v.X, v.Y, v.Z));
                        allNormals.Add(new Vector3(n.X, n.Y, n.Z));
                    }
                }
                else
                {
                    hasAnyNormals = false;
                    for (int i = 0; i < mesh.VertexCount; i++)
                    {
                        var v = mesh.Vertices[i];
                        allVerts.Add(new Vector3(v.X, v.Y, v.Z));
                        allNormals.Add(Vector3.Zero);
                    }
                }

                // Faces -> triangles
                foreach (var face in mesh.Faces)
                {
                    if (face.IndexCount < 3) continue;
                    for (int i = 1; i < face.IndexCount - 1; i++)
                    {
                        var ia = offset + face.Indices[0];
                        var ib = offset + face.Indices[i];
                        var ic = offset + face.Indices[i + 1];
                        allIndices.Add(ia);
                        allIndices.Add(ib);
                        allIndices.Add(ic);

                        // If no normals from file, compute from this triangle.
                        if (!meshHasNormals)
                        {
                            var a = allVerts[ia];
                            var b = allVerts[ib];
                            var c = allVerts[ic];
                            var fn = Vector3.Cross(b - a, c - a);
                            if (fn.LengthSquared() > 1e-12f) fn = Vector3.Normalize(fn);
                            allNormals[ia] += fn;
                            allNormals[ib] += fn;
                            allNormals[ic] += fn;
                        }
                    }
                }
            }

            if (allVerts.Count == 0 || allIndices.Count == 0) return null;

            // Fallback path: normalize accumulated normals (per-vertex averaged).
            if (!hasAnyNormals)
            {
                for (int i = 0; i < allNormals.Count; i++)
                {
                    var n = allNormals[i];
                    if (n.LengthSquared() > 1e-12f) allNormals[i] = Vector3.Normalize(n);
                    else allNormals[i] = Vector3.UnitZ;
                }
            }

            var result = new MeshGeometry
            {
                Vertices = allVerts.ToArray(),
                VertexNormals = allNormals.ToArray(),
                Indices = allIndices.ToArray(),
            };
            Log.Info("[Assimp] LoadGeometry ok path=" + SafeName(filePath) +
                     " tris=" + result.TriangleCount +
                     " verts=" + result.Vertices.Length +
                     " hasFileNormals=" + hasAnyNormals +
                     " took=" + sw.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
            return result;
        }
        catch (Exception ex)
        {
            Log.Exception("[Assimp] LoadGeometry failed path=" + SafeName(filePath), ex);
            return null;
        }
    }

    private static Scene? ImportScene(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath)) return null;
        var sw = Stopwatch.StartNew();
        try
        {
            using (var ctx = new AssimpContext())
            {
                var scene = ctx.ImportFile(filePath, PostProcessSteps.Triangulate);
                Log.Info("[Assimp] ImportFile path=" + SafeName(filePath) + " ok=" + (scene != null) + " meshes=" + (scene != null && scene.HasMeshes ? scene.MeshCount : 0) + " took=" + sw.ElapsedMilliseconds + "ms");
                return scene != null && scene.HasMeshes ? scene : null;
            }
        }
        catch (Exception ex)
        {
            Log.Exception("[Assimp] ImportFile failed path=" + SafeName(filePath) + " took=" + sw.ElapsedMilliseconds + "ms", ex);
            return null;
        }
    }

    private static string SafeName(string filePath)
    {
        try { return Path.GetFileName(filePath) ?? filePath; } catch { return filePath; }
    }
}
'@

# ============ SkiaPreviewRenderer.cs (Gouraud + file normals) ============
$rendererCs = @'
using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using SkiaSharp;

namespace MiniCodex.Render.Rendering;

public class SkiaPreviewRenderer : IPreviewRenderer
{
    private const float FillStrength = 0.35f;
    private const float FillKeyThreshold = 0.5f;

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
        var fillDir = Vector3.Normalize(new Vector3(0.3f, -0.4f, 0.5f));

        // Precompute per-vertex lambert (Gouraud). If no vertex normals, fallback per-triangle.
        float[]? vertexLambert = null;
        if (mesh.HasVertexNormals)
        {
            vertexLambert = new float[verts.Length];
            for (int i = 0; i < verts.Length; i++)
            {
                var n = TransformNormal(mesh.VertexNormals[i], yawDegrees, pitchDegrees);
                vertexLambert[i] = ComputeLambert(n, keyDir, fillDir, style.MinLambert);
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
                var lam = ComputeLambert(normal, keyDir, fillDir, style.MinLambert);
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

    private static float ComputeLambert(Vector3 normal, Vector3 keyDir, Vector3 fillDir, float minLambert)
    {
        var keyL = MathF.Abs(Vector3.Dot(normal, keyDir));
        float combined = keyL;
        if (keyL < FillKeyThreshold)
        {
            var fillL = MathF.Abs(Vector3.Dot(normal, fillDir)) * FillStrength;
            combined = MathF.Min(1.0f, keyL + fillL);
        }
        return MathF.Max(minLambert, combined);
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
            // Sub-pixel: use avg lambert and max-z (front-most).
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
'@

# ============ PreviewGeneratorOptions.cs (SS=2 fixed) ============
$optionsCs = @'
namespace MiniCodex.Core.Services;

public class PreviewGeneratorOptions
{
    public int Width { get; set; } = 384;
    public int Height { get; set; } = 384;
    public float PitchDegrees { get; set; } = 15f;
    public float[] YawDegrees { get; set; } = { 180f, 270f, 0f, 90f };

    // Fixed supersample. Adaptive SS caused over-averaging on 1.5M+ poly meshes.
    public int Supersample { get; set; } = 2;
}
'@

# ============ RenderStyle.cs (MinLambert 0.45) ============
$renderStyleCs = @'
namespace MiniCodex.Core.Services;

/// <summary>Render parameters. Colors are ARGB (0xAARRGGBB).</summary>
public record RenderStyle
{
    public uint BackgroundArgb { get; init; } = 0xFFE0E0E0;
    public uint ModelArgb { get; init; } = 0xFFFFFFFF;
    public float MinLambert { get; init; } = 0.45f;
    public bool Wireframe { get; init; }
}
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $meshGeomPath    = Join-Path $ProjectRoot 'src\MiniCodex.Core\Models\MeshGeometry.cs'
    $loaderPath      = Join-Path $ProjectRoot 'src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs'
    $rendererPath    = Join-Path $ProjectRoot 'src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs'
    $optionsPath     = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGeneratorOptions.cs'
    $renderStylePath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\RenderStyle.cs'
    $previewGenPath  = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGenerator.cs'
    $vmPath          = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'

    Backup-File $meshGeomPath
    Backup-File $loaderPath
    Backup-File $rendererPath
    Backup-File $optionsPath
    Backup-File $renderStylePath
    Backup-File $previewGenPath
    Backup-File $vmPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    Write-Text -Path $meshGeomPath -Content $meshGeomCs
    Write-Log 'updated: MeshGeometry.cs (VertexNormals)'

    Write-Text -Path $loaderPath -Content $loaderCs
    Write-Log 'updated: AssimpMeshLoader.cs (file normals)'

    Write-Text -Path $rendererPath -Content $rendererCs
    Write-Log 'updated: SkiaPreviewRenderer.cs (Gouraud + file normals)'

    Write-Text -Path $optionsPath -Content $optionsCs
    Write-Log 'updated: PreviewGeneratorOptions.cs (SS=2 fixed, 384x384)'

    Write-Text -Path $renderStylePath -Content $renderStyleCs
    Write-Log 'updated: RenderStyle.cs (MinLambert 0.45)'

    # PreviewGenerator: bump RendererVersion, use fixed Supersample
    $pg = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    $pg = $pg -replace 'RendererVersion\s*=\s*"0\.4\.5a\d+"', 'RendererVersion = "0.4.5a10"'
    $pg = $pg -replace '_options\.PickSupersample\(triCount\)', '_options.Supersample'
    [IO.File]::WriteAllText($previewGenPath, $pg, [Text.UTF8Encoding]::new($false))
    Write-Log 'updated: PreviewGenerator.cs (RendererVersion=0.4.5a10, fixed SS)'

    # VM: _minLambert 0.4f -> 0.45f
    $vm = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)
    $vm = $vm -replace 'private float _minLambert = 0\.\d+f;', 'private float _minLambert = 0.45f;'
    [IO.File]::WriteAllText($vmPath, $vm, [Text.UTF8Encoding]::new($false))
    Write-Log 'updated: ModelCardPageViewModel.cs (_minLambert = 0.45f)'

    # README
    $readme = @'
# Patch 0.4.5a10 - File normals + Gouraud shading

**Iteration:** 0.4.5

## Root cause

Two issues:

1. Adaptive SS=4 on 1.5M tris: 16 subpixels averaged per output pixel
   washed out micro-detail -> flat grey surfaces. Only flat plates stayed bright.

2. Normals computed from cross(v1-v0, v2-v0) fail for STL with inconsistent winding.
   Assimp's mesh.Normals holds the file's per-vertex normals, which are correct
   even when winding is broken.

## Fixes

1. MeshGeometry gets VertexNormals; AssimpMeshLoader populates from mesh.Normals
   (fallback: computed face normal, averaged to vertex).

2. SkiaPreviewRenderer uses per-vertex normals transformed with the mesh, computes
   per-vertex lambert, and interpolates per-pixel via barycentric weights (Gouraud
   shading). Flat surfaces still look flat, smooth surfaces now show real curvature.

3. Fixed supersample = 2 (removed adaptive 3/4). Preview 384x384 (768x768 internal
   at SS=2). No ZBias (could skip triangles). Fill light with threshold (as 0.4.5a8).

4. MinLambert = 0.45 (between 0.4 and 0.5).

5. RendererVersion bumped to 0.4.5a10 - forces regeneration.

## Expected result

- Dense 1.5M poly models: smooth shading gradient visible (not flat grey).
- STL files with broken winding: correctly lit because we use file normals.
- OBJ files with per-vertex normals: Gouraud-shaded (smooth).
- Z-fighting: handled by natural z-order at 768x768 internal.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- After app restart: previews regenerate.
- No flat grey silhouettes; models show volume.
'@
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.5a10\README.md'

    # Verify
    $verifyG = [IO.File]::ReadAllText($meshGeomPath, [Text.Encoding]::UTF8)
    if ($verifyG -match 'VertexNormals') { Write-Log 'verify OK: MeshGeometry has VertexNormals' } else { Write-Log 'verify FAIL: VertexNormals missing' 'WARN' }

    $verifyL = [IO.File]::ReadAllText($loaderPath, [Text.Encoding]::UTF8)
    if ($verifyL -match 'mesh\.Normals') { Write-Log 'verify OK: loader reads mesh.Normals' } else { Write-Log 'verify FAIL: mesh.Normals not read' 'WARN' }

    $verifyR = [IO.File]::ReadAllText($rendererPath, [Text.Encoding]::UTF8)
    if ($verifyR -match 'RasterizeTriangleGouraud') { Write-Log 'verify OK: Gouraud rasterizer' } else { Write-Log 'verify FAIL: Gouraud missing' 'WARN' }
    if ($verifyR -match 'vertexLambert') { Write-Log 'verify OK: per-vertex lambert' } else { Write-Log 'verify FAIL: vertexLambert missing' 'WARN' }

    $verifyP = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    if ($verifyP -match '"0\.4\.5a10"') { Write-Log 'verify OK: RendererVersion = 0.4.5a10' }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a10 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a10] - 2026-11-12`r`n`r`n### Fixed`r`n- Flat grey shading on high-poly: use file normals from Assimp + Gouraud interpolation, SS=2 fixed (removed adaptive over-averaging).`r`n`r`n### Changed`r`n- MeshGeometry.VertexNormals; MinLambert 0.45; preview 384x384 SS=2.`r`n- RendererVersion 0.4.5a10.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a9\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md updated.'
        }
    }

    Write-Log "Patch $Version complete."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Log "Backup: $BackupDir" 'ERROR'
    exit 1
}
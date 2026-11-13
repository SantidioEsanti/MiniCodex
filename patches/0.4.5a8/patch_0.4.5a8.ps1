#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a8 - Final render polish: z-fighting bias, fill light, lighter shadows.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a8'
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

# ============ SkiaPreviewRenderer.cs (full rewrite) ============
$rendererCs = @'
using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using SkiaSharp;

namespace MiniCodex.Render.Rendering;

public class SkiaPreviewRenderer : IPreviewRenderer
{
    private const float ZBias = 1e-4f;

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
        const float fillStrength = 0.35f;

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

            var edge1 = verts[i1] - verts[i0];
            var edge2 = verts[i2] - verts[i0];
            var normal = Vector3.Cross(edge1, edge2);
            var normalLenSq = normal.LengthSquared();

            byte r, g, b;
            if (normalLenSq < 1e-10f)
            {
                r = (byte)(modelR * style.MinLambert);
                g = (byte)(modelG * style.MinLambert);
                b = (byte)(modelB * style.MinLambert);
            }
            else
            {
                normal = Vector3.Normalize(normal);
                var keyL = MathF.Abs(Vector3.Dot(normal, keyDir));
                // Fill light only on shadowed faces (keyL < 0.5). Lit faces stay at key strength.
                var combined = keyL;
                if (keyL < 0.5f)
                {
                    var fillL = MathF.Abs(Vector3.Dot(normal, fillDir)) * fillStrength;
                    combined = MathF.Min(1.0f, keyL + fillL);
                }
                var lambert = MathF.Max(style.MinLambert, combined);
                r = (byte)MathF.Min(255, modelR * lambert);
                g = (byte)MathF.Min(255, modelG * lambert);
                b = (byte)MathF.Min(255, modelB * lambert);
            }
            var packed = PackPremul(r, g, b);

            RasterizeTriangle(pixels, zBuffer, renderW, renderH,
                v0, v1, v2, depth[i0], depth[i1], depth[i2], packed);
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

    private static void RasterizeTriangle(
        uint[] pixels, float[] zBuffer, int width, int height,
        Vector2 p0, Vector2 p1, Vector2 p2,
        float z0, float z1, float z2, uint color)
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
            var z = (z0 + z1 + z2) / 3f;
            for (int py = minY; py <= maxY; py++)
            {
                int rowBase = py * width;
                for (int px = minX; px <= maxX; px++)
                {
                    var idx = rowBase + px;
                    if (z > zBuffer[idx] + ZBias) { zBuffer[idx] = z; pixels[idx] = color; }
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
                if (z > zBuffer[idx] + ZBias) { zBuffer[idx] = z; pixels[idx] = color; }
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
                if (z >= zBuffer[idx])
                {
                    zBuffer[idx] = z;
                    pixels[idx] = color;
                }
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

# ============ RenderStyle.cs (MinLambert default 0.5) ============
$renderStyleCs = @'
namespace MiniCodex.Core.Services;

/// <summary>Render parameters. Colors are ARGB (0xAARRGGBB).</summary>
public record RenderStyle
{
    public uint BackgroundArgb { get; init; } = 0xFFE0E0E0;
    public uint ModelArgb { get; init; } = 0xFFFFFFFF;
    public float MinLambert { get; init; } = 0.5f;
    public bool Wireframe { get; init; }
}
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $rendererPath    = Join-Path $ProjectRoot 'src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs'
    $renderStylePath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\RenderStyle.cs'
    $vmPath          = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
    $previewGenPath  = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGenerator.cs'

    Backup-File $rendererPath
    Backup-File $renderStylePath
    Backup-File $vmPath
    Backup-File $previewGenPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    Write-Text -Path $rendererPath -Content $rendererCs
    Write-Log 'updated: SkiaPreviewRenderer.cs (zbias + fill light)'

    Write-Text -Path $renderStylePath -Content $renderStyleCs
    Write-Log 'updated: RenderStyle.cs (MinLambert 0.4 -> 0.5)'

    # VM: _minLambert = 0.4f -> 0.5f
    $vm = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)
    $oldVm = 'private float _minLambert = 0.4f;'
    $newVm = 'private float _minLambert = 0.5f;'
    if ($vm.Contains($oldVm)) {
        $vm = $vm.Replace($oldVm, $newVm)
        [IO.File]::WriteAllText($vmPath, $vm, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: ModelCardPageViewModel.cs (_minLambert 0.4 -> 0.5)'
    } elseif ($vm.Contains($newVm)) {
        Write-Log 'ModelCardPageViewModel.cs: _minLambert already 0.5, skipping.' 'WARN'
    } else {
        Write-Log 'ModelCardPageViewModel.cs: _minLambert = 0.4f line not found' 'WARN'
    }

    # Bump RendererVersion
    $pg = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    if ($pg -match 'RendererVersion\s*=\s*"0\.4\.5a7"') {
        $pg = $pg -replace 'RendererVersion\s*=\s*"0\.4\.5a7"', 'RendererVersion = "0.4.5a8"'
        [IO.File]::WriteAllText($previewGenPath, $pg, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: PreviewGenerator.cs (RendererVersion = 0.4.5a8)'
    } elseif ($pg -match 'RendererVersion\s*=\s*"0\.4\.5a8"') {
        Write-Log 'PreviewGenerator.cs: RendererVersion already 0.4.5a8' 'WARN'
    } else {
        Write-Log 'PreviewGenerator.cs: RendererVersion pattern not found' 'WARN'
    }

    # README
    $readme = @'
# Patch 0.4.5a8 - Final render polish

**Iteration:** 0.4.5

## What it does

1. Z-buffer bias (ZBias = 1e-4) in RasterizeTriangle.
   Applied in main barycentric loop AND in sub-pixel bbox fill.
   Fixes z-fighting flicker on coplanar surfaces (bases, plinths, flat bottoms).

2. Fill light: second directional light (0.3, -0.4, 0.5), strength 0.35.
   Applied ONLY on shadowed faces (keyLambert < 0.5).
   Lit faces keep pure key light strength (no over-brighten).

3. MinLambert default 0.4 -> 0.5 in RenderStyle record and ModelCardPageViewModel._minLambert.
   Shadows ~25% lighter. Slider in UI stays, user can revert per-card.

4. RendererVersion 0.4.5a8 - forces preview regeneration.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- After app restart: previews regenerate automatically.
- Warrior-with-base and other coplanar-base models: no white speckle on base.
- All models slightly lighter in shadows (MinLambert 0.5).
'@
    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.5a8\README.md'

    # Verify
    $verifyR = [IO.File]::ReadAllText($rendererPath, [Text.Encoding]::UTF8)
    $checks = @(
        @('ZBias constant', ($verifyR -match 'const float ZBias = 1e-4f')),
        @('fillDir light', ($verifyR -match 'fillDir')),
        @('fillStrength', ($verifyR -match 'fillStrength'))
    )
    foreach ($c in $checks) {
        if ($c[1]) { Write-Log ("verify OK: " + $c[0]) }
        else { Write-Log ("verify FAIL: " + $c[0]) 'WARN' }
    }

    $verifyP = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    if ($verifyP -match '"0\.4\.5a8"') { Write-Log 'verify OK: RendererVersion = 0.4.5a8' }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a8 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a8] - 2026-11-12`r`n`r`n### Fixed`r`n- Z-fighting speckle on coplanar surfaces (ZBias 1e-4).`r`n`r`n### Changed`r`n- Fill light (0.35) on shadowed faces only - models with dark areas now readable.`r`n- MinLambert default 0.4 -> 0.5 (shadows 25% lighter).`r`n- RendererVersion 0.4.5a8.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a7\].*)$', "$entry`$1"
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
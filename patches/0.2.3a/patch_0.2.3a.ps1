#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.2.3a — фикс рендера превью: Z-up→Y-up, белый цвет, порядок байт.
.DESCRIPTION
    Правит SkiaPreviewRenderer (ориентация, цвет, RGBA-порядок) и PreviewGenerator
    (RendererVersion в кэше — инвалидация старых превью).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.2.3a'
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
    Write-Log "Backup: $rel -> $dst"
}

function Write-Text {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

$Files = @{}

# ============ Render/Rendering/SkiaPreviewRenderer.cs (полная замена) ============
$Files['src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs'] = @'
using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using SkiaSharp;

namespace MiniCodex.Render.Rendering;

public class SkiaPreviewRenderer : IPreviewRenderer
{
    // Светло-серый фон — на нём белая модель читается за счёт теней.
    private static readonly SKColor Background = new(0xE0, 0xE0, 0xE0);
    private static readonly SKColor BaseColor = new(0xFF, 0xFF, 0xFF);
    private const float MinLambert = 0.40f;

    public byte[] Render(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees)
    {
        var verts = Transform(mesh.Vertices, yawDegrees, pitchDegrees);

        var min = new Vector3(float.MaxValue);
        var max = new Vector3(float.MinValue);
        foreach (var v in verts) { min = Vector3.Min(min, v); max = Vector3.Max(max, v); }
        var size = max - min;
        var center = (min + max) * 0.5f;
        var maxDim = MathF.Max(size.X, MathF.Max(size.Y, size.Z));
        var scale = maxDim > 0 ? (MathF.Min(width, height) * 0.8f) / maxDim : 1f;

        var screen = new Vector2[verts.Length];
        var depth = new float[verts.Length];
        for (int i = 0; i < verts.Length; i++)
        {
            var p = verts[i] - center;
            screen[i] = new Vector2(width * 0.5f + p.X * scale, height * 0.5f - p.Y * scale);
            depth[i] = p.Z;
        }

        var zBuffer = new float[width * height];
        for (int i = 0; i < zBuffer.Length; i++) zBuffer[i] = float.NegativeInfinity;

        var pixels = new uint[width * height];
        var bgPacked = PackPremul(Background.Red, Background.Green, Background.Blue);
        for (int i = 0; i < pixels.Length; i++) pixels[i] = bgPacked;

        var lightDir = Vector3.Normalize(new Vector3(-0.3f, -0.5f, 1f));

        for (int t = 0; t < mesh.Indices.Length; t += 3)
        {
            int i0 = mesh.Indices[t], i1 = mesh.Indices[t + 1], i2 = mesh.Indices[t + 2];
            var v0 = screen[i0]; var v1 = screen[i1]; var v2 = screen[i2];

            var edge1 = verts[i1] - verts[i0];
            var edge2 = verts[i2] - verts[i0];
            var normal = Vector3.Cross(edge1, edge2);
            if (normal.LengthSquared() < 1e-10f) continue;
            normal = Vector3.Normalize(normal);
            var lambert = MathF.Max(MinLambert, Vector3.Dot(normal, lightDir));
            byte r = (byte)MathF.Min(255, BaseColor.Red * lambert);
            byte g = (byte)MathF.Min(255, BaseColor.Green * lambert);
            byte b = (byte)MathF.Min(255, BaseColor.Blue * lambert);
            var packed = PackPremul(r, g, b);

            RasterizeTriangle(pixels, zBuffer, width, height,
                v0, v1, v2, depth[i0], depth[i1], depth[i2], packed);
        }

        using var bitmap = new SKBitmap(width, height, SKColorType.Rgba8888, SKAlphaType.Premul);
        unsafe
        {
            var dst = (uint*)bitmap.GetPixels().ToPointer();
            for (int i = 0; i < pixels.Length; i++) dst[i] = pixels[i];
        }

        using var image = SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SKEncodedImageFormat.Png, 90);
        return data.ToArray();
    }

    // Skia Rgba8888 little-endian memory order: byte0=R, byte1=G, byte2=B, byte3=A.
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
            // 1) Z-up -> Y-up: 3D-печатные форматы (STL/3MF) используют Z как вертикаль.
            var x0 = v.X;
            var y0 = v.Z;
            var z0 = -v.Y;
            // 2) Yaw — вращение вокруг вертикали Y.
            var x1 = x0 * cy + z0 * sy;
            var z1 = -x0 * sy + z0 * cy;
            // 3) Pitch — наклон камеры (положительный = смотрим сверху).
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
                    zBuffer[idx] = z;
                    pixels[idx] = color;
                }
            }
        }
    }
}
'@

# ============ Core/Services/PreviewGenerator.cs (обновление: RendererVersion) ============
$Files['src\MiniCodex.Core\Services\PreviewGenerator.cs'] = @'
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MiniCodex.Core.Services;

public class PreviewGenerator : IPreviewGenerator
{
    // Увеличивайте при изменении алгоритма рендера — инвалидирует кэш.
    private const string RendererVersion = "0.2.3a";

    private readonly IPreviewRenderer _renderer;
    private readonly IMeshGeometryLoader _loader;
    private readonly string _cacheDir;
    private readonly PreviewGeneratorOptions _options;

    public PreviewGenerator(
        IPreviewRenderer renderer,
        IMeshGeometryLoader loader,
        string cacheDir,
        PreviewGeneratorOptions? options = null)
    {
        _renderer = renderer;
        _loader = loader;
        _cacheDir = cacheDir;
        _options = options ?? new PreviewGeneratorOptions();
    }

    public async Task<IReadOnlyList<string?>> EnsurePreviewsAsync(
        string modelId,
        string meshPath,
        DateTime sourceUpdatedAt,
        CancellationToken ct = default)
    {
        return await Task.Run(() => GenerateAll(modelId, meshPath, sourceUpdatedAt, ct), ct);
    }

    private IReadOnlyList<string?> GenerateAll(string modelId, string meshPath, DateTime sourceUpdatedAt, CancellationToken ct)
    {
        var results = new string?[_options.YawDegrees.Length];
        var modelDir = Path.Combine(_cacheDir, modelId);
        Directory.CreateDirectory(modelDir);

        var metaPath = Path.Combine(modelDir, "metadata.json");
        CacheMetadata? meta = null;
        if (File.Exists(metaPath))
        {
            try { meta = JsonSerializer.Deserialize<CacheMetadata>(File.ReadAllText(metaPath)); } catch { }
        }

        var needsRegen =
            meta == null ||
            meta.RendererVersion != RendererVersion ||
            meta.SourceUpdatedAt < sourceUpdatedAt;

        for (int i = 0; i < _options.YawDegrees.Length; i++)
        {
            if (ct.IsCancellationRequested) return results;
            var pngPath = Path.Combine(modelDir, $"{(int)_options.YawDegrees[i]}.png");
            if (needsRegen || !File.Exists(pngPath))
                pngPath = RenderOne(modelId, meshPath, _options.YawDegrees[i], pngPath, ct);
            results[i] = File.Exists(pngPath) ? pngPath : null;
        }

        if (needsRegen)
        {
            var newMeta = new CacheMetadata
            {
                ModelId = modelId,
                SourcePath = meshPath,
                SourceUpdatedAt = sourceUpdatedAt,
                GeneratedAt = DateTime.UtcNow,
                RendererVersion = RendererVersion,
            };
            File.WriteAllText(metaPath, JsonSerializer.Serialize(newMeta, new JsonSerializerOptions { WriteIndented = true }));
        }
        return results;
    }

    private string RenderOne(string modelId, string meshPath, float yaw, string outPath, CancellationToken ct)
    {
        var geometry = _loader.LoadGeometry(meshPath);
        if (geometry == null || geometry.TriangleCount == 0) return outPath;
        if (ct.IsCancellationRequested) return outPath;

        var png = _renderer.Render(geometry, _options.Width, _options.Height, yaw, _options.PitchDegrees);
        File.WriteAllBytes(outPath, png);
        return outPath;
    }

    private class CacheMetadata
    {
        [JsonPropertyName("modelId")] public string ModelId { get; set; } = string.Empty;
        [JsonPropertyName("sourcePath")] public string SourcePath { get; set; } = string.Empty;
        [JsonPropertyName("sourceUpdatedAt")] public DateTime SourceUpdatedAt { get; set; }
        [JsonPropertyName("generatedAt")] public DateTime GeneratedAt { get; set; }
        [JsonPropertyName("rendererVersion")] public string? RendererVersion { get; set; }
    }
}
'@

# ============ README патча ============
$Files['patches\0.2.3a\README.md'] = @'
# Патч 0.2.3a — фикс рендера превью

**Итерация:** 0.2 · **Статус:** реализован

## Причины

1. **Модели показывались сверху.** 3D-печатные форматы (STL/3MF) используют Z как
   вертикаль (Z-up), а рендерер работает в Y-up. Персонаж «лежал» вдоль Z и
   проецировался как вид сверху.
2. **Цвет модели был фиолетово-коричневым вместо заданного.** В `SkiaSharp.SKColorType.Rgba8888`
   порядок байт в памяти little-endian — `R, G, B, A`, а код паковал как `A, R, G, B` →
   каналы R и B поменялись местами.
3. **Кэш не инвалидировался** при изменении алгоритма рендера — старые PNG оставались
   бы навсегда до изменения `model.updated_at`.

## Что делает

- `SkiaPreviewRenderer.Transform`: добавлен первый шаг «Z-up → Y-up»: `(x, y, z) → (x, z, −y)`.
- `PackPremul`: корректный порядок байт для Skia (`A, B, G, R` в uint, что даёт `R,G,B,A` в памяти).
- `Background = #E0E0E0` (светло-серый) — белая модель читается за счёт теней.
- `BaseColor = #FFFFFF` — модель белая, с мягкой ламберт-затенённостью (`MinLambert = 0.40`).
- `PreviewGenerator.RendererVersion = "0.2.3a"` + поле в `metadata.json` — старая запись без
  поля → `null != "0.2.3a"` → принудительная перегенерация при первом показе карточек.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.3a\patch_0.2.3a.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24 теста, 0 сбоев (тест `Render_DifferentAngles` по-прежнему валиден: 0° и 37° на кубе дают разные PNG).
- При перезапуске приложения все превью перегенерируются: модели стоят вертикально, белые, вид ~3/4 сверху-сбоку.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs')
    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGenerator.cs')
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # CHANGELOG
    $marker = '<!-- patch 0.2.3a applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Fixed`n- 0.2.3a: превью моделей — вертикальная ориентация (Z-up→Y-up), белый цвет, корректный порядок RGBA.`n- 0.2.3a: инвалидация кэша превью через RendererVersion.`n"
            $cl = $cl -replace '(?m)^(## \[0\.2\.3\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.2.3a.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}
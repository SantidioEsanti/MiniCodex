#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.2.2 — Генерация 4 ракурсов превью + кэш PNG.
.DESCRIPTION
    SkiaSharp-рендерер + PreviewGenerator с кэшем по model.updated_at.
    Затрагивает Render (рендер, geometry), Core (интерфейсы + generator), Tests.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.2.2'
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

# ============ Core/Models/MeshGeometry.cs ============
$Files['src\MiniCodex.Core\Models\MeshGeometry.cs'] = @'
using System.Numerics;

namespace MiniCodex.Core.Models;

public class MeshGeometry
{
    public Vector3[] Vertices { get; set; } = Array.Empty<Vector3>();
    public int[] Indices { get; set; } = Array.Empty<int>();
    public int TriangleCount => Indices.Length / 3;
}
'@

# ============ Core/Services/IMeshGeometryLoader.cs ============
$Files['src\MiniCodex.Core\Services\IMeshGeometryLoader.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IMeshGeometryLoader
{
    MeshGeometry? LoadGeometry(string filePath);
}
'@

# ============ Core/Services/IPreviewRenderer.cs ============
$Files['src\MiniCodex.Core\Services\IPreviewRenderer.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IPreviewRenderer
{
    /// <summary>
    /// Возвращает PNG-байты рендера меша с заданным поворотом (yaw) и наклоном (pitch).
    /// </summary>
    byte[] Render(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees);
}
'@

# ============ Core/Services/IPreviewGenerator.cs ============
$Files['src\MiniCodex.Core\Services\IPreviewGenerator.cs'] = @'
namespace MiniCodex.Core.Services;

public interface IPreviewGenerator
{
    /// <summary>
    /// Гарантирует наличие 4 PNG-превью для модели.
    /// Возвращает пути к 4 файлам (0°, 90°, 180°, 270°). null-элементы — если ракурс не удалось сгенерировать.
    /// </summary>
    Task<IReadOnlyList<string?>> EnsurePreviewsAsync(
        string modelId,
        string meshPath,
        DateTime sourceUpdatedAt,
        CancellationToken ct = default);
}
'@

# ============ Core/Services/PreviewGeneratorOptions.cs ============
$Files['src\MiniCodex.Core\Services\PreviewGeneratorOptions.cs'] = @'
namespace MiniCodex.Core.Services;

public class PreviewGeneratorOptions
{
    public int Width { get; set; } = 256;
    public int Height { get; set; } = 256;
    public float PitchDegrees { get; set; } = 15f;
    public float[] YawDegrees { get; set; } = { 0f, 90f, 180f, 270f };
}
'@

# ============ Core/Services/PreviewGenerator.cs ============
$Files['src\MiniCodex.Core\Services\PreviewGenerator.cs'] = @'
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MiniCodex.Core.Services;

public class PreviewGenerator : IPreviewGenerator
{
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

        // Инвалидация: source не изменился + все углы на месте
        var needsRegen = meta == null || meta.SourceUpdatedAt < sourceUpdatedAt;
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
    }
}
'@

# ============ Render/Rendering/SkiaPreviewRenderer.cs ============
$Files['src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs'] = @'
using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using SkiaSharp;

namespace MiniCodex.Render.Rendering;

public class SkiaPreviewRenderer : IPreviewRenderer
{
    private static readonly SKColor Background = new(0xF5, 0xF5, 0xF5);
    private static readonly SKColor BaseColor = new(0x60, 0x60, 0x80);

    public byte[] Render(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees)
    {
        var verts = Transform(mesh.Vertices, yawDegrees, pitchDegrees);

        // bounding box после трансформа
        var min = new Vector3(float.MaxValue);
        var max = new Vector3(float.MinValue);
        foreach (var v in verts) { min = Vector3.Min(min, v); max = Vector3.Max(max, v); }
        var size = max - min;
        var center = (min + max) * 0.5f;
        var maxDim = MathF.Max(size.X, MathF.Max(size.Y, size.Z));
        var scale = maxDim > 0 ? (MathF.Min(width, height) * 0.8f) / maxDim : 1f;

        // проекция на экран + Z-buffer
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
        var bg = (uint)((255u << 24) | ((uint)Background.Red << 16) | ((uint)Background.Green << 8) | Background.Blue);
        for (int i = 0; i < pixels.Length; i++) pixels[i] = bg;

        // нормали и освещение
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
            var lambert = MathF.Max(0.15f, Vector3.Dot(normal, lightDir));
            var col = new SKColor(
                (byte)MathF.Min(255, BaseColor.Red * lambert),
                (byte)MathF.Min(255, BaseColor.Green * lambert),
                (byte)MathF.Min(255, BaseColor.Blue * lambert));
            var packed = (uint)((255u << 24) | ((uint)col.Red << 16) | ((uint)col.Green << 8) | col.Blue);

            RasterizeTriangle(pixels, zBuffer, width, height,
                v0, v1, v2,
                depth[i0], depth[i1], depth[i2], packed);
        }

        // конвертация в PNG
        using var bitmap = new SKBitmap(width, height, SKColorType.Rgba8888, SKAlphaType.Premul);
        unsafe
        {
            var dst = (uint*)bitmap.GetPixels().ToPointer();
            for (int i = 0; i < pixels.Length; i++)
            {
                var p = pixels[i];
                var r = (byte)((p >> 16) & 0xFF);
                var g = (byte)((p >> 8) & 0xFF);
                var b = (byte)(p & 0xFF);
                dst[i] = (uint)((255u << 24) | ((uint)r << 16) | ((uint)g << 8) | b);
            }
        }

        using var image = SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SKEncodedImageFormat.Png, 90);
        return data.ToArray();
    }

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
            var x1 = v.X * cy + v.Z * sy;
            var z1 = -v.X * sy + v.Z * cy;
            var y2 = v.Y * cp - z1 * sp;
            var z2 = v.Y * sp + z1 * cp;
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

# ============ Render/Loaders/AssimpMeshLoader.cs (дополнение LoadGeometry) ============
$Files['src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs'] = @'
using System.Numerics;
using Assimp;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;

namespace MiniCodex.Render.Loaders;

public class AssimpMeshLoader : IMeshLoader, IMeshGeometryLoader
{
    private static readonly HashSet<string> _extensions = new(StringComparer.OrdinalIgnoreCase)
    {
        "stl", "obj", "3mf", "ply"
    };

    public IReadOnlyCollection<string> SupportedExtensions => _extensions;

    public MeshInfo? Load(string filePath)
    {
        var scene = ImportScene(filePath);
        if (scene == null) return null;

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
        return new MeshInfo
        {
            PolygonCount = polygonCount,
            FileSizeBytes = new FileInfo(filePath).Length,
            BoundingBoxMin = new[] { min.X, min.Y, min.Z },
            BoundingBoxMax = new[] { max.X, max.Y, max.Z },
        };
    }

    public MeshGeometry? LoadGeometry(string filePath)
    {
        var scene = ImportScene(filePath);
        if (scene == null) return null;

        var allVerts = new List<Vector3>();
        var allIndices = new List<int>();

        foreach (var mesh in scene.Meshes)
        {
            var offset = allVerts.Count;
            foreach (var v in mesh.Vertices) allVerts.Add(new Vector3(v.X, v.Y, v.Z));
            foreach (var face in mesh.Faces)
            {
                if (face.IndexCount < 3) continue;
                // треугольники (Assimp постпроцесс Triangulate уже применён)
                for (int i = 1; i < face.IndexCount - 1; i++)
                {
                    allIndices.Add(offset + face.Indices[0]);
                    allIndices.Add(offset + face.Indices[i]);
                    allIndices.Add(offset + face.Indices[i + 1]);
                }
            }
        }

        if (allVerts.Count == 0 || allIndices.Count == 0) return null;
        return new MeshGeometry { Vertices = allVerts.ToArray(), Indices = allIndices.ToArray() };
    }

    private static Scene? ImportScene(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath)) return null;
        try
        {
            using var ctx = new AssimpContext();
            var scene = ctx.ImportFile(filePath, PostProcessSteps.Triangulate | PostProcessSteps.JoinIdenticalVertices);
            return scene != null && scene.HasMeshes ? scene : null;
        }
        catch { return null; }
    }
}
'@

# ============ Tests/Render/PreviewRendererTests.cs ============
$Files['src\MiniCodex.Tests\Render\PreviewRendererTests.cs'] = @'
using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Render.Rendering;
using Xunit;

namespace MiniCodex.Tests.Render;

public class PreviewRendererTests
{
    private static MeshGeometry Cube()
    {
        var v = new[]
        {
            new Vector3(-1,-1,-1), new Vector3(1,-1,-1), new Vector3(1,1,-1), new Vector3(-1,1,-1),
            new Vector3(-1,-1, 1), new Vector3(1,-1, 1), new Vector3(1,1, 1), new Vector3(-1,1, 1),
        };
        var idx = new[]
        {
            0,1,2, 0,2,3,  4,6,5, 4,7,6,
            0,4,5, 0,5,1,  1,5,6, 1,6,2,
            2,6,7, 2,7,3,  3,7,4, 3,4,0,
        };
        return new MeshGeometry { Vertices = v, Indices = idx };
    }

    [Fact]
    public void Render_ProducesValidPng()
    {
        var renderer = new SkiaPreviewRenderer();
        var png = renderer.Render(Cube(), 64, 64, 0f, 15f);
        Assert.NotNull(png);
        Assert.True(png.Length > 100);
        // PNG signature
        Assert.Equal(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }, png.Take(8).ToArray());
    }

    [Fact]
    public void Render_DifferentAngles_ProduceDifferentPngs()
    {
        var renderer = new SkiaPreviewRenderer();
        var a = renderer.Render(Cube(), 64, 64, 0f, 15f);
        var b = renderer.Render(Cube(), 64, 64, 90f, 15f);
        Assert.NotEqual(a, b);
    }
}
'@

# ============ Tests/Services/PreviewGeneratorTests.cs ============
$Files['src\MiniCodex.Tests\Services\PreviewGeneratorTests.cs'] = @'
using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using Xunit;

namespace MiniCodex.Tests.Services;

public class StubRenderer : IPreviewRenderer
{
    public int CallCount { get; private set; }
    public byte[] Render(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees)
    {
        CallCount++;
        // минимальный валидный PNG-подобный контент (не важно для теста кэша)
        return new byte[] { 0x89, 0x50, 0x4E, 0x47, (byte)CallCount, 0, 0, 0 };
    }
}

public class StubGeometryLoader : IMeshGeometryLoader
{
    public MeshGeometry? LoadGeometry(string filePath) => new()
    {
        Vertices = new[] { new Vector3(0, 0, 0), new Vector3(1, 0, 0), new Vector3(0, 1, 0) },
        Indices = new[] { 0, 1, 2 },
    };
}

public class PreviewGeneratorTests : IDisposable
{
    private readonly string _cacheDir;
    private readonly StubRenderer _renderer = new();

    public PreviewGeneratorTests()
    {
        _cacheDir = Path.Combine(Path.GetTempPath(), $"minicodex_cache_{Guid.NewGuid()}");
        Directory.CreateDirectory(_cacheDir);
    }

    public void Dispose() { try { Directory.Delete(_cacheDir, true); } catch { } }

    private PreviewGenerator NewGen() => new(_renderer, new StubGeometryLoader(), _cacheDir);

    [Fact]
    public async Task EnsurePreviews_CreatesFourFiles()
    {
        var gen = NewGen();
        var results = await gen.EnsurePreviewsAsync("m1", "fake.stl", DateTime.UtcNow);

        Assert.Equal(4, results.Count);
        Assert.All(results, r => Assert.NotNull(r));
        Assert.All(results, r => Assert.True(File.Exists(r!)));
        Assert.Equal(4, _renderer.CallCount);
    }

    [Fact]
    public async Task EnsurePreviews_SecondCall_UsesCache()
    {
        var gen = NewGen();
        var dt = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        await gen.EnsurePreviewsAsync("m1", "fake.stl", dt);
        var callsAfterFirst = _renderer.CallCount;

        await gen.EnsurePreviewsAsync("m1", "fake.stl", dt);
        Assert.Equal(callsAfterFirst, _renderer.CallCount); // не перегенерировано
    }

    [Fact]
    public async Task EnsurePreviews_SourceChanged_Regenerates()
    {
        var gen = NewGen();
        var t1 = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        await gen.EnsurePreviewsAsync("m1", "fake.stl", t1);
        var callsAfterFirst = _renderer.CallCount;

        var t2 = t1.AddHours(1);
        await gen.EnsurePreviewsAsync("m1", "fake.stl", t2);
        Assert.True(_renderer.CallCount > callsAfterFirst); // перегенерация
    }

    [Fact]
    public async Task EnsurePreviews_MissingGeometry_ReturnsNulls()
    {
        var gen = new PreviewGenerator(_renderer, new NullGeometryLoader(), _cacheDir);
        var results = await gen.EnsurePreviewsAsync("m1", "fake.stl", DateTime.UtcNow);
        Assert.All(results, r => Assert.Null(r));
        Assert.Equal(0, _renderer.CallCount);
    }

    private class NullGeometryLoader : IMeshGeometryLoader
    {
        public MeshGeometry? LoadGeometry(string filePath) => null;
    }
}
'@

# ============ Render.csproj (обновление: SkiaSharp) ============
$renderCsproj = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="AssimpNet" Version="4.1.0" />
    <PackageReference Include="SkiaSharp" Version="2.88.8" />
    <PackageReference Include="SkiaSharp.NativeAssets.Win32" Version="2.88.8" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\MiniCodex.Core\MiniCodex.Core.csproj" />
  </ItemGroup>
</Project>
'@

# ============ README патча ============
$Files['patches\0.2.2\README.md'] = @'
# Патч 0.2.2 — Генерация 4 ракурсов превью + кэш PNG

**Итерация:** 0.2 · **Статус:** реализован

## Что делает

- `SkiaPreviewRenderer` — оффскрин-рендер (SkiaSharp) с Z-buffer и flat shading.
- `IMeshGeometryLoader` + `AssimpMeshLoader.LoadGeometry` — полная геометрия (вершины + индексы) из STL/OBJ/3MF/PLY.
- `PreviewGenerator` — 4 ракурса (0°/90°/180°/270°) + наклон 15°.
- Кэш: `{cacheDir}/{modelId}/{angle}.png` + `metadata.json`.
- Инвалидация по `source_updated_at`: если источник новее — перегенерация.
- Тесты: 2 × рендерер + 4 × generator = 6 новых.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.2\patch_0.2.2.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24 теста (18 старых + 6 новых), все зелёные.
'@

# ============ Основной сценарий ============
$renderCsprojPath = Join-Path $ProjectRoot 'src\MiniCodex.Render\MiniCodex.Render.csproj'
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    Backup-File $renderCsprojPath
    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs')
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # Перезаписываем Render.csproj с новыми пакетами
    Write-Text -Path $renderCsprojPath -Content $renderCsproj
    Write-Log 'updated: src\MiniCodex.Render\MiniCodex.Render.csproj (SkiaSharp)'

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # CHANGELOG
    $marker = '<!-- patch 0.2.2 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n## [0.2.2] - 2026-11-10`n`n### Added`n- SkiaPreviewRenderer (оффскрин, Z-buffer, flat shading).`n- AssimpMeshLoader.LoadGeometry.`n- PreviewGenerator: 4 ракурса + кэш PNG.`n- 6 тестов рендера и кэша.`n"
            $cl = $cl -replace '(?m)^(## \[0\.2\.1b\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.2.2.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
    Write-Log 'Следующий шаг: dotnet build + dotnet test'
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}
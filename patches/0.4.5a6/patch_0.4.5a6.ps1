#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a6 - Fix remaining shatter: bbox fill for sub-pixel, degenerate draw, SS=3 default.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a6'
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

# ============ SkiaPreviewRenderer.cs (full rewrite with fixes) ============
$rendererCs = @'
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
        // Scale safety: if bbox collapsed (< 1e-6), fall back to unit-cube scaling.
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

        var lightDir = Vector3.Normalize(new Vector3(-0.4f, 0.6f, 1f));

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
                // Degenerate triangle (zero area). Draw with MinLambert instead of skipping.
                r = (byte)(modelR * style.MinLambert);
                g = (byte)(modelG * style.MinLambert);
                b = (byte)(modelB * style.MinLambert);
            }
            else
            {
                normal = Vector3.Normalize(normal);
                var lambert = MathF.Max(style.MinLambert, Vector3.Dot(normal, lightDir));
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

        // Sub-pixel: if bbox area (pixels) is small, fill the entire bbox instead of one center pixel.
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
                    if (z > zBuffer[idx]) { zBuffer[idx] = z; pixels[idx] = color; }
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
                if (z > zBuffer[idx]) { zBuffer[idx] = z; pixels[idx] = color; }
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

# ============ PreviewGeneratorOptions.cs ============
$optionsCs = @'
namespace MiniCodex.Core.Services;

public class PreviewGeneratorOptions
{
    public int Width { get; set; } = 256;
    public int Height { get; set; } = 256;
    public float PitchDegrees { get; set; } = 15f;
    public float[] YawDegrees { get; set; } = { 180f, 270f, 0f, 90f };
    public int Supersample { get; set; } = 3;
}
'@

# ============ PreviewGenerator.cs (pass Supersample) ============
$previewGenCs = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public class PreviewGenerator : IPreviewGenerator
{
    private const string RendererVersion = "0.4.5a6";

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
        float baseYawDegrees = 0f,
        float basePitchDegrees = 0f,
        bool forceRegenerate = false,
        CancellationToken ct = default)
    {
        return await Task.Run(
            () => GenerateAll(modelId, meshPath, sourceUpdatedAt, baseYawDegrees, basePitchDegrees, forceRegenerate, ct),
            ct);
    }

    private IReadOnlyList<string?> GenerateAll(
        string modelId, string meshPath, DateTime sourceUpdatedAt,
        float baseYaw, float basePitch, bool forceRegenerate, CancellationToken ct)
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
            forceRegenerate ||
            meta == null ||
            meta.RendererVersion != RendererVersion ||
            meta.SourceUpdatedAt < sourceUpdatedAt ||
            Math.Abs(meta.BaseYaw - baseYaw) > 0.01f ||
            Math.Abs(meta.BasePitch - basePitch) > 0.01f;

        var modelShort = SafeName(meshPath);
        Log.Info("[PreviewGen] START model=" + modelId + " path=" + modelShort + " needsRegen=" + needsRegen + " mem=" + Log.MemoryMb() + "MB");

        MeshGeometry? geometry = null;
        try
        {
            for (int i = 0; i < _options.YawDegrees.Length; i++)
            {
                if (ct.IsCancellationRequested) break;

                var pngPath = Path.Combine(modelDir, ((int)_options.YawDegrees[i]).ToString() + ".png");
                var needThisAngle = needsRegen || !File.Exists(pngPath);

                if (needThisAngle)
                {
                    if (geometry == null)
                    {
                        var swLoad = Stopwatch.StartNew();
                        try
                        {
                            geometry = _loader.LoadGeometry(meshPath);
                        }
                        catch (Exception ex)
                        {
                            Log.Exception("[PreviewGen] LoadGeometry failed model=" + modelId, ex);
                            geometry = null;
                        }
                        Log.Info("[PreviewGen] LoadGeometry model=" + modelId +
                                 " tris=" + (geometry == null ? 0 : geometry.TriangleCount) +
                                 " took=" + swLoad.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
                    }

                    if (geometry != null && geometry.TriangleCount > 0)
                    {
                        var swRender = Stopwatch.StartNew();
                        try
                        {
                            var yaw = _options.YawDegrees[i] + baseYaw;
                            var pitch = _options.PitchDegrees + basePitch;
                            var png = _renderer.Render(geometry, _options.Width, _options.Height, yaw, pitch, 1.0f, null, _options.Supersample);
                            File.WriteAllBytes(pngPath, png);
                            Log.Info("[PreviewGen] Render model=" + modelId +
                                     " angle=" + (int)_options.YawDegrees[i] +
                                     " took=" + swRender.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
                        }
                        catch (Exception ex)
                        {
                            Log.Exception("[PreviewGen] Render failed model=" + modelId + " angle=" + i, ex);
                        }
                    }
                }

                results[i] = File.Exists(pngPath) ? pngPath : null;
            }
        }
        finally
        {
            geometry = null;
            try
            {
                GC.Collect(GC.MaxGeneration, GCCollectionMode.Optimized, blocking: false);
            }
            catch { }
            Log.Info("[PreviewGen] DONE model=" + modelId + " mem=" + Log.MemoryMb() + "MB");
        }

        if (needsRegen)
        {
            try
            {
                var newMeta = new CacheMetadata
                {
                    ModelId = modelId,
                    SourcePath = meshPath,
                    SourceUpdatedAt = sourceUpdatedAt,
                    GeneratedAt = DateTime.UtcNow,
                    RendererVersion = RendererVersion,
                    BaseYaw = baseYaw,
                    BasePitch = basePitch,
                };
                File.WriteAllText(metaPath, JsonSerializer.Serialize(newMeta, new JsonSerializerOptions { WriteIndented = true }));
            }
            catch (Exception ex)
            {
                Log.Exception("[PreviewGen] write metadata failed model=" + modelId, ex);
            }
        }
        return results;
    }

    private static string SafeName(string filePath)
    {
        try { return Path.GetFileName(filePath) ?? filePath; } catch { return filePath; }
    }

    private class CacheMetadata
    {
        [JsonPropertyName("modelId")] public string ModelId { get; set; } = string.Empty;
        [JsonPropertyName("sourcePath")] public string SourcePath { get; set; } = string.Empty;
        [JsonPropertyName("sourceUpdatedAt")] public DateTime SourceUpdatedAt { get; set; }
        [JsonPropertyName("generatedAt")] public DateTime GeneratedAt { get; set; }
        [JsonPropertyName("rendererVersion")] public string? RendererVersion { get; set; }
        [JsonPropertyName("baseYaw")] public float BaseYaw { get; set; }
        [JsonPropertyName("basePitch")] public float BasePitch { get; set; }
    }
}
'@

# ============ ThreeDViewer.axaml.cs (High=SS3, Medium=SS2, Low=SS1) ============
$viewerCs = @'
using Avalonia;
using Avalonia.Controls;
using Avalonia.Data;
using Avalonia.Input;
using Avalonia.Media.Imaging;
using Avalonia.Styling;
using Avalonia.Threading;
using MiniCodex.App.ViewModels;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Render.Loaders;
using MiniCodex.Render.Rendering;

namespace MiniCodex.App.Views;

public partial class ThreeDViewer : UserControl
{
    private readonly SkiaPreviewRenderer _renderer = new();
    private readonly AssimpMeshLoader _loader = new();
    private MeshGeometry? _geometry;

    private float _yaw = 180f;
    private float _pitch = 15f;
    private float _zoom = 1.0f;
    private Point? _lastPointer;
    private bool _isDragging;
    private bool _renderInProgress;
    private bool _renderPending;
    private int _renderWidth = 480;
    private int _renderHeight = 480;

    public static readonly StyledProperty<string?> MeshFilePathProperty =
        AvaloniaProperty.Register<ThreeDViewer, string?>(nameof(MeshFilePath));

    public static readonly StyledProperty<float> MinLambertProperty =
        AvaloniaProperty.Register<ThreeDViewer, float>(nameof(MinLambert), 0.4f);

    public static readonly StyledProperty<bool> WireframeProperty =
        AvaloniaProperty.Register<ThreeDViewer, bool>(nameof(Wireframe));

    public static readonly StyledProperty<float> YawProperty =
        AvaloniaProperty.Register<ThreeDViewer, float>(nameof(Yaw), 180f, defaultBindingMode: BindingMode.TwoWay);

    public static readonly StyledProperty<float> PitchProperty =
        AvaloniaProperty.Register<ThreeDViewer, float>(nameof(Pitch), 15f, defaultBindingMode: BindingMode.TwoWay);

    public static readonly StyledProperty<string> QualityProperty =
        AvaloniaProperty.Register<ThreeDViewer, string>(nameof(Quality), "High");

    public string? MeshFilePath
    {
        get => GetValue(MeshFilePathProperty);
        set => SetValue(MeshFilePathProperty, value);
    }

    public float MinLambert
    {
        get => GetValue(MinLambertProperty);
        set => SetValue(MinLambertProperty, value);
    }

    public bool Wireframe
    {
        get => GetValue(WireframeProperty);
        set => SetValue(WireframeProperty, value);
    }

    public float Yaw
    {
        get => GetValue(YawProperty);
        set => SetValue(YawProperty, value);
    }

    public float Pitch
    {
        get => GetValue(PitchProperty);
        set => SetValue(PitchProperty, value);
    }

    public string Quality
    {
        get => GetValue(QualityProperty);
        set => SetValue(QualityProperty, value);
    }

    public ThreeDViewer()
    {
        InitializeComponent();
        SizeChanged += (_, e) =>
        {
            _renderWidth = Math.Max(128, (int)e.NewSize.Width);
            _renderHeight = Math.Max(128, (int)e.NewSize.Height);
            RequestRender();
        };
        if (Application.Current != null)
            Application.Current.ActualThemeVariantChanged += OnThemeChanged;
    }

    private void OnThemeChanged(object? sender, EventArgs e) => RequestRender();

    protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
    {
        base.OnPropertyChanged(change);
        if (change.Property == MeshFilePathProperty)
            _ = LoadGeometryAsync(change.GetNewValue<string?>());
        else if (change.Property == YawProperty)
        {
            _yaw = change.GetNewValue<float>();
            RequestRender();
        }
        else if (change.Property == PitchProperty)
        {
            _pitch = change.GetNewValue<float>();
            RequestRender();
        }
        else if (change.Property == MinLambertProperty || change.Property == WireframeProperty || change.Property == QualityProperty)
            RequestRender();
    }

    private RenderStyle BuildStyle()
    {
        var isDark = Application.Current?.ActualThemeVariant == ThemeVariant.Dark;
        uint bg = isDark ? 0xFF2D2D2D : 0xFFE0E0E0;
        return new RenderStyle
        {
            BackgroundArgb = bg,
            ModelArgb = 0xFFFFFFFF,
            MinLambert = Math.Clamp(MinLambert, 0f, 1f),
            Wireframe = Wireframe,
        };
    }

    private void SetViewState(ThreeDViewState state, string? error = null)
    {
        if (DataContext is ModelCardPageViewModel vm)
        {
            vm.ThreeDViewState = state;
            vm.ThreeDErrorMessage = error;
        }
    }

    private async Task LoadGeometryAsync(string? path)
    {
        _geometry = null;
        PreviewHost.Source = null;

        if (string.IsNullOrEmpty(path))
        {
            SetViewState(ThreeDViewState.FileNotChosen);
            return;
        }

        SetViewState(ThreeDViewState.Loading);
        try
        {
            var geo = await Task.Run(() => _loader.LoadGeometry(path));
            if (geo == null)
            {
                SetViewState(ThreeDViewState.ParseFailed);
                return;
            }
            _geometry = geo;
            SetViewState(ThreeDViewState.Loaded);
            RequestRender();
        }
        catch (Exception ex)
        {
            SetViewState(ThreeDViewState.Error, ex.Message);
        }
    }

    private void RequestRender()
    {
        if (_geometry == null) return;
        if (_renderInProgress) { _renderPending = true; return; }
        _renderInProgress = true;
        _ = RenderLoop();
    }

    private (int w, int h, int supersample) PickRenderSettings()
    {
        var isHigh = string.Equals(Quality, "High", StringComparison.OrdinalIgnoreCase);
        var isLow = string.Equals(Quality, "Low", StringComparison.OrdinalIgnoreCase);

        if (_isDragging)
        {
            var divisor = isLow ? 4 : 2;
            var w = Math.Max(96, _renderWidth / divisor);
            var h = Math.Max(96, _renderHeight / divisor);
            return (w, h, 1);
        }
        else
        {
            int ss;
            if (isHigh) ss = 3;
            else if (isLow) ss = 1;
            else ss = 2; // Medium
            return (_renderWidth, _renderHeight, ss);
        }
    }

    private async Task RenderLoop()
    {
        try
        {
            while (true)
            {
                _renderPending = false;
                var yaw = _yaw; var pitch = _pitch; var zoom = _zoom;
                var geo = _geometry;
                var style = BuildStyle();
                if (geo == null) break;

                var (w, h, ss) = PickRenderSettings();

                byte[]? png = null;
                try
                {
                    png = await Task.Run(() => _renderer.Render(geo, w, h, yaw, pitch, zoom, style, ss));
                }
                catch { }

                if (png != null)
                {
                    await Dispatcher.UIThread.InvokeAsync(() =>
                    {
                        try
                        {
                            using var ms = new MemoryStream(png);
                            PreviewHost.Source = new Bitmap(ms);
                        }
                        catch { }
                    });
                }
                if (!_renderPending) break;
            }
        }
        finally
        {
            _renderInProgress = false;
            if (_renderPending) RequestRender();
        }
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        _lastPointer = e.GetPosition(this);
        e.Pointer.Capture(this);
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        _lastPointer = null;
        e.Pointer.Capture(null);

        if (_isDragging)
        {
            _isDragging = false;
            RequestRender();
        }
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        if (_lastPointer == null || _geometry == null) return;
        var pos = e.GetPosition(this);
        var dx = (float)(pos.X - _lastPointer.Value.X);
        var dy = (float)(pos.Y - _lastPointer.Value.Y);
        _lastPointer = pos;

        if (Math.Abs(dx) + Math.Abs(dy) < 0.5f) return;

        _isDragging = true;
        _yaw += dx * 0.5f;
        _pitch = Math.Clamp(_pitch + dy * 0.5f, -89f, 89f);

        SetCurrentValue(YawProperty, _yaw);
        SetCurrentValue(PitchProperty, _pitch);

        RequestRender();
    }

    protected override void OnPointerWheelChanged(PointerWheelEventArgs e)
    {
        base.OnPointerWheelChanged(e);
        if (_geometry == null) return;
        _zoom = Math.Clamp(_zoom * (1f + (float)e.Delta.Y * 0.1f), 0.2f, 5f);
        RequestRender();
        e.Handled = true;
    }
}
'@

# ============ README ============
$readme = @'
# Patch 0.4.5a6 - Fix remaining shatter

**Iteration:** 0.4.5

## Root cause (persisted after 0.4.5a5)

1. Sub-pixel force-draw painted only the CENTER pixel of tiny bboxes.
   Neighbour pixels stayed empty -> sandpaper on smooth models, holes on dense ones.
   Fix: fill ENTIRE bbox (up to 3x3 pixels = 9) when spanX * spanY <= 9.

2. Degenerate triangles (normal ~ 0) were SKIPPED via `continue`.
   Many STL meshes contain degenerate faces after Triangulate (no JoinIdenticalVertices).
   Fix: draw with MinLambert color instead of skipping.

3. SS=2 insufficient for 1.5M polygons at 512x512.
   Average triangle = 0.17 pixels, adjacent triangles land in different pixels.
   Fix: High quality now uses SS=3 (768x768 internal), each output pixel averages 9 subpixels.

4. Scale safety: bbox with maxDim < 1e-6 rendered as unit cube
   (fixes "empty" previews seen for a few models).

5. RendererVersion bumped to "0.4.5a6" - forces all previews to regenerate.

## Quality mapping

- High: idle SS=3 (768x768 internal, ~1.8s per model), drag half-res SS=1 (200ms).
- Medium: idle SS=2 (512x512, ~800ms), drag half-res SS=1 (200ms).
- Low: idle SS=1 (256x256, ~200ms), drag quarter-res SS=1 (~50ms).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- After app restart, previews regenerate automatically (RendererVersion changed).
- No shatter on High. Medium may have slight sandpaper but usable. Low for speed only.
- Viewer High idle: 1.8s wait, but crisp. Drag: 200ms/frame.
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $rendererPath = Join-Path $ProjectRoot 'src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs'
    $optionsPath  = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGeneratorOptions.cs'
    $previewGenPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGenerator.cs'
    $viewerPath   = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ThreeDViewer.axaml.cs'

    Backup-File $rendererPath
    Backup-File $optionsPath
    Backup-File $previewGenPath
    Backup-File $viewerPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    Write-Text -Path $rendererPath -Content $rendererCs
    Write-Log 'updated: SkiaPreviewRenderer.cs (bbox fill + degenerate draw + scale safety)'

    Write-Text -Path $optionsPath -Content $optionsCs
    Write-Log 'updated: PreviewGeneratorOptions.cs (Supersample = 3)'

    Write-Text -Path $previewGenPath -Content $previewGenCs
    Write-Log 'updated: PreviewGenerator.cs (Supersample passed, RendererVersion=0.4.5a6)'

    Write-Text -Path $viewerPath -Content $viewerCs
    Write-Log 'updated: ThreeDViewer.axaml.cs (High SS=3, Medium SS=2, Low SS=1)'

    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.5a6\README.md'

    # Verify
    $verifyR = [IO.File]::ReadAllText($rendererPath, [Text.Encoding]::UTF8)
    $checks = @(
        @('spanX * spanY sub-pixel', ($verifyR -match 'spanX \* spanY <= 9')),
        @('degenerate draw (no continue)', ($verifyR -notmatch 'normal\.LengthSquared\(\) < 1e-10f\) continue;')),
        @('MinLambert for degenerate', ($verifyR -match 'Degenerate triangle.*MinLambert'))
    )
    foreach ($c in $checks) {
        if ($c[1]) { Write-Log ("verify OK: " + $c[0]) }
        else { Write-Log ("verify FAIL: " + $c[0]) 'WARN' }
    }

    $verifyP = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    if ($verifyP -match '0\.4\.5a6') { Write-Log 'verify OK: RendererVersion = 0.4.5a6' }

    $verifyO = [IO.File]::ReadAllText($optionsPath, [Text.Encoding]::UTF8)
    if ($verifyO -match 'Supersample.*= 3') { Write-Log 'verify OK: PreviewGeneratorOptions.Supersample = 3' }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a6 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a6] - 2026-11-12`r`n`r`n### Fixed`r`n- Shatter on dense models: sub-pixel bbox fill (up to 9 pixels), degenerate triangles drawn, scale safety.`r`n`r`n### Changed`r`n- High quality: SS=3 (was 2). Medium: SS=2. Low: SS=1.`r`n- RendererVersion 0.4.5a6 - forces preview regeneration.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a5\.1\].*)$', "$entry`$1"
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
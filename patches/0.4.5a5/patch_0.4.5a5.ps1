#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a5 - Fix polygon shatter (sub-pixel force-draw + supersample) + Quality/LOD for viewer.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a5'
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

# ============ IPreviewRenderer.cs ============
$iPreviewCs = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IPreviewRenderer
{
    /// <summary>
    /// Render mesh to PNG bytes. supersample=2 renders at 2x internal resolution
    /// and downsamples, fixing sub-pixel triangle coverage at high polygon counts.
    /// </summary>
    byte[] Render(MeshGeometry mesh, int width, int height,
        float yawDegrees, float pitchDegrees, float zoom = 1.0f,
        RenderStyle? style = null, int supersample = 2);
}
'@

# ============ SkiaPreviewRenderer.cs ============
$skiaRendererCs = @'
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
        var fit = maxDim > 0 ? (MathF.Min(renderW, renderH) * 0.8f) / maxDim : 1f;
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
            if (normal.LengthSquared() < 1e-10f) continue;
            normal = Vector3.Normalize(normal);
            var lambert = MathF.Max(style.MinLambert, Vector3.Dot(normal, lightDir));
            byte r = (byte)MathF.Min(255, modelR * lambert);
            byte g = (byte)MathF.Min(255, modelG * lambert);
            byte b = (byte)MathF.Min(255, modelB * lambert);
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

        // Sub-pixel triangle: force-draw at bbox center to preserve coverage at high poly counts.
        if ((maxX - minX) <= 2 && (maxY - minY) <= 2)
        {
            var px = (minX + maxX) >> 1;
            var py = (minY + maxY) >> 1;
            var z = (z0 + z1 + z2) / 3f;
            var idx = py * width + px;
            if (z > zBuffer[idx]) { zBuffer[idx] = z; pixels[idx] = color; }
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

# ============ ThreeDViewer.axaml.cs ============
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
        else if (change.Property == MinLambertProperty || change.Property == WireframeProperty)
            RequestRender();
        else if (change.Property == QualityProperty)
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
            // Drag: halve or quarter the resolution + supersample 1 for responsiveness.
            var divisor = isLow ? 4 : 2;
            var w = Math.Max(96, _renderWidth / divisor);
            var h = Math.Max(96, _renderHeight / divisor);
            return (w, h, 1);
        }
        else
        {
            // Idle: supersample 2 for High, 1 for Medium/Low.
            var ss = isHigh ? 2 : 1;
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
# Patch 0.4.5a5 - Fix shatter + Quality/LOD

**Iteration:** 0.4.5

## Root cause of shatter

At 1.5M polygons on a 256x256 preview, average triangle covers ~0.04 pixels.
Barycentric center-of-pixel test misses 96% of triangles -> holes/shards on surface.

## Fixes

1. Sub-pixel force-draw in RasterizeTriangle:
   - If bbox span is <=2x2 pixels, force-draw to bbox center pixel.
   - Every tiny triangle contributes -> no holes.
   - Cost: one z-test per triangle, cheaper than the skipped barycentric loop.

2. Supersample in SkiaPreviewRenderer:
   - IPreviewRenderer.Render gains supersample param (default 2).
   - Renders at supersample x width/height, downsamples by averaging.
   - Previews use SS=2 (256 becomes 512 internal), eliminating sandpaper.

3. ThreeDViewer Quality property (High/Medium/Low):
   - Drag detection: _isDragging set when movement > 0.5px.
   - Drag renders at reduced resolution (half for High/Medium, quarter for Low).
   - Idle renders at full resolution (SS=2 for High, SS=1 for Medium/Low).
   - Pointer release triggers crisp re-render.

4. ModelCardPageViewModel.RenderQuality (High/Medium/Low), persisted to Setting "Render.Quality".

5. ModelCardView: Quality ComboBox next to MinLambert slider.

## Expected behavior

- Previews: SS=2, ~800ms per model, no shatter, no sandpaper.
- Viewer High: idle SS=2 (smooth, ~800ms), drag half-size (50ms, 20fps).
- Viewer Medium: idle SS=1 (200ms, slight sandpaper), drag half (50ms).
- Viewer Low: idle SS=1 (200ms), drag quarter (12ms, 80fps).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Clear data/cache/previews before testing (RendererVersion unchanged).
- Previews no longer show broken polygons.
- Drag in viewer is responsive (no 800ms freezes).
- Quality ComboBox works, persists across restarts.
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $iPreviewPath   = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\IPreviewRenderer.cs'
    $rendererPath   = Join-Path $ProjectRoot 'src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs'
    $viewerPath     = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ThreeDViewer.axaml.cs'
    $vmPath         = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'
    $xamlPath       = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\ModelCardView.axaml'
    $enPath         = Join-Path $ProjectRoot 'lang\en.json'
    $ruPath         = Join-Path $ProjectRoot 'lang\ru.json'

    Backup-File $iPreviewPath
    Backup-File $rendererPath
    Backup-File $viewerPath
    Backup-File $vmPath
    Backup-File $xamlPath
    Backup-File $enPath
    Backup-File $ruPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    Write-Text -Path $iPreviewPath -Content $iPreviewCs
    Write-Log 'updated: IPreviewRenderer.cs (supersample param)'

    Write-Text -Path $rendererPath -Content $skiaRendererCs
    Write-Log 'updated: SkiaPreviewRenderer.cs (supersample + sub-pixel)'

    Write-Text -Path $viewerPath -Content $viewerCs
    Write-Log 'updated: ThreeDViewer.axaml.cs (Quality + drag detection)'

    # ============ ModelCardPageViewModel targeted edits ============
    $vm = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)

    $oldWire = @'
    private bool _wireframeMode;
    public bool WireframeMode
    {
        get => _wireframeMode;
        set { if (_wireframeMode != value) { _wireframeMode = value; Raise(); } }
    }
'@
    $newWire = @'
    private bool _wireframeMode;
    public bool WireframeMode
    {
        get => _wireframeMode;
        set { if (_wireframeMode != value) { _wireframeMode = value; Raise(); } }
    }

    public ObservableCollection<string> QualityChoices { get; } = new() { "High", "Medium", "Low" };

    private string _renderQuality = "High";
    public string RenderQuality
    {
        get => _renderQuality;
        set
        {
            if (_renderQuality == value) return;
            _renderQuality = value;
            Raise();
            _ = SaveSettingAsync("Render.Quality", value);
        }
    }

    public string LabelQuality => Loc("Card.View.Quality", "Quality");
'@
    $vmNorm = $vm -replace "`r`n", "`n"
    $oldNorm = $oldWire -replace "`r`n", "`n"
    if ($vmNorm.Contains($oldNorm)) {
        $vmNorm = $vmNorm.Replace($oldNorm, ($newWire -replace "`r`n", "`n"))
        $vm = $vmNorm -replace "(?<!`r)`n", "`r`n"
        Write-Log 'VM: added RenderQuality + QualityChoices + LabelQuality'
    } elseif ($vm -match 'RenderQuality') {
        Write-Log 'VM: RenderQuality already present, skipping.' 'WARN'
    } else {
        Write-Log 'VM: wireframe block not found - manual check needed.' 'WARN'
    }

    # Load quality from Setting in LoadAsync
    $oldLoadSetting = '            var raw = await AppServices.Settings.GetAsync("Render.MinLambert", ct);
            if (raw != null && float.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var f))
            {
                _minLambert = Math.Clamp(f, 0f, 1f);
                Raise(nameof(MinLambertValue));
            }'
    $newLoadSetting = $oldLoadSetting + '

            var rawQ = await AppServices.Settings.GetAsync("Render.Quality", ct);
            if (!string.IsNullOrEmpty(rawQ) && QualityChoices.Contains(rawQ))
            {
                _renderQuality = rawQ;
                Raise(nameof(RenderQuality));
            }'
    $vmNorm = $vm -replace "`r`n", "`n"
    $oldLoadNorm = $oldLoadSetting -replace "`r`n", "`n"
    if ($vmNorm.Contains($oldLoadNorm)) {
        $vmNorm = $vmNorm.Replace($oldLoadNorm, ($newLoadSetting -replace "`r`n", "`n"))
        $vm = $vmNorm -replace "(?<!`r)`n", "`r`n"
        Write-Log 'VM: LoadAsync loads Render.Quality from Setting'
    }

    # RefreshLocalized for LabelQuality
    $oldRefresh = '        Raise(nameof(LabelWireframe));'
    $newRefresh = $oldRefresh + "`r`n" + '        Raise(nameof(LabelQuality));'
    if ($vm.Contains($oldRefresh) -and ($vm -notmatch 'Raise\(nameof\(LabelQuality\)\)')) {
        $vm = $vm.Replace($oldRefresh, $newRefresh)
        Write-Log 'VM: RefreshLocalized includes LabelQuality'
    }

    [IO.File]::WriteAllText($vmPath, $vm, [Text.UTF8Encoding]::new($false))

    # ============ ModelCardView.axaml targeted edits ============
    $xaml = [IO.File]::ReadAllText($xamlPath, [Text.Encoding]::UTF8)

    # Add Quality ComboBox + TextBlock before Wireframe CheckBox
    $oldCheck = '<CheckBox Content="{Binding LabelWireframe}" IsChecked="{Binding WireframeMode}" VerticalAlignment="Center"/>'
    $newCheck = '<TextBlock Text="{Binding LabelQuality}" VerticalAlignment="Center" Margin="12,0,4,0"/>' + "`r`n" +
                '            <ComboBox ItemsSource="{Binding QualityChoices}" SelectedItem="{Binding RenderQuality}" Width="100" VerticalAlignment="Center"/>' + "`r`n" +
                '            ' + $oldCheck
    if ($xaml.Contains($oldCheck) -and ($xaml -notmatch 'RenderQuality')) {
        $xaml = $xaml.Replace($oldCheck, $newCheck)
        Write-Log 'XAML: added Quality ComboBox'
    }

    # Bind Quality in ThreeDViewer
    $oldViewer = '<views:ThreeDViewer Grid.Column="0"' + "`r`n" +
                 '                    MeshFilePath="{Binding MeshFilePath}"' + "`r`n" +
                 '                    MinLambert="{Binding MinLambertValue}"' + "`r`n" +
                 '                    Wireframe="{Binding WireframeMode}"' + "`r`n" +
                 '                    Yaw="{Binding ViewerYaw, Mode=TwoWay}"'
    $newViewer = '<views:ThreeDViewer Grid.Column="0"' + "`r`n" +
                 '                    MeshFilePath="{Binding MeshFilePath}"' + "`r`n" +
                 '                    MinLambert="{Binding MinLambertValue}"' + "`r`n" +
                 '                    Wireframe="{Binding WireframeMode}"' + "`r`n" +
                 '                    Quality="{Binding RenderQuality}"' + "`r`n" +
                 '                    Yaw="{Binding ViewerYaw, Mode=TwoWay}"'
    if ($xaml.Contains($oldViewer) -and ($xaml -notmatch 'Quality="\{Binding RenderQuality\}"')) {
        $xaml = $xaml.Replace($oldViewer, $newViewer)
        Write-Log 'XAML: bound Quality to ThreeDViewer'
    }

    [IO.File]::WriteAllText($xamlPath, $xaml, [Text.UTF8Encoding]::new($false))

    # ============ lang updates ============
    if (Test-Path $enPath) {
        $en = [IO.File]::ReadAllText($enPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not ($en.Card.View.PSObject.Properties.Name -contains 'Quality')) {
            $en.Card.View | Add-Member -NotePropertyName 'Quality' -NotePropertyValue 'Quality' -Force
        }
        $outEn = $en | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($enPath, $outEn, [Text.UTF8Encoding]::new($false))
        Write-Log 'lang/en.json: Card.View.Quality'
    }

    if (Test-Path $ruPath) {
        $ru = [IO.File]::ReadAllText($ruPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $ruQuality = -join ((0x041A,0x0430,0x0447,0x0435,0x0441,0x0442,0x0432,0x043E) | ForEach-Object { [char]$_ })
        if (-not ($ru.Card.View.PSObject.Properties.Name -contains 'Quality')) {
            $ru.Card.View | Add-Member -NotePropertyName 'Quality' -NotePropertyValue $ruQuality -Force
        }
        $outRu = $ru | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($ruPath, $outRu, [Text.UTF8Encoding]::new($false))
        Write-Log 'lang/ru.json: Card.View.Quality'
    }

    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.5a5\README.md'

    # Verify
    $verifyR = [IO.File]::ReadAllText($rendererPath, [Text.Encoding]::UTF8)
    if ($verifyR -match 'supersample') { Write-Log 'verify OK: renderer has supersample' }
    else { Write-Log 'verify FAIL: supersample missing' 'WARN' }
    if ($verifyR -match 'maxX - minX\) <= 2') { Write-Log 'verify OK: renderer has sub-pixel force-draw' }
    else { Write-Log 'verify FAIL: sub-pixel missing' 'WARN' }

    $verifyV = [IO.File]::ReadAllText($vmPath, [Text.Encoding]::UTF8)
    if ($verifyV -match 'RenderQuality') { Write-Log 'verify OK: VM has RenderQuality' }
    else { Write-Log 'verify FAIL: VM RenderQuality missing' 'WARN' }

    $verifyX = [IO.File]::ReadAllText($xamlPath, [Text.Encoding]::UTF8)
    if ($verifyX -match 'RenderQuality') { Write-Log 'verify OK: XAML has RenderQuality binding' }
    else { Write-Log 'verify FAIL: XAML binding missing' 'WARN' }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a5 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a5] - 2026-11-12`r`n`r`n### Added`r`n- Quality ComboBox (High/Medium/Low) in model card.`r`n- Drag detection in ThreeDViewer (reduced res during drag).`r`n`r`n### Fixed`r`n- Shatter/sandpaper on 1.5M poly models: sub-pixel force-draw + supersample in renderer.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a4\].*)$', "$entry`$1"
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
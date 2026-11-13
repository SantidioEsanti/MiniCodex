#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.3.0c — тема-зависимый фон 3D-вьюера + MinLambert + wireframe.
.DESCRIPTION
    RenderStyle (Core) + IPreviewRenderer.Render(+style) + SkiaPreviewRenderer (wireframe).
    ThreeDViewer подписан на смену темы, строит style из ActualThemeVariant + DataContext.
    MinLambert сохраняется в Setting (Render.MinLambert).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.3.0c'
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

# ============ Core/Services/RenderStyle.cs ============
$Files['src\MiniCodex.Core\Services\RenderStyle.cs'] = @'
namespace MiniCodex.Core.Services;

/// <summary>Параметры рендера. Цвета — в ARGB (0xAARRGGBB).</summary>
public record RenderStyle
{
    public uint BackgroundArgb { get; init; } = 0xFFE0E0E0;
    public uint ModelArgb { get; init; } = 0xFFFFFFFF;
    public float MinLambert { get; init; } = 0.4f;
    public bool Wireframe { get; init; }
}
'@

# ============ Core/Services/IPreviewRenderer.cs ============
$Files['src\MiniCodex.Core\Services\IPreviewRenderer.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IPreviewRenderer
{
    /// <summary>Рендер меша. style=null эквивалентно new RenderStyle() (светлый фон, белая модель, MinLambert=0.4).</summary>
    byte[] Render(MeshGeometry mesh, int width, int height,
        float yawDegrees, float pitchDegrees, float zoom = 1.0f, RenderStyle? style = null);
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
    public byte[] Render(MeshGeometry mesh, int width, int height,
        float yawDegrees, float pitchDegrees, float zoom = 1.0f, RenderStyle? style = null)
    {
        style ??= new RenderStyle();
        if (zoom < 0.1f) zoom = 0.1f;

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
        var fit = maxDim > 0 ? (MathF.Min(width, height) * 0.8f) / maxDim : 1f;
        var scale = fit * zoom;

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
        var bgPacked = PackPremul(bgR, bgG, bgB, bgA);
        for (int i = 0; i < pixels.Length; i++) pixels[i] = bgPacked;

        // wireframe: цвет контрастирует с фоном
        float bgLum = (0.299f * bgR + 0.587f * bgG + 0.114f * bgB) / 255f;
        uint wireColor = bgLum > 0.5f ? PackPremul(40, 40, 40) : PackPremul(220, 220, 220);

        var lightDir = Vector3.Normalize(new Vector3(-0.4f, 0.6f, 1f));

        for (int t = 0; t < mesh.Indices.Length; t += 3)
        {
            int i0 = mesh.Indices[t], i1 = mesh.Indices[t + 1], i2 = mesh.Indices[t + 2];
            var v0 = screen[i0]; var v1 = screen[i1]; var v2 = screen[i2];

            if (style.Wireframe)
            {
                DrawLine(pixels, zBuffer, width, height, v0, v1, depth[i0], depth[i1], wireColor);
                DrawLine(pixels, zBuffer, width, height, v1, v2, depth[i1], depth[i2], wireColor);
                DrawLine(pixels, zBuffer, width, height, v2, v0, depth[i2], depth[i0], wireColor);
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

# ============ App/AppServices.cs ============
$Files['src\MiniCodex.App\AppServices.cs'] = @'
using MiniCodex.App.Services;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using MiniCodex.Render.Loaders;
using MiniCodex.Render.Rendering;

namespace MiniCodex.App;

public static class AppServices
{
    public static SqliteConnectionFactory? Factory { get; private set; }
    public static IModelRepository? Models { get; private set; }
    public static IModelFileRepository? ModelFiles { get; private set; }
    public static IAssetRepository? Assets { get; private set; }
    public static ISettingRepository? Settings { get; private set; }
    public static ScannerService? Scanner { get; private set; }
    public static PreviewGenerator? PreviewGenerator { get; private set; }

    public static void Init(AppPaths paths)
    {
        Factory = new SqliteConnectionFactory(paths.LibraryDb);
        Models = new ModelRepository(Factory);
        ModelFiles = new ModelFileRepository(Factory);
        Assets = new AssetRepository(Factory);
        Settings = new SettingRepository(Factory);

        var meshLoader = new AssimpMeshLoader();
        Scanner = new ScannerService(meshLoader, Models, ModelFiles);

        var renderer = new SkiaPreviewRenderer();
        PreviewGenerator = new PreviewGenerator(renderer, meshLoader, paths.CacheDir);
    }
}
'@

# ============ App/ViewModels/ModelCardPageViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.App.ViewModels;

public enum ThreeDViewState { Loading, Loaded, FileNotChosen, ParseFailed, Error }
public enum SaveState { None, Saved, Error }

public class ModelCardPageViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private readonly IModelRepository _models;
    private readonly IModelFileRepository _files;
    private readonly Action _onBack;

    public Model Model { get; }

    // ---------- Info ----------
    private string _title = string.Empty;
    public string Title { get => _title; set { _title = value; Raise(); } }
    private string _author = string.Empty;
    public string Author { get => _author; set { _author = value; Raise(); } }
    private string _sourceUrl = string.Empty;
    public string SourceUrl { get => _sourceUrl; set { _sourceUrl = value; Raise(); } }
    private string _status = string.Empty;
    public string Status { get => _status; set { _status = value; Raise(); } }
    private string _difficulty = string.Empty;
    public string Difficulty { get => _difficulty; set { _difficulty = value; Raise(); } }
    private string _notes = string.Empty;
    public string Notes { get => _notes; set { _notes = value; Raise(); } }

    // ---------- Files ----------
    public ObservableCollection<ModelFileRowViewModel> FileRows { get; } = new();

    private string? _meshFilePath;
    public string? MeshFilePath { get => _meshFilePath; set { _meshFilePath = value; Raise(); } }

    // ---------- Tabs ----------
    private int _selectedTabIndex;
    public int SelectedTabIndex { get => _selectedTabIndex; set { _selectedTabIndex = value; Raise(); } }

    // ---------- 3D render params ----------
    private float _minLambert = 0.4f;
    public float MinLambertValue
    {
        get => _minLambert;
        set
        {
            if (Math.Abs(_minLambert - value) < 0.001f) return;
            _minLambert = value;
            Raise();
            _ = SaveSettingAsync("Render.MinLambert", value.ToString("F2", CultureInfo.InvariantCulture));
        }
    }

    private bool _wireframeMode;
    public bool WireframeMode
    {
        get => _wireframeMode;
        set { if (_wireframeMode != value) { _wireframeMode = value; Raise(); } }
    }

    // ---------- ThreeD state ----------
    private ThreeDViewState _threeDViewState = ThreeDViewState.FileNotChosen;
    public ThreeDViewState ThreeDViewState
    {
        get => _threeDViewState;
        set { _threeDViewState = value; Raise(); Raise(nameof(ThreeDStatusText)); Raise(nameof(ThreeDStatusVisible)); }
    }

    private string? _threeDErrorMessage;
    public string? ThreeDErrorMessage
    {
        get => _threeDErrorMessage;
        set { _threeDErrorMessage = value; Raise(); Raise(nameof(ThreeDStatusText)); }
    }

    public string ThreeDStatusText => ThreeDViewState switch
    {
        ThreeDViewState.Loading => Loc("Card.ThreeD.Loading", "Loading 3D…"),
        ThreeDViewState.FileNotChosen => Loc("Card.ThreeD.FileNotChosen", "No model file selected"),
        ThreeDViewState.ParseFailed => Loc("Card.ThreeD.ParseFailed", "Failed to parse model"),
        ThreeDViewState.Error => Loc("Card.ThreeD.ErrorPrefix", "Error: ") + (ThreeDErrorMessage ?? ""),
        _ => string.Empty,
    };
    public bool ThreeDStatusVisible => ThreeDViewState != ThreeDViewState.Loaded;

    // ---------- Save status ----------
    private SaveState _saveState = SaveState.None;
    public SaveState SaveState
    {
        get => _saveState;
        private set { _saveState = value; Raise(); Raise(nameof(SaveStatusText)); }
    }

    private string? _saveErrorMessage;
    public string? SaveErrorMessage
    {
        get => _saveErrorMessage;
        private set { _saveErrorMessage = value; Raise(); Raise(nameof(SaveStatusText)); }
    }

    public string SaveStatusText => SaveState switch
    {
        SaveState.Saved => Loc("Card.Status.Saved", "Saved"),
        SaveState.Error => Loc("Card.Status.ErrorPrefix", "Error: ") + (SaveErrorMessage ?? ""),
        _ => string.Empty,
    };

    // ---------- Localized labels ----------
    public string BackButtonText => Loc("Card.Actions.Back", "← Back");
    public string SaveButtonText => Loc("Card.Actions.Save", "Save");
    public string TabInfoHeader => Loc("Card.Tabs.Info", "Info");
    public string TabFilesHeader => Loc("Card.Tabs.Files", "Files");
    public string TabAssociationsHeader => Loc("Card.Tabs.Associations", "Associations");
    public string TabTagsHeader => Loc("Card.Tabs.Tags", "Tags");
    public string TabNotesHeader => Loc("Card.Tabs.Notes", "Notes");
    public string LabelTitle => Loc("Card.Fields.Title", "Title");
    public string LabelAuthor => Loc("Card.Fields.Author", "Author");
    public string LabelSourceUrl => Loc("Card.Fields.SourceUrl", "Source URL");
    public string LabelStatus => Loc("Card.Fields.Status", "Status");
    public string LabelDifficulty => Loc("Card.Fields.Difficulty", "Difficulty");
    public string LabelMinLambert => Loc("Card.View.MinLambert", "Shadow softness");
    public string LabelWireframe => Loc("Card.View.Wireframe", "Wireframe");
    public string AssociationsPlaceholder => Loc("Card.Placeholder.AssociationsSoon", "Associations — coming in 0.3.1");
    public string TagsPlaceholder => Loc("Card.Placeholder.TagsSoon", "Tags — coming in 0.3.2");

    public ICommand SaveCommand { get; }
    public ICommand GoBackCommand { get; }
    public ICommand SetPrimaryCommand { get; }

    public ModelCardPageViewModel(
        Model model,
        IModelRepository models,
        IModelFileRepository files,
        Action onBack)
    {
        Model = model;
        _models = models;
        _files = files;
        _onBack = onBack;

        _title = model.Title;
        _author = model.Author ?? string.Empty;
        _sourceUrl = model.SourceUrl ?? string.Empty;
        _status = model.Status ?? string.Empty;
        _difficulty = model.Difficulty?.ToString() ?? string.Empty;
        _notes = model.Notes ?? string.Empty;

        SaveCommand = new RelayCommand(async () => await SaveAsync());
        GoBackCommand = new RelayCommand(() => _onBack());
        SetPrimaryCommand = new RelayCommand(async p => await SetPrimaryAsync(p as ModelFileRowViewModel));
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        var files = await _files.GetByModelAsync(Model.Id, ct);
        FileRows.Clear();
        foreach (var f in files)
            FileRows.Add(new ModelFileRowViewModel(f, f.Id == Model.PrimaryModelFileId));

        var primary = files.FirstOrDefault(f => f.Id == Model.PrimaryModelFileId)
                      ?? files.FirstOrDefault();
        MeshFilePath = primary?.Path;

        if (AppServices.Settings != null)
        {
            var raw = await AppServices.Settings.GetAsync("Render.MinLambert", ct);
            if (raw != null && float.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var f))
            {
                _minLambert = Math.Clamp(f, 0f, 1f);
                Raise(nameof(MinLambertValue));
            }
        }
    }

    public void RefreshLocalized()
    {
        Raise(nameof(BackButtonText));
        Raise(nameof(SaveButtonText));
        Raise(nameof(TabInfoHeader));
        Raise(nameof(TabFilesHeader));
        Raise(nameof(TabAssociationsHeader));
        Raise(nameof(TabTagsHeader));
        Raise(nameof(TabNotesHeader));
        Raise(nameof(LabelTitle));
        Raise(nameof(LabelAuthor));
        Raise(nameof(LabelSourceUrl));
        Raise(nameof(LabelStatus));
        Raise(nameof(LabelDifficulty));
        Raise(nameof(LabelMinLambert));
        Raise(nameof(LabelWireframe));
        Raise(nameof(AssociationsPlaceholder));
        Raise(nameof(TagsPlaceholder));
        Raise(nameof(ThreeDStatusText));
        Raise(nameof(SaveStatusText));
    }

    private async Task SaveAsync()
    {
        try
        {
            Model.Title = string.IsNullOrWhiteSpace(Title) ? "Untitled" : Title;
            Model.Author = NullIfEmpty(Author);
            Model.SourceUrl = NullIfEmpty(SourceUrl);
            Model.Status = NullIfEmpty(Status);
            Model.Difficulty = int.TryParse(Difficulty, out var d) ? Math.Clamp(d, 1, 5) : null;
            Model.Notes = NullIfEmpty(Notes);
            await _models.UpsertAsync(Model);
            SaveErrorMessage = null;
            SaveState = SaveState.Saved;
        }
        catch (Exception ex)
        {
            SaveErrorMessage = ex.Message;
            SaveState = SaveState.Error;
        }
    }

    private async Task SetPrimaryAsync(ModelFileRowViewModel? row)
    {
        if (row == null) return;
        foreach (var r in FileRows) r.IsPrimary = ReferenceEquals(r, row);
        Model.PrimaryModelFileId = row.File.Id;
        await _models.UpsertAsync(Model);
        MeshFilePath = row.File.Path;
    }

    private static async Task SaveSettingAsync(string key, string value)
    {
        if (AppServices.Settings == null) return;
        try { await AppServices.Settings.SetAsync(key, value); } catch { }
    }

    private static string? NullIfEmpty(string s) => string.IsNullOrWhiteSpace(s) ? null : s;
    private static string Loc(string key, string fallback) => App.Loc?.Get(key) ?? fallback;
}
'@

# ============ App/Views/ThreeDViewer.axaml ============
$Files['src\MiniCodex.App\Views\ThreeDViewer.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             x:Class="MiniCodex.App.Views.ThreeDViewer">
    <Grid>
        <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}" CornerRadius="4">
            <Image x:Name="PreviewHost" Stretch="Uniform"/>
        </Border>
        <TextBlock Text="{Binding ThreeDStatusText}"
                   IsVisible="{Binding ThreeDStatusVisible}"
                   HorizontalAlignment="Center" VerticalAlignment="Center"
                   Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                   FontSize="14"/>
    </Grid>
</UserControl>
'@

# ============ App/Views/ThreeDViewer.axaml.cs ============
$Files['src\MiniCodex.App\Views\ThreeDViewer.axaml.cs'] = @'
using Avalonia;
using Avalonia.Controls;
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
        else if (change.Property == MinLambertProperty || change.Property == WireframeProperty)
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

    private async Task RenderLoop()
    {
        try
        {
            while (true)
            {
                _renderPending = false;
                var yaw = _yaw; var pitch = _pitch; var zoom = _zoom;
                var w = _renderWidth; var h = _renderHeight;
                var geo = _geometry;
                var style = BuildStyle();
                if (geo == null) break;

                byte[]? png = null;
                try { png = await Task.Run(() => _renderer.Render(geo, w, h, yaw, pitch, zoom, style)); }
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
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        if (_lastPointer == null || _geometry == null) return;
        var pos = e.GetPosition(this);
        var dx = (float)(pos.X - _lastPointer.Value.X);
        var dy = (float)(pos.Y - _lastPointer.Value.Y);
        _lastPointer = pos;
        _yaw += dx * 0.5f;
        _pitch = Math.Clamp(_pitch + dy * 0.5f, -89f, 89f);
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

# ============ App/Views/ModelCardView.axaml ============
$Files['src\MiniCodex.App\Views\ModelCardView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.ModelCardView"
             x:DataType="vm:ModelCardPageViewModel">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Orientation="Horizontal" Spacing="8" Margin="8">
            <Button Content="{Binding BackButtonText}" Command="{Binding GoBackCommand}"/>
            <Button Content="{Binding SaveButtonText}" Command="{Binding SaveCommand}"/>
            <TextBlock Text="{Binding SaveStatusText}" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
            <TextBlock Text="{Binding LabelMinLambert}" VerticalAlignment="Center" Margin="12,0,4,0"/>
            <Slider Value="{Binding MinLambertValue}" Minimum="0" Maximum="1" Width="120" VerticalAlignment="Center"/>
            <CheckBox Content="{Binding LabelWireframe}" IsChecked="{Binding WireframeMode}" VerticalAlignment="Center"/>
        </StackPanel>

        <Grid Grid.Row="1" ColumnDefinitions="480,*" Margin="8,0,8,8">
            <views:ThreeDViewer Grid.Column="0"
                                MeshFilePath="{Binding MeshFilePath}"
                                MinLambert="{Binding MinLambertValue}"
                                Wireframe="{Binding WireframeMode}"
                                Margin="0,0,8,0"/>

            <TabControl Grid.Column="1" SelectedIndex="{Binding SelectedTabIndex}">
                <TabItem Header="{Binding TabInfoHeader}">
                    <ScrollViewer>
                        <StackPanel Margin="8" Spacing="6">
                            <TextBlock Text="{Binding LabelTitle}"/>
                            <TextBox Text="{Binding Title}"/>
                            <TextBlock Text="{Binding LabelAuthor}"/>
                            <TextBox Text="{Binding Author}"/>
                            <TextBlock Text="{Binding LabelSourceUrl}"/>
                            <TextBox Text="{Binding SourceUrl}"/>
                            <TextBlock Text="{Binding LabelStatus}"/>
                            <TextBox Text="{Binding Status}"/>
                            <TextBlock Text="{Binding LabelDifficulty}"/>
                            <TextBox Text="{Binding Difficulty}"/>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <TabItem Header="{Binding TabFilesHeader}">
                    <ListBox ItemsSource="{Binding FileRows}">
                        <ListBox.ItemTemplate>
                            <DataTemplate>
                                <Grid ColumnDefinitions="Auto,*,Auto,Auto,Auto" Margin="4">
                                    <RadioButton Grid.Column="0"
                                                 IsChecked="{Binding IsPrimary, Mode=OneWay}"
                                                 Command="{Binding $parent[ListBox].((vm:ModelCardPageViewModel)DataContext).SetPrimaryCommand}"
                                                 CommandParameter="{Binding}"
                                                 GroupName="PrimaryFile"/>
                                    <TextBlock Grid.Column="1" Text="{Binding DisplayName}"
                                               VerticalAlignment="Center" Margin="6,0"/>
                                    <TextBlock Grid.Column="2" Text="{Binding RoleText}"
                                               VerticalAlignment="Center" Width="80"/>
                                    <TextBlock Grid.Column="3" Text="{Binding SizeText}"
                                               VerticalAlignment="Center" Width="80"/>
                                    <TextBlock Grid.Column="4" Text="{Binding PolygonsText}"
                                               VerticalAlignment="Center" Width="80"/>
                                </Grid>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
                </TabItem>

                <TabItem Header="{Binding TabAssociationsHeader}">
                    <TextBlock Text="{Binding AssociationsPlaceholder}"
                               HorizontalAlignment="Center" VerticalAlignment="Center"
                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                </TabItem>

                <TabItem Header="{Binding TabTagsHeader}">
                    <TextBlock Text="{Binding TagsPlaceholder}"
                               HorizontalAlignment="Center" VerticalAlignment="Center"
                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                </TabItem>

                <TabItem Header="{Binding TabNotesHeader}">
                    <TextBox Text="{Binding Notes}" AcceptsReturn="True"
                             TextWrapping="Wrap" VerticalContentAlignment="Top"
                             Margin="8" MinHeight="200"/>
                </TabItem>
            </TabControl>
        </Grid>
    </Grid>
</UserControl>
'@

# ============ Tests/Services/PreviewGeneratorTests.cs (stub signature) ============
$Files['src\MiniCodex.Tests\Services\PreviewGeneratorTests.cs'] = @'
using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using Xunit;

namespace MiniCodex.Tests.Services;

public class StubRenderer : IPreviewRenderer
{
    public int CallCount { get; private set; }
    public byte[] Render(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees, float zoom = 1.0f, RenderStyle? style = null)
    {
        CallCount++;
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
        Assert.Equal(callsAfterFirst, _renderer.CallCount);
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
        Assert.True(_renderer.CallCount > callsAfterFirst);
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

# ============ lang/en.json — добавляем Card.View.* ============
# (используем точечную вставку через замену блока "Card": { ... } — но проще перезаписать целиком)
# Уже было: Card.* из 0.3.0b. Добавляем Card.View.MinLambert, Card.View.Wireframe.

# ============ lang/ru.json ============

# ============ README ============
$Files['patches\0.3.0c\README.md'] = @'
# Патч 0.3.0c — тема-зависимый фон 3D-вьюера + MinLambert + wireframe

**Итерация:** 0.3 · **Статус:** реализован

## Что делает

### Тема-зависимый фон (основное)
- `RenderStyle` (Core) — record с `BackgroundArgb`, `ModelArgb`, `MinLambert`, `Wireframe`.
- `IPreviewRenderer.Render` — параметр `RenderStyle? style = null` (null = дефолт = светлый фон, белая модель, MinLambert=0.4).
- `SkiaPreviewRenderer` — использует стиль: фон и цвет модели из ARGB, `MinLambert` из стиля.
- `ThreeDViewer` подписан на `Application.Current.ActualThemeVariantChanged`; при смене темы строит style с `BackgroundArgb` = `#2D2D2D` (dark) или `#E0E0E0` (light) и перерисовывает.
- `ThreeDViewer.axaml` — Border под Image тоже `DynamicResource`, чтобы не было белых краёв.

### MinLambert
- Слайдер `0..1` в верхней панели карточки.
- Сохраняется в `Setting` (ключ `Render.MinLambert`), восстанавливается при открытии любой карточки.
- Влияет только на **живой** 3D-вьюер, кэш превью библиотеки не трогает (там всегда `0.4`).

### Wireframe
- Чекбокс `Wireframe`.
- `SkiaPreviewRenderer`: `DrawLine` (Bresenham с z-buffer) вместо заливки треугольников.
- Цвет рёбер адаптивный: `#282828` на светлом фоне, `#DCDCDC` на тёмном.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.0c\patch_0.3.0c.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24/24.
- Смена темы (auto→dark→light) при открытой карточке → фон 3D-вьюера меняется.
- Слайдер «Мягкость теней»: при 0 — контрастные тени, при 1 — плоский белый силуэт.
- Чекбокс «Каркас» → модель показана рёбрами.
- Значение слайдера сохраняется между перезапусками.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.Core\Services\IPreviewRenderer.cs',
        'src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs',
        'src\MiniCodex.App\AppServices.cs',
        'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs',
        'src\MiniCodex.App\Views\ThreeDViewer.axaml',
        'src\MiniCodex.App\Views\ThreeDViewer.axaml.cs',
        'src\MiniCodex.App\Views\ModelCardView.axaml',
        'src\MiniCodex.Tests\Services\PreviewGeneratorTests.cs',
        'lang\en.json',
        'lang\ru.json',
        'CHANGELOG.md'
    )
    foreach ($rel in $toBackup) { Backup-File (Join-Path $ProjectRoot $rel) }

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # --- lang/*.json: добавляем Card.View.* через точечную вставку ---
    foreach ($langFile in @('lang\en.json', 'lang\ru.json')) {
        $path = Join-Path $ProjectRoot $langFile
        if (-not (Test-Path $path)) { continue }
        $content = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        if ($content -notmatch '"MinLambert"') {
            $isEn = $langFile -match 'en'
            $minL = if ($isEn) { 'Shadow softness' } else { 'Мягкость теней' }
            $wireL = if ($isEn) { 'Wireframe' } else { 'Каркас' }
            # Вставляем Card.View.* внутрь "Card": { ... } — сразу после "Actions": { ... },
            $viewBlock = '    "View": {' + "`r`n" + "      " + '"MinLambert": "' + $minL + '",' + "`r`n" + "      " + '"Wireframe": "' + $wireL + '"' + "`r`n" + '    },' + "`r`n"
            # Находим "Tabs" внутри Card и вставляем View перед ним
            $content = $content -replace '(\s+)("Tabs":\s*\{)', "`r`n$viewBlock`$1`$2"
            [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
            Write-Log "updated: $langFile (Card.View.MinLambert, Card.View.Wireframe)"
        } else {
            Write-Log "$langFile : Card.View уже есть, пропускаю." 'WARN'
        }
    }

    # CHANGELOG
    $marker = '<!-- patch 0.3.0c applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Added`n- 0.3.0c: фон 3D-вьюера следует за темой (RenderStyle + Application.ActualThemeVariantChanged).`n- 0.3.0c: слайдер MinLambert на карточке (сохраняется в Setting).`n- 0.3.0c: wireframe-toggle с адаптивным цветом рёбер.`n"
            $cl = $cl -replace '(?m)^(## \[0\.3\.0b\.1\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.3.0c.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}
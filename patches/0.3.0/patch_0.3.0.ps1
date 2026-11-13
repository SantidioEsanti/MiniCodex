#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.3.0 — Экран «Карточка модели» с 3D-вьюером и вкладками.
.DESCRIPTION
    Навигация Library <-> Card, ThreeDViewer (drag/scroll, coalescing),
    вкладки Info/Files/Associations/Tags/Notes, сохранение в БД.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.3.0'
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

# ============ Core/Services/IPreviewRenderer.cs ============
$Files['src\MiniCodex.Core\Services\IPreviewRenderer.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IPreviewRenderer
{
    /// <summary>
    /// Рендер меша. zoom=1.0 — модель занимает 80% меньшей стороны; zoom>1 приближает.
    /// </summary>
    byte[] Render(MeshGeometry mesh, int width, int height,
        float yawDegrees, float pitchDegrees, float zoom = 1.0f);
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
    private static readonly SKColor Background = new(0xE0, 0xE0, 0xE0);
    private static readonly SKColor BaseColor = new(0xFF, 0xFF, 0xFF);
    private const float MinLambert = 0.40f;

    public byte[] Render(MeshGeometry mesh, int width, int height,
        float yawDegrees, float pitchDegrees, float zoom = 1.0f)
    {
        if (zoom < 0.1f) zoom = 0.1f;

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
        var bgPacked = PackPremul(Background.Red, Background.Green, Background.Blue);
        for (int i = 0; i < pixels.Length; i++) pixels[i] = bgPacked;

        var lightDir = Vector3.Normalize(new Vector3(-0.4f, 0.6f, 1f));

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
}
'@

# ============ App/ViewModels/RelayCommand.cs ============
$Files['src\MiniCodex.App\ViewModels\RelayCommand.cs'] = @'
using System.Windows.Input;

namespace MiniCodex.App.ViewModels;

public class RelayCommand : ICommand
{
    private readonly Action<object?> _execute;
    private readonly Func<object?, bool>? _canExecute;

    public RelayCommand(Action execute, Func<bool>? canExecute = null)
        : this(_ => execute(), canExecute == null ? null : _ => canExecute()) { }

    public RelayCommand(Action<object?> execute, Func<object?, bool>? canExecute = null)
    {
        _execute = execute;
        _canExecute = canExecute;
    }

    public event EventHandler? CanExecuteChanged;
    public bool CanExecute(object? parameter) => _canExecute?.Invoke(parameter) ?? true;
    public void Execute(object? parameter) => _execute(parameter);
    public void RaiseCanExecuteChanged() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}
'@

# ============ App/ViewModels/ModelFileRowViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\ModelFileRowViewModel.cs'] = @'
using System.ComponentModel;
using System.Runtime.CompilerServices;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class ModelFileRowViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public ModelFile File { get; }

    public string DisplayName => Path.GetFileName(File.Path);
    public string RoleText => string.IsNullOrEmpty(File.FileRole) ? "-" : File.FileRole!;
    public string SizeText => File.FileSizeBytes.HasValue ? FormatSize(File.FileSizeBytes.Value) : "-";
    public string PolygonsText => File.PolygonCount?.ToString("N0") ?? "-";

    private bool _isPrimary;
    public bool IsPrimary
    {
        get => _isPrimary;
        set { if (_isPrimary != value) { _isPrimary = value; Raise(); } }
    }

    public ModelFileRowViewModel(ModelFile file, bool isPrimary)
    {
        File = file;
        _isPrimary = isPrimary;
    }

    private static string FormatSize(long bytes)
    {
        string[] units = { "B", "KB", "MB", "GB" };
        double v = bytes; int u = 0;
        while (v >= 1024 && u < units.Length - 1) { v /= 1024; u++; }
        return $"{v:F1} {units[u]}";
    }
}
'@

# ============ App/ViewModels/ModelCardPageViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.App.ViewModels;

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

    // ---------- Status ----------
    private string _saveStatus = string.Empty;
    public string SaveStatus { get => _saveStatus; set { _saveStatus = value; Raise(); } }

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
            SaveStatus = "Сохранено";
        }
        catch (Exception ex)
        {
            SaveStatus = "Ошибка: " + ex.Message;
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

    private static string? NullIfEmpty(string s) => string.IsNullOrWhiteSpace(s) ? null : s;
}
'@

# ============ App/ViewModels/ModelCardViewModel.cs — OpenCommand ============
$Files['src\MiniCodex.App\ViewModels\ModelCardViewModel.cs'] = @'
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public class ModelCardViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public Model Model { get; }
    public string Title => Model.Title;
    public string StatusText => Model.Status ?? "-";

    public ICommand OpenCommand { get; }

    private Bitmap? _preview;
    public Bitmap? PreviewImage
    {
        get => _preview;
        private set { _preview = value; Raise(); }
    }

    public ModelCardViewModel(Model model, Action<Model> onOpen)
    {
        Model = model;
        OpenCommand = new RelayCommand(() => onOpen(Model));
    }

    public async Task LoadDetailsAsync(
        IModelFileRepository files,
        PreviewGenerator previews,
        CancellationToken ct = default)
    {
        try
        {
            if (Model.PrimaryModelFileId == null) return;
            var allFiles = await files.GetByModelAsync(Model.Id, ct);
            var primary = allFiles.FirstOrDefault(f => f.Id == Model.PrimaryModelFileId);
            if (primary == null) return;

            var results = await previews.EnsurePreviewsAsync(
                Model.Id, primary.Path, Model.UpdatedAt, ct);
            var firstPath = results.FirstOrDefault(p => p != null);
            if (firstPath == null) return;

            await Dispatcher.UIThread.InvokeAsync(() =>
            {
                try
                {
                    using var stream = File.OpenRead(firstPath);
                    PreviewImage = new Bitmap(stream);
                }
                catch { }
            });
        }
        catch { }
    }
}
'@

# ============ App/ViewModels/LibraryViewModel.cs — OpenCardRequested ============
$Files['src\MiniCodex.App\ViewModels\LibraryViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public class LibraryViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public event EventHandler<Model>? OpenCardRequested;

    private readonly IModelRepository? _models;
    private readonly IModelFileRepository? _files;
    private readonly ScannerService? _scanner;
    private readonly PreviewGenerator? _previews;

    public ObservableCollection<ModelCardViewModel> Cards { get; } = new();

    private bool _isBusy;
    public bool IsBusy
    {
        get => _isBusy;
        private set { _isBusy = value; Raise(); Raise(nameof(IsEmpty)); }
    }

    public bool IsEmpty => !IsBusy && Cards.Count == 0;

    public string ScanButtonText => App.Loc?.Get("Library.ScanButton") ?? "Scan folder";
    public string EmptyStateText => App.Loc?.Get("Library.Empty") ?? "No models yet.";

    private enum StatusState { None, Loading, ModelCount, Scanning }
    private StatusState _statusState = StatusState.None;
    private int _statusCount;
    private string _statusDetail = string.Empty;

    public string StatusText => _statusState switch
    {
        StatusState.Loading => App.Loc?.Get("Library.Loading") ?? "Loading…",
        StatusState.ModelCount => string.Format(App.Loc?.Get("Library.ModelsCount") ?? "Models: {0}", _statusCount),
        StatusState.Scanning => _statusDetail,
        _ => string.Empty,
    };

    private void SetStatus(StatusState state, int count = 0, string detail = "")
    {
        _statusState = state; _statusCount = count; _statusDetail = detail;
        Raise(nameof(StatusText));
    }

    public LibraryViewModel(
        IModelRepository? models,
        IModelFileRepository? files,
        ScannerService? scanner,
        PreviewGenerator? previews)
    {
        _models = models; _files = files; _scanner = scanner; _previews = previews;
    }

    public void RefreshLocalized()
    {
        Raise(nameof(ScanButtonText));
        Raise(nameof(EmptyStateText));
        if (_statusState == StatusState.ModelCount) SetStatus(StatusState.ModelCount, _statusCount);
        else Raise(nameof(StatusText));
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        if (_models == null || _files == null || _previews == null)
        {
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.ServicesNotInitialized") ?? "Services not initialized.");
            return;
        }
        IsBusy = true;
        try
        {
            SetStatus(StatusState.Loading);
            var all = await _models.GetAllAsync(ct);
            Cards.Clear();
            foreach (var m in all)
            {
                var card = new ModelCardViewModel(m, OnOpenRequested);
                Cards.Add(card);
                _ = Task.Run(() => card.LoadDetailsAsync(_files, _previews, ct), ct);
            }
            SetStatus(Cards.Count == 0 ? StatusState.None : StatusState.ModelCount, Cards.Count);
            Raise(nameof(IsEmpty));
        }
        finally { IsBusy = false; }
    }

    public async Task ScanAsync(IEnumerable<string> folders, CancellationToken ct = default)
    {
        if (_scanner == null || _models == null || _files == null || _previews == null) return;
        IsBusy = true;
        SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Scanning") ?? "Scanning…");
        try
        {
            var progress = new Progress<ScanProgress>(p =>
            {
                var fmt = App.Loc?.Get("Library.ScanningProgress") ?? "Scanning: {0}/{1} (+{2}, ~{3}, ={4})";
                SetStatus(StatusState.Scanning, 0, string.Format(fmt, p.ProcessedFiles, p.TotalFiles, p.Added, p.Updated, p.Skipped));
            });
            await _scanner.ScanAsync(folders, progress, ct);
        }
        finally { await LoadAsync(ct); }
    }

    private void OnOpenRequested(Model m) => OpenCardRequested?.Invoke(this, m);
}
'@

# ============ App/ViewModels/MainWindowViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\MainWindowViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class MainWindowViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public ObservableCollection<string> Languages { get; } = new() { "en", "ru" };
    public ObservableCollection<string> Themes { get; } = new() { "light", "dark", "auto" };

    private string _lang = App.Loc?.Current ?? "en";
    public string CurrentLanguage
    {
        get => _lang;
        set
        {
            if (!Set(ref _lang, value)) return;
            App.Loc.SetLanguage(value);
            Raise(nameof(Title));
            Library.RefreshLocalized();
        }
    }

    private string _theme = "auto";
    public string CurrentTheme
    {
        get => _theme;
        set { if (Set(ref _theme, value)) App.Theme.Apply(value); }
    }

    public string Title => App.Loc.Get("App.Name");

    public LibraryViewModel Library { get; }

    private object? _currentPage;
    public object? CurrentPage
    {
        get => _currentPage;
        private set { _currentPage = value; Raise(); }
    }

    public MainWindowViewModel()
    {
        Library = new LibraryViewModel(
            AppServices.Models,
            AppServices.ModelFiles,
            AppServices.Scanner,
            AppServices.PreviewGenerator);
        Library.OpenCardRequested += OnOpenCard;
        CurrentPage = Library;
    }

    private void OnOpenCard(object? sender, Model model)
    {
        if (AppServices.Models == null || AppServices.ModelFiles == null) return;
        var page = new ModelCardPageViewModel(model, AppServices.Models, AppServices.ModelFiles,
            onBack: () => CurrentPage = Library);
        CurrentPage = page;
        _ = page.LoadAsync();
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (Equals(field, value)) return false;
        field = value;
        Raise(name);
        return true;
    }
}
'@

# ============ App/Views/ThreeDViewer.axaml ============
$Files['src\MiniCodex.App\Views\ThreeDViewer.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             x:Class="MiniCodex.App.Views.ThreeDViewer">
    <Grid>
        <Border Background="#E0E0E0" CornerRadius="4">
            <Image x:Name="PreviewHost" Stretch="Uniform"/>
        </Border>
        <TextBlock x:Name="StatusLabel" Text="Загрузка 3D…"
                   HorizontalAlignment="Center" VerticalAlignment="Center"
                   Foreground="#666" FontSize="14" IsVisible="False"/>
    </Grid>
</UserControl>
'@

# ============ App/Views/ThreeDViewer.axaml.cs ============
$Files['src\MiniCodex.App\Views\ThreeDViewer.axaml.cs'] = @'
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using MiniCodex.Render.Loaders;
using MiniCodex.Render.Rendering;
using MiniCodex.Core.Models;

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

    public string? MeshFilePath
    {
        get => GetValue(MeshFilePathProperty);
        set => SetValue(MeshFilePathProperty, value);
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
    }

    protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
    {
        base.OnPropertyChanged(change);
        if (change.Property == MeshFilePathProperty)
            _ = LoadGeometryAsync(change.GetNewValue<string?>());
    }

    private async Task LoadGeometryAsync(string? path)
    {
        _geometry = null;
        PreviewHost.Source = null;

        if (string.IsNullOrEmpty(path))
        {
            StatusLabel.Text = "Файл модели не выбран";
            StatusLabel.IsVisible = true;
            return;
        }

        StatusLabel.Text = "Загрузка 3D…";
        StatusLabel.IsVisible = true;
        try
        {
            var geo = await Task.Run(() => _loader.LoadGeometry(path));
            if (geo == null)
            {
                StatusLabel.Text = "Не удалось разобрать модель";
                return;
            }
            _geometry = geo;
            StatusLabel.IsVisible = false;
            RequestRender();
        }
        catch (Exception ex)
        {
            StatusLabel.Text = "Ошибка: " + ex.Message;
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
                if (geo == null) break;

                byte[]? png = null;
                try { png = await Task.Run(() => _renderer.Render(geo, w, h, yaw, pitch, zoom)); }
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
        _yaw -= dx * 0.5f;
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
             x:Class="MiniCodex.App.Views.ModelCardView">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Orientation="Horizontal" Spacing="8" Margin="8">
            <Button Content="← Назад" Command="{Binding GoBackCommand}"/>
            <Button Content="Сохранить" Command="{Binding SaveCommand}"/>
            <TextBlock Text="{Binding SaveStatus}" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
        </StackPanel>

        <Grid Grid.Row="1" ColumnDefinitions="480,*" Margin="8,0,8,8">
            <views:ThreeDViewer Grid.Column="0" MeshFilePath="{Binding MeshFilePath}" Margin="0,0,8,0"/>

            <TabControl Grid.Column="1" SelectedIndex="{Binding SelectedTabIndex}">
                <TabItem Header="Инфо">
                    <ScrollViewer>
                        <StackPanel Margin="8" Spacing="6">
                            <TextBlock Text="Название"/>
                            <TextBox Text="{Binding Title}"/>
                            <TextBlock Text="Автор"/>
                            <TextBox Text="{Binding Author}"/>
                            <TextBlock Text="Источник (URL)"/>
                            <TextBox Text="{Binding SourceUrl}"/>
                            <TextBlock Text="Статус (planned / printed / painted)"/>
                            <TextBox Text="{Binding Status}"/>
                            <TextBlock Text="Сложность покраса (1–5)"/>
                            <TextBox Text="{Binding Difficulty}"/>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <TabItem Header="Файлы">
                    <Grid RowDefinitions="*,Auto">
                        <ListBox ItemsSource="{Binding FileRows}">
                            <ListBox.ItemTemplate>
                                <DataTemplate>
                                    <Grid ColumnDefinitions="Auto,*,Auto,Auto,Auto" Margin="4">
                                        <RadioButton Grid.Column="0"
                                                     IsChecked="{Binding IsPrimary, Mode=OneWay}"
                                                     Command="{Binding $parent[UserControl].((vm:ModelCardPageViewModel)DataContext).SetPrimaryCommand}"
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
                    </Grid>
                </TabItem>

                <TabItem Header="Ассоциации">
                    <TextBlock Text="Ассоциации — в патче 0.3.1"
                               HorizontalAlignment="Center" VerticalAlignment="Center"
                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                </TabItem>

                <TabItem Header="Теги">
                    <TextBlock Text="Теги — в патче 0.3.2"
                               HorizontalAlignment="Center" VerticalAlignment="Center"
                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                </TabItem>

                <TabItem Header="Заметки">
                    <TextBox Text="{Binding Notes}" AcceptsReturn="True"
                             TextWrapping="Wrap" VerticalContentAlignment="Top"
                             Margin="8" MinHeight="200"/>
                </TabItem>
            </TabControl>
        </Grid>
    </Grid>
</UserControl>
'@

# ============ App/Views/ModelCardView.axaml.cs ============
$Files['src\MiniCodex.App\Views\ModelCardView.axaml.cs'] = @'
using Avalonia.Controls;

namespace MiniCodex.App.Views;

public partial class ModelCardView : UserControl
{
    public ModelCardView() => InitializeComponent();
}
'@

# ============ App/Views/MainWindow.axaml ============
$Files['src\MiniCodex.App\Views\MainWindow.axaml'] = @'
<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Class="MiniCodex.App.Views.MainWindow"
        Title="{Binding Title}" Icon="/Assets/icon.ico"
        Width="1100" Height="750">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Orientation="Horizontal" Spacing="8" Margin="8">
            <ComboBox ItemsSource="{Binding Languages}" SelectedItem="{Binding CurrentLanguage}" Width="120"/>
            <ComboBox ItemsSource="{Binding Themes}" SelectedItem="{Binding CurrentTheme}" Width="120"/>
        </StackPanel>
        <ContentControl Grid.Row="1" Content="{Binding CurrentPage}"/>
    </Grid>
</Window>
'@

# ============ App/Views/LibraryView.axaml — карточки как кнопки ============
$Files['src\MiniCodex.App\Views\LibraryView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             x:Class="MiniCodex.App.Views.LibraryView">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="8" Spacing="8">
            <Button Content="{Binding ScanButtonText}" Click="OnScanClick"/>
            <TextBlock Text="{Binding StatusText}" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
            <ProgressBar IsIndeterminate="True" IsVisible="{Binding IsBusy}"
                         Width="120" VerticalAlignment="Center"/>
        </StackPanel>

        <ScrollViewer Grid.Row="1">
            <ItemsControl ItemsSource="{Binding Cards}" Margin="4">
                <ItemsControl.ItemsPanel>
                    <ItemsPanelTemplate>
                        <WrapPanel Orientation="Horizontal"/>
                    </ItemsPanelTemplate>
                </ItemsControl.ItemsPanel>
                <ItemsControl.ItemTemplate>
                    <DataTemplate>
                        <Button Command="{Binding OpenCommand}"
                                Background="Transparent"
                                BorderBrush="Transparent"
                                Padding="0">
                            <Border Width="220" Height="260" Margin="6"
                                    BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
                                    BorderThickness="1" CornerRadius="6" Padding="6">
                                <Grid RowDefinitions="180,*,Auto">
                                    <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                            CornerRadius="4">
                                        <Image Source="{Binding PreviewImage}" Stretch="Uniform" Margin="4"/>
                                    </Border>
                                    <TextBlock Grid.Row="1" Text="{Binding Title}"
                                               FontWeight="Bold" TextTrimming="CharacterEllipsis"
                                               Margin="0,6,0,0"/>
                                    <TextBlock Grid.Row="2" FontSize="11"
                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                               Text="{Binding StatusText}"/>
                                </Grid>
                            </Border>
                        </Button>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </ScrollViewer>

        <TextBlock Grid.Row="1" Text="{Binding EmptyStateText}"
                   HorizontalAlignment="Center" VerticalAlignment="Center"
                   Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                   IsVisible="{Binding IsEmpty}"/>
    </Grid>
</UserControl>
'@

# ============ App/App.axaml — DataTemplates ============
$Files['src\MiniCodex.App\App.axaml'] = @'
<Application xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             x:Class="MiniCodex.App.App"
             RequestedThemeVariant="Default">
    <Application.DataTemplates>
        <DataTemplate DataType="vm:LibraryViewModel">
            <views:LibraryView/>
        </DataTemplate>
        <DataTemplate DataType="vm:ModelCardPageViewModel">
            <views:ModelCardView/>
        </DataTemplate>
    </Application.DataTemplates>
    <Application.Styles>
        <FluentTheme />
    </Application.Styles>
</Application>
'@

# ============ README патча ============
$Files['patches\0.3.0\README.md'] = @'
# Патч 0.3.0 — Экран «Карточка модели»

**Итерация:** 0.3 · **Статус:** реализован

## Что делает

- `ThreeDViewer` — UserControl с drag-вращением (yaw/pitch) и колесом-зумом.
  Geometry загружается в фоне, рендер коалесцируется (skip frames при busy).
- `ModelCardView` — карточка: слева 3D-вьюер, справа 5 вкладок.
- Вкладки: Инфо (редактируемая), Файлы (radio = primary), Ассоциации/Tags (заглушки → 0.3.1/0.3.2), Заметки (редактируемая).
- Навигация: клик на карточке в библиотеке → открывается карточка. «← Назад» → возврат.
- `RelayCommand` — минимальный ICommand.
- DataTemplates в `App.axaml` — маппинг ViewModel → View.
- `IPreviewRenderer.Render` — добавлен optional zoom.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.0\patch_0.3.0.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24 теста, 0 сбоев (5-аргументные вызовы Render используют zoom=1.0 по умолчанию).
- Клик на карточке → открывается карточка модели.
- 3D: drag мышью вращает, колесо зумит.
- Info: правка + «Сохранить» → запись в БД.
- Файлы: radio-выбор primary → переключение 3D и запись в БД.
- «← Назад» → библиотека.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.Core\Services\IPreviewRenderer.cs',
        'src\MiniCodex.Render\Rendering\SkiaPreviewRenderer.cs',
        'src\MiniCodex.App\ViewModels\ModelCardViewModel.cs',
        'src\MiniCodex.App\ViewModels\LibraryViewModel.cs',
        'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs',
        'src\MiniCodex.App\Views\MainWindow.axaml',
        'src\MiniCodex.App\Views\LibraryView.axaml',
        'src\MiniCodex.App\App.axaml',
        'CHANGELOG.md'
    )
    foreach ($rel in $toBackup) { Backup-File (Join-Path $ProjectRoot $rel) }

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # CHANGELOG
    $marker = '<!-- patch 0.3.0 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n## [0.3.0] - 2026-11-10`n`n### Added`n- Экран «Карточка модели» с 3D-вьюером и 5 вкладками.`n- ThreeDViewer (drag + scroll).`n- Навигация Library <-> Card.`n- RelayCommand.`n- Zoom в IPreviewRenderer.Render.`n"
            $cl = $cl -replace '(?m)^(## \[0\.2\.3c\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.3.0.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}
#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.3.1 — Ассоциации (drag-and-drop, авто-привязка, Hybrid).
.DESCRIPTION
    IAssetService + AssetService + IAssetThumbnailGenerator (Skia).
    ModelCardPageViewModel: AssetRows, фильтр, ImportAssetsAsync, AutoLinkAsync, RemoveAsync.
    ModelCardView: вкладка Ассоциации с drag/drop, миниатюрами, ComboBox типа/фильтра.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.3.1'
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

# ============ Core/Services/IAssetThumbnailGenerator.cs ============
$Files['src\MiniCodex.Core\Services\IAssetThumbnailGenerator.cs'] = @'
namespace MiniCodex.Core.Services;

public interface IAssetThumbnailGenerator
{
    /// <summary>
    /// Возвращает PNG-байты миниатюры (квадрат maxSize×maxSize) для sourcePath.
    /// Если файл не изображение — генерирует заглушку с буквой типа.
    /// </summary>
    byte[] Generate(string sourcePath, string assetType, int maxSize);
}
'@

# ============ Core/Services/IAssetService.cs ============
$Files['src\MiniCodex.Core\Services\IAssetService.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IAssetService
{
    /// <summary>
    /// Копирует файл в assets/{modelId}/{8hex}_{origName}{ext}, создаёт запись Asset.
    /// </summary>
    Task<Asset> ImportAsync(string modelId, string sourcePath, string assetType, CancellationToken ct = default);

    /// <summary>
    /// Удаляет запись Asset из БД. Файл на диске НЕ удаляется (решение MVP).
    /// </summary>
    Task RemoveFromCardAsync(string assetId, CancellationToken ct = default);

    /// <summary>
    /// Ищет рядом с primary-файлом модели файлы {basename}_*.{png,jpg,jpeg,webp,pdf}
    /// и импортирует ещё не привязанные как reference.
    /// </summary>
    Task<IReadOnlyList<Asset>> AutoLinkAsync(string modelId, CancellationToken ct = default);

    /// <summary>
    /// Возвращает путь к миниатюре (создаёт при необходимости). null — если не удалось.
    /// </summary>
    Task<string?> EnsureThumbnailAsync(Asset asset, CancellationToken ct = default);
}
'@

# ============ Core/Services/AssetService.cs ============
$Files['src\MiniCodex.Core\Services\AssetService.cs'] = @'
using System.Security.Cryptography;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class AssetService : IAssetService
{
    private static readonly string[] ImageExtensions = { ".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp" };
    private static readonly string[] AutoLinkExtensions = { ".png", ".jpg", ".jpeg", ".webp", ".pdf" };

    private readonly IAssetRepository _assets;
    private readonly IModelFileRepository _files;
    private readonly IAssetThumbnailGenerator _thumbs;
    private readonly string _assetsRoot;
    private readonly string _thumbsRoot;

    public AssetService(
        IAssetRepository assets,
        IModelFileRepository files,
        IAssetThumbnailGenerator thumbs,
        string assetsRoot,
        string thumbsRoot)
    {
        _assets = assets;
        _files = files;
        _thumbs = thumbs;
        _assetsRoot = assetsRoot;
        _thumbsRoot = thumbsRoot;
    }

    public async Task<Asset> ImportAsync(string modelId, string sourcePath, string assetType, CancellationToken ct = default)
    {
        if (!File.Exists(sourcePath))
            throw new FileNotFoundException("Asset source not found", sourcePath);

        var modelDir = Path.Combine(_assetsRoot, modelId);
        Directory.CreateDirectory(modelDir);

        var origName = Path.GetFileName(sourcePath);
        var ext = Path.GetExtension(sourcePath);
        var baseName = Path.GetFileNameWithoutExtension(sourcePath);
        var hex = Convert.ToHexString(RandomNumberGenerator.GetBytes(4)).ToLowerInvariant();
        var destPath = Path.Combine(modelDir, $"{hex}_{baseName}{ext}");

        File.Copy(sourcePath, destPath, overwrite: false);

        var asset = new Asset
        {
            ModelId = modelId,
            AssetType = assetType,
            AbsolutePath = destPath,
            StorageMode = "hybrid",
            SortOrder = (int)(DateTime.UtcNow.Ticks % int.MaxValue),
        };
        await _assets.UpsertAsync(asset, ct);
        return asset;
    }

    public async Task RemoveFromCardAsync(string assetId, CancellationToken ct = default)
    {
        await _assets.DeleteAsync(assetId, ct);
        // Файл на диске НЕ удаляем — решение MVP (см. docs/ROADMAP.md, раздел 0).
    }

    public async Task<IReadOnlyList<Asset>> AutoLinkAsync(string modelId, CancellationToken ct = default)
    {
        var files = await _files.GetByModelAsync(modelId, ct);
        var primary = files.FirstOrDefault(f => f.FileRole == "main") ?? files.FirstOrDefault();
        if (primary == null) return Array.Empty<Asset>();

        var dir = Path.GetDirectoryName(primary.Path);
        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return Array.Empty<Asset>();

        var baseName = Path.GetFileNameWithoutExtension(primary.Path);
        var existing = await _assets.GetByModelAsync(modelId, ct);
        var existingSourceNames = new HashSet<string>(
            existing.Select(a => Path.GetFileName(a.AbsolutePath)).Where(n => n != null)!.Cast<string>(),
            StringComparer.OrdinalIgnoreCase);

        var imported = new List<Asset>();
        foreach (var candidate in Directory.EnumerateFiles(dir, baseName + "_*"))
        {
            var ext = Path.GetExtension(candidate).ToLowerInvariant();
            if (!AutoLinkExtensions.Contains(ext)) continue;

            // Пропускаем, если файл уже привязан (по basename после 8hex_)
            var candidateName = Path.GetFileNameWithoutExtension(candidate);
            if (existingSourceNames.Any(n => n.EndsWith("_" + candidateName + ext, StringComparison.OrdinalIgnoreCase)))
                continue;

            try
            {
                var asset = await ImportAsync(modelId, candidate, "reference", ct);
                imported.Add(asset);
            }
            catch { /* пропускаем битые */ }
        }
        return imported;
    }

    public async Task<string?> EnsureThumbnailAsync(Asset asset, CancellationToken ct = default)
    {
        Directory.CreateDirectory(_thumbsRoot);
        var thumbPath = Path.Combine(_thumbsRoot, asset.Id + ".png");
        if (File.Exists(thumbPath)) return thumbPath;

        try
        {
            var type = asset.AssetType ?? "reference";
            var bytes = await Task.Run(() => _thumbs.Generate(asset.AbsolutePath, type, 128), ct);
            await File.WriteAllBytesAsync(thumbPath, bytes, ct);
            return thumbPath;
        }
        catch { return null; }
    }
}
'@

# ============ Render/Rendering/SkiaThumbnailGenerator.cs ============
$Files['src\MiniCodex.Render\Rendering\SkiaThumbnailGenerator.cs'] = @'
using MiniCodex.Core.Services;
using SkiaSharp;

namespace MiniCodex.Render.Rendering;

public class SkiaThumbnailGenerator : IAssetThumbnailGenerator
{
    public byte[] Generate(string sourcePath, string assetType, int maxSize)
    {
        try
        {
            var ext = Path.GetExtension(sourcePath).ToLowerInvariant();
            var isImage = ext == ".png" || ext == ".jpg" || ext == ".jpeg" ||
                          ext == ".webp" || ext == ".gif" || ext == ".bmp";
            if (isImage)
            {
                using var src = SKBitmap.Decode(sourcePath);
                if (src != null)
                    return ResizeToPng(src, maxSize);
            }
        }
        catch { /* fall through to placeholder */ }
        return Placeholder(assetType, maxSize);
    }

    private static byte[] ResizeToPng(SKBitmap src, int maxSize)
    {
        var side = Math.Max(src.Width, src.Height);
        var scale = side > maxSize ? (float)maxSize / side : 1f;
        var w = Math.Max(1, (int)(src.Width * scale));
        var h = Math.Max(1, (int)(src.Height * scale));

        using var resized = new SKBitmap(w, h, SKColorType.Rgba8888, SKAlphaType.Premul);
        using (var canvas = new SKCanvas(resized))
        using (var paint = new SKPaint { FilterQuality = SKFilterQuality.High })
        {
            canvas.Clear(SKColors.Transparent);
            canvas.DrawBitmap(src, SKRect.Create(w, h), paint);
        }
        using var img = SKImage.FromBitmap(resized);
        using var data = img.Encode(SKEncodedImageFormat.Png, 90);
        return data.ToArray();
    }

    private static byte[] Placeholder(string assetType, int maxSize)
    {
        using var bitmap = new SKBitmap(maxSize, maxSize, SKColorType.Rgba8888, SKAlphaPremul);
        using (var canvas = new SKCanvas(bitmap))
        using (var bg = new SKPaint { Color = new SKColor(0x44, 0x44, 0x44), IsAntialias = true })
        using (var fg = new SKPaint { Color = SKColors.White, IsAntialias = true, TextSize = maxSize * 0.4f, TextAlign = SKTextAlign.Center, Typeface = SKTypeface.FromFamilyName("Segoe UI", SKFontStyle.Bold) })
        {
            canvas.Clear(new SKColor(0x44, 0x44, 0x44));
            var letter = assetType switch
            {
                "render" => "R",
                "photo" => "P",
                "document" => "D",
                "profile" => "Pr",
                _ => "Re",
            };
            var metrics = fg.FontMetrics;
            var y = maxSize * 0.5f - (metrics.Ascent + metrics.Descent) * 0.5f;
            canvas.DrawText(letter, maxSize * 0.5f, y, fg);
        }
        using var img = SKImage.FromBitmap(bitmap);
        using var data = img.Encode(SKEncodedImageFormat.Png, 90);
        return data.ToArray();
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
    public static IAssetService? AssetService { get; private set; }
    public static AppPaths? Paths { get; private set; }

    public static void Init(AppPaths paths)
    {
        Paths = paths;
        Factory = new SqliteConnectionFactory(paths.LibraryDb);
        Models = new ModelRepository(Factory);
        ModelFiles = new ModelFileRepository(Factory);
        Assets = new AssetRepository(Factory);
        Settings = new SettingRepository(Factory);

        var meshLoader = new AssimpMeshLoader();
        Scanner = new ScannerService(meshLoader, Models, ModelFiles);

        var renderer = new SkiaPreviewRenderer();
        PreviewGenerator = new PreviewGenerator(renderer, meshLoader, paths.CacheDir);

        var thumbs = new SkiaThumbnailGenerator();
        var thumbsRoot = Path.Combine(paths.DataDir, "cache", "asset-thumbs");
        AssetService = new AssetService(Assets, ModelFiles, thumbs, paths.AssetsDir, thumbsRoot);
    }
}
'@

# ============ App/ViewModels/AssetRowViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\AssetRowViewModel.cs'] = @'
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Media.Imaging;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class AssetRowViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public Asset Asset { get; }
    public string DisplayName => Path.GetFileName(Asset.AbsolutePath);
    public string AssetTypeText => Asset.AssetType ?? "-";

    private Bitmap? _thumbnail;
    public Bitmap? Thumbnail
    {
        get => _thumbnail;
        private set { _thumbnail = value; Raise(); }
    }

    public ICommand RemoveCommand { get; }

    public AssetRowViewModel(Asset asset, Func<AssetRowViewModel, Task> onRemove)
    {
        Asset = asset;
        RemoveCommand = new RelayCommand(async () => await onRemove(this));
    }

    public void SetThumbnail(Bitmap? bitmap) => Thumbnail = bitmap;
}
'@

# ============ App/ViewModels/ModelCardPageViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Media.Imaging;
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

    // ---------- 3D state ----------
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

    // ---------- Save ----------
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

    public string AddFileButtonText => Loc("Card.Assoc.AddFile", "Add file");
    public string AutoLinkButtonText => Loc("Card.Assoc.AutoLink", "Auto-link");
    public string DropHintText => Loc("Card.Assoc.DropHint", "Drop files here to attach");
    public string RemoveAssetText => Loc("Card.Assoc.Remove", "Remove");
    public string AssetStatusText { get; private set; } = string.Empty;

    // ---------- Associations ----------
    public ObservableCollection<AssetRowViewModel> AssetRows { get; } = new();
    public ObservableCollection<AssetRowViewModel> FilteredAssets { get; } = new();

    public ObservableCollection<string> AssetTypeChoices { get; } = new()
    { "reference", "render", "photo", "document", "profile" };

    private string _selectedAssetType = "reference";
    public string SelectedAssetType { get => _selectedAssetType; set { _selectedAssetType = value; Raise(); } }

    public ObservableCollection<string> AssetFilterChoices { get; } = new()
    { "all", "reference", "render", "photo", "document", "profile" };

    private string _selectedAssetFilter = "all";
    public string SelectedAssetFilter
    {
        get => _selectedAssetFilter;
        set { _selectedAssetFilter = value; Raise(); RebuildFilteredAssets(); }
    }

    public ICommand SaveCommand { get; }
    public ICommand GoBackCommand { get; }
    public ICommand SetPrimaryCommand { get; }
    public ICommand AutoLinkCommand { get; }

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
        AutoLinkCommand = new RelayCommand(async () => await AutoLinkAsync());
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        var files = await _files.GetByModelAsync(Model.Id, ct);
        FileRows.Clear();
        foreach (var f in files)
            FileRows.Add(new ModelFileRowViewModel(f, f.Id == Model.PrimaryModelFileId));

        var primary = files.FirstOrDefault(f => f.Id == Model.PrimaryModelFileId) ?? files.FirstOrDefault();
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

        await ReloadAssetsAsync(ct);
    }

    private async Task ReloadAssetsAsync(CancellationToken ct)
    {
        if (AppServices.Assets == null || AppServices.AssetService == null) return;
        var assets = await AppServices.Assets.GetByModelAsync(Model.Id, ct);
        AssetRows.Clear();
        foreach (var a in assets)
        {
            var row = new AssetRowViewModel(a, OnRemoveAssetAsync);
            AssetRows.Add(row);
            _ = LoadThumbnailAsync(row, ct);
        }
        RebuildFilteredAssets();
    }

    private async Task LoadThumbnailAsync(AssetRowViewModel row, CancellationToken ct)
    {
        if (AppServices.AssetService == null) return;
        try
        {
            var path = await AppServices.AssetService.EnsureThumbnailAsync(row.Asset, ct);
            if (path == null) return;
            await Avalonia.Threading.Dispatcher.UIThread.InvokeAsync(() =>
            {
                try
                {
                    using var stream = File.OpenRead(path);
                    row.SetThumbnail(new Bitmap(stream));
                }
                catch { }
            });
        }
        catch { }
    }

    private void RebuildFilteredAssets()
    {
        FilteredAssets.Clear();
        foreach (var r in AssetRows)
        {
            if (_selectedAssetFilter == "all" || r.Asset.AssetType == _selectedAssetFilter)
                FilteredAssets.Add(r);
        }
    }

    private void SetAssetStatus(string text)
    {
        AssetStatusText = text;
        Raise(nameof(AssetStatusText));
    }

    public async Task ImportAssetsAsync(IEnumerable<string> sourcePaths)
    {
        if (AppServices.AssetService == null) return;
        var count = 0;
        foreach (var p in sourcePaths)
        {
            try
            {
                await AppServices.AssetService.ImportAsync(Model.Id, p, SelectedAssetType);
                count++;
            }
            catch { }
        }
        SetAssetStatus(string.Format(Loc("Card.Assoc.Imported", "Imported: {0}"), count));
        await ReloadAssetsAsync(CancellationToken.None);
    }

    private async Task AutoLinkAsync()
    {
        if (AppServices.AssetService == null) return;
        SetAssetStatus(Loc("Card.Assoc.AutoLinkRunning", "Searching…"));
        try
        {
            var found = await AppServices.AssetService.AutoLinkAsync(Model.Id);
            SetAssetStatus(string.Format(Loc("Card.Assoc.AutoLinkResult", "Linked: {0}"), found.Count));
            await ReloadAssetsAsync(CancellationToken.None);
        }
        catch (Exception ex) { SetAssetStatus("Error: " + ex.Message); }
    }

    private async Task OnRemoveAssetAsync(AssetRowViewModel row)
    {
        if (AppServices.AssetService == null) return;
        await AppServices.AssetService.RemoveFromCardAsync(row.Asset.Id);
        AssetRows.Remove(row);
        RebuildFilteredAssets();
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
        Raise(nameof(AddFileButtonText));
        Raise(nameof(AutoLinkButtonText));
        Raise(nameof(DropHintText));
        Raise(nameof(RemoveAssetText));
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
                    <Grid RowDefinitions="Auto,Auto,*">
                        <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="6" Margin="6">
                            <ComboBox ItemsSource="{Binding AssetTypeChoices}"
                                      SelectedItem="{Binding SelectedAssetType}" Width="110"/>
                            <Button Content="{Binding AddFileButtonText}" Click="OnAddFileClick"/>
                            <Button Content="{Binding AutoLinkButtonText}" Command="{Binding AutoLinkCommand}"/>
                            <ComboBox ItemsSource="{Binding AssetFilterChoices}"
                                      SelectedItem="{Binding SelectedAssetFilter}" Width="110" Margin="12,0,0,0"/>
                            <TextBlock Text="{Binding AssetStatusText}" VerticalAlignment="Center" Margin="8,0,0,0"
                                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                        </StackPanel>

                        <Border Grid.Row="1" Margin="6" Padding="8" MinHeight="60"
                                BorderThickness="1" BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
                                CornerRadius="6"
                                Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                Name="DropZone" DragDrop.AllowDrop="True">
                            <TextBlock Text="{Binding DropHintText}" HorizontalAlignment="Center" VerticalAlignment="Center"
                                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                        </Border>

                        <ScrollViewer Grid.Row="2">
                            <ItemsControl ItemsSource="{Binding FilteredAssets}" Margin="6">
                                <ItemsControl.ItemsPanel>
                                    <ItemsPanelTemplate>
                                        <WrapPanel Orientation="Horizontal"/>
                                    </ItemsPanelTemplate>
                                </ItemsControl.ItemsPanel>
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <Border Width="150" Margin="4" Padding="6"
                                                BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
                                                BorderThickness="1" CornerRadius="4">
                                            <Grid RowDefinitions="100,*,Auto">
                                                <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}" CornerRadius="2">
                                                    <Image Source="{Binding Thumbnail}" Stretch="Uniform" Margin="2"/>
                                                </Border>
                                                <TextBlock Grid.Row="1" Text="{Binding DisplayName}" FontSize="11"
                                                           TextTrimming="CharacterEllipsis" Margin="0,4,0,0"/>
                                                <Grid Grid.Row="2" ColumnDefinitions="*,Auto" Margin="0,4,0,0">
                                                    <TextBlock Text="{Binding AssetTypeText}" FontSize="10"
                                                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                                               VerticalAlignment="Center"/>
                                                    <Button Grid.Column="1" Content="×"
                                                            Command="{Binding RemoveCommand}"
                                                            Padding="6,0" MinWidth="24"
                                                            ToolTip.Tip="{Binding $parent[ItemsControl].((vm:ModelCardPageViewModel)DataContext).RemoveAssetText}"/>
                                                </Grid>
                                            </Grid>
                                        </Border>
                                    </DataTemplate>
                                </ItemsControl.ItemTemplate>
                            </ItemsControl>
                        </ScrollViewer>
                    </Grid>
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

# ============ App/Views/ModelCardView.axaml.cs ============
$Files['src\MiniCodex.App\Views\ModelCardView.axaml.cs'] = @'
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class ModelCardView : UserControl
{
    public ModelCardView()
    {
        InitializeComponent();
        DragDrop.SetAllowDrop(this, true);
        AddHandler(DragDrop.DropEvent, OnDrop);
        AddHandler(DragDrop.DragOverEvent, OnDragOver);
    }

    private void OnDragOver(object? sender, DragEventArgs e)
    {
        e.DragEffects = e.Data.Contains(DataFormats.Files)
            ? DragDropEffects.Copy
            : DragDropEffects.None;
    }

    private async void OnDrop(object? sender, DragEventArgs e)
    {
        if (DataContext is not ModelCardPageViewModel vm) return;
        if (!e.Data.Contains(DataFormats.Files)) return;

        var files = e.Data.GetFiles();
        if (files == null) return;

        var paths = files
            .Select(f => f.TryGetLocalPath())
            .Where(p => !string.IsNullOrEmpty(p))
            .Cast<string>()
            .ToList();
        if (paths.Count == 0) return;

        await vm.ImportAssetsAsync(paths);
        e.Handled = true;
    }

    private async void OnAddFileClick(object? sender, RoutedEventArgs e)
    {
        if (DataContext is not ModelCardPageViewModel vm) return;
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is null) return;

        var files = await top.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Add associations",
            AllowMultiple = true,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("Images") { Patterns = new[] { "*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp" } },
                new FilePickerFileType("Documents") { Patterns = new[] { "*.pdf" } },
                new FilePickerFileType("All files") { Patterns = new[] { "*" } },
            }
        });
        if (files.Count == 0) return;

        var paths = files
            .Select(f => f.TryGetLocalPath())
            .Where(p => !string.IsNullOrEmpty(p))
            .Cast<string>()
            .ToList();
        if (paths.Count == 0) return;

        await vm.ImportAssetsAsync(paths);
    }
}
'@

# ============ Tests/Services/AssetServiceTests.cs ============
$Files['src\MiniCodex.Tests\Services\AssetServiceTests.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Services;

public class StubThumbnailGenerator : IAssetThumbnailGenerator
{
    public byte[] Generate(string sourcePath, string assetType, int maxSize)
        => new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
}

public class AssetServiceTests : IDisposable
{
    private readonly string _dbPath;
    private readonly string _tempRoot;
    private readonly string _assetsRoot;
    private readonly string _thumbsRoot;
    private readonly SqliteConnectionFactory _factory;
    private readonly AssetService _service;
    private readonly IModelRepository _models;
    private readonly IModelFileRepository _files;
    private readonly IAssetRepository _assets;

    public AssetServiceTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        _tempRoot = Path.Combine(Path.GetTempPath(), $"minicodex_assoc_{Guid.NewGuid()}");
        _assetsRoot = Path.Combine(_tempRoot, "assets");
        _thumbsRoot = Path.Combine(_tempRoot, "thumbs");
        Directory.CreateDirectory(_tempRoot);
        Directory.CreateDirectory(_assetsRoot);
        Directory.CreateDirectory(_thumbsRoot);
        DatabaseInitializer.InitializeAsync(_dbPath).GetAwaiter().GetResult();
        _factory = new SqliteConnectionFactory(_dbPath);
        _models = new ModelRepository(_factory);
        _files = new ModelFileRepository(_factory);
        _assets = new AssetRepository(_factory);
        _service = new AssetService(_assets, _files, new StubThumbnailGenerator(), _assetsRoot, _thumbsRoot);
    }

    public void Dispose()
    {
        try { File.Delete(_dbPath); } catch { }
        try { Directory.Delete(_tempRoot, true); } catch { }
    }

    [Fact]
    public async Task Import_CopiesFileAndCreatesRecord()
    {
        var model = new Model { Title = "M" };
        await _models.UpsertAsync(model);

        var src = Path.Combine(_tempRoot, "photo.png");
        File.WriteAllBytes(src, new byte[] { 1, 2, 3 });

        var asset = await _service.ImportAsync(model.Id, src, "photo");

        Assert.NotNull(asset);
        Assert.True(File.Exists(asset.AbsolutePath));
        Assert.StartsWith(Path.Combine(_assetsRoot, model.Id), asset.AbsolutePath);
        Assert.Equal("photo", asset.AssetType);
        Assert.Equal("hybrid", asset.StorageMode);

        var fromDb = await _assets.GetAsync(asset.Id);
        Assert.NotNull(fromDb);
    }

    [Fact]
    public async Task RemoveFromCard_DeletesRecordButKeepsFile()
    {
        var model = new Model { Title = "M" };
        await _models.UpsertAsync(model);

        var src = Path.Combine(_tempRoot, "photo.png");
        File.WriteAllBytes(src, new byte[] { 1, 2, 3 });
        var asset = await _service.ImportAsync(model.Id, src, "photo");

        var fileOnDisk = asset.AbsolutePath;
        Assert.True(File.Exists(fileOnDisk));

        await _service.RemoveFromCardAsync(asset.Id);

        Assert.Null(await _assets.GetAsync(asset.Id));
        Assert.True(File.Exists(fileOnDisk)); // ключевое: файл остаётся на диске
    }

    [Fact]
    public async Task AutoLink_FindsSiblingFiles_AndImports()
    {
        var modelDir = Path.Combine(_tempRoot, "model_dir");
        Directory.CreateDirectory(modelDir);
        var stl = Path.Combine(modelDir, "hero_001.stl");
        File.WriteAllBytes(stl, new byte[] { 0 });

        var model = new Model { Title = "hero_001" };
        await _models.UpsertAsync(model);
        var modelFile = new ModelFile
        {
            ModelId = model.Id,
            Path = stl,
            FileRole = "main",
            FileSizeBytes = 1,
        };
        await _files.UpsertAsync(modelFile);
        model.PrimaryModelFileId = modelFile.Id;
        await _models.UpsertAsync(model);

        File.WriteAllBytes(Path.Combine(modelDir, "hero_001_ref.png"), new byte[] { 1 });
        File.WriteAllBytes(Path.Combine(modelDir, "hero_001_render.jpg"), new byte[] { 2 });
        File.WriteAllBytes(Path.Combine(modelDir, "other_thing.png"), new byte[] { 3 });

        var found = await _service.AutoLinkAsync(model.Id);

        Assert.Equal(2, found.Count);
        var all = await _assets.GetByModelAsync(model.Id);
        Assert.Equal(2, all.Count);
        Assert.All(all, a => Assert.Equal("reference", a.AssetType));
        Assert.All(all, a => Assert.True(File.Exists(a.AbsolutePath)));
    }

    [Fact]
    public async Task EnsureThumbnail_CreatesPngFile()
    {
        var model = new Model { Title = "M" };
        await _models.UpsertAsync(model);

        var src = Path.Combine(_tempRoot, "photo.png");
        File.WriteAllBytes(src, new byte[] { 0x89, 0x50, 0x4E, 0x47 });
        var asset = await _service.ImportAsync(model.Id, src, "photo");

        var thumbPath = await _service.EnsureThumbnailAsync(asset);

        Assert.NotNull(thumbPath);
        Assert.True(File.Exists(thumbPath));
        Assert.EndsWith(".png", thumbPath);
    }
}
'@

# ============ lang updates: Card.Assoc.* ============
# Отдельно точечной вставкой внутрь Card
$langEnPatch = @'

  "Assoc": {
    "AddFile": "Add file",
    "AutoLink": "Auto-link",
    "AutoLinkRunning": "Searching…",
    "AutoLinkResult": "Linked: {0}",
    "Imported": "Imported: {0}",
    "DropHint": "Drop files here to attach",
    "Remove": "Remove"
  },
'@
$langRuPatch = @'

  "Assoc": {
    "AddFile": "Добавить файл",
    "AutoLink": "Авто-привязка",
    "AutoLinkRunning": "Поиск…",
    "AutoLinkResult": "Привязано: {0}",
    "Imported": "Импортировано: {0}",
    "DropHint": "Перетащите файлы сюда",
    "Remove": "Убрать"
  },
'@

# ============ README ============
$Files['patches\0.3.1\README.md'] = @'
# Патч 0.3.1 — Ассоциации (drag-and-drop, авто-привязка, Hybrid)

**Итерация:** 0.3 · **Статус:** реализован

## Что делает

- `IAssetService` / `AssetService` (Core):
  - `ImportAsync` — копирование файла в `data/assets/{modelId}/{8hex}_{origName}{ext}` + запись Asset
  - `RemoveFromCardAsync` — удаление записи из БД; **файл на диске остаётся** (MVP)
  - `AutoLinkAsync` — поиск рядом с primary `{basename}_*.{png,jpg,jpeg,webp,pdf}`, импорт как reference
  - `EnsureThumbnailAsync` — миниатюра в `data/cache/asset-thumbs/{assetId}.png`
- `IAssetThumbnailGenerator` (Core) + `SkiaThumbnailGenerator` (Render): ресайз изображений / заглушка с буквой типа.
- UI карточки, вкладка «Ассоциации»:
  - Drop-зона (drag-and-drop файлов), file picker «Add file»
  - ComboBox выбора типа (reference/render/photo/document/profile)
  - ComboBox фильтра по типу (all + 5 типов)
  - Галерея 150×150: миниатюра, имя, тип, кнопка «×» (Убрать из карточки)
  - Кнопка «Авто-привязка» — сразу импортирует найденные
- `AppServices.AssetService` — инициализация.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.1\patch_0.3.1.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 28 тестов (24 + 4 новых), все зелёные.
- Drag-and-drop PNG/JPG/PDF в карточку → ассоциация с миниатюрой.
- «Добавить файл» → file picker → импорт.
- «Авто-привязка» → находит {basename}_*.png рядом с primary.
- «Убрать» → запись из БД удаляется, **файл в data/assets/{modelId}/ остаётся**.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.App\AppServices.cs',
        'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs',
        'src\MiniCodex.App\Views\ModelCardView.axaml',
        'src\MiniCodex.App\Views\ModelCardView.axaml.cs',
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

    # --- lang/*.json: добавить "Assoc": { ... } внутрь "Card": { ... } ---
    foreach ($pair in @(@('lang\en.json', $langEnPatch, 'en'), @('lang\ru.json', $langRuPatch, 'ru'))) {
        $langPath = Join-Path $ProjectRoot $pair[0]
        if (-not (Test-Path $langPath)) { continue }
        $content = [IO.File]::ReadAllText($langPath, [Text.Encoding]::UTF8)
        if ($content -notmatch '"Assoc"\s*:') {
            # Вставляем после "Actions": { ... }, внутри Card. Ищем "Tabs": { в Card и вставляем перед ним.
            # Более простой путь: ищем "Card": { и вставляем "Assoc": {...} сразу после открывающей скобки Card.
            $content = $content -replace '("Card"\s*:\s*\{)', ("`$1" + $pair[1].TrimStart("`n").Insert(0, "`r`n"))
            [IO.File]::WriteAllText($langPath, $content, [Text.UTF8Encoding]::new($false))
            Write-Log "updated: $($pair[0]) (Card.Assoc.*)"
        } else {
            Write-Log "$($pair[0]) : Card.Assoc уже есть, пропускаю." 'WARN'
        }
    }

    # CHANGELOG
    $marker = '<!-- patch 0.3.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n## [0.3.1] - 2026-11-10`n`n### Added`n- Ассоциации: drag-and-drop, file picker, авто-привязка.`n- Hybrid-хранение: data/assets/{modelId}/.`n- Миниатюры ассоциаций (SkiaSharp, asset-thumbs).`n- Фильтр по типу.`n- 4 новых теста.`n"
            $cl = $cl -replace '(?m)^(## \[0\.3\.0c\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.3.1.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}
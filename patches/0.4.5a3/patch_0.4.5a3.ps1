#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a3 - Fix Assimp OOM: single preview at a time, load geometry once per model, GC after each model.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a3'
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

# ============ PreviewGenerator.cs (load once, render 4x, GC after) ============
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
    private const string RendererVersion = "0.2.3c";

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
                            var png = _renderer.Render(geometry, _options.Width, _options.Height, yaw, pitch);
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
            // Force GC to release native Assimp scene memory held by managed wrapper.
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

# ============ LibraryViewModel.cs (SemaphoreSlim(1) on previews) ============
$libVmCs = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public class LibraryViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? FocusSearchRequested;
    public event EventHandler<Model>? OpenCardRequested;
    public event EventHandler<(Model model, int tabIndex)>? OpenCardWithTabRequested;

    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private readonly IModelRepository? _models;
    private readonly IModelFileRepository? _files;
    private readonly ScannerService? _scanner;
    private readonly PreviewGenerator? _previews;
    private readonly ITagService? _tagService;
    private readonly IIntegrationService? _integration;

    // Serialize preview generation to avoid simultaneous Assimp native allocations (OOM).
    private readonly SemaphoreSlim _previewSemaphore = new SemaphoreSlim(1, 1);

    public ObservableCollection<ModelCardViewModel> Cards { get; } = new();
    public ObservableCollection<TagWithUsage> Tags { get; } = new();

    private bool _hasSlicer;
    private bool _hasEditor;

    private bool _isBusy;
    public bool IsBusy
    {
        get => _isBusy;
        private set { _isBusy = value; Raise(); Raise(nameof(IsEmpty)); }
    }

    public bool IsEmpty => !IsBusy && Cards.Count == 0;

    private bool _suppressTagReload;

    private TagWithUsage? _selectedTag;
    public TagWithUsage? SelectedTag
    {
        get => _selectedTag;
        set
        {
            if (Equals(_selectedTag, value)) return;
            _selectedTag = value;
            Raise();
            if (!_suppressTagReload)
                _ = ReloadModelsAsync(CancellationToken.None);
        }
    }

    private string _searchQuery = string.Empty;
    public string SearchQuery
    {
        get => _searchQuery;
        set
        {
            if (_searchQuery == value) return;
            _searchQuery = value;
            Raise();
            _ = DebouncedSearchAsync();
        }
    }

    private CancellationTokenSource? _searchCts;
    private async Task DebouncedSearchAsync()
    {
        _searchCts?.Cancel();
        _searchCts = new CancellationTokenSource();
        var ct = _searchCts.Token;
        try
        {
            await Task.Delay(200, ct);
            await ReloadModelsAsync(ct);
        }
        catch (OperationCanceledException) { }
    }

    private string? FilterTagId => string.IsNullOrEmpty(SelectedTag?.Id) ? null : SelectedTag!.Id;

    public string ScanButtonText => App.Loc?.Get("Library.ScanButton") ?? "Scan folder";
    public string EmptyStateText => App.Loc?.Get("Library.Empty") ?? "No models yet.";
    public string SearchPlaceholder => App.Loc?.Get("Library.SearchPlaceholder") ?? "Search...";
    public string TagsHeader => App.Loc?.Get("Library.TagsHeader") ?? "Tags";

    private enum StatusState { None, Loading, ModelCount, Scanning }
    private StatusState _statusState = StatusState.None;
    private int _statusCount;
    private string _statusDetail = string.Empty;

    public string StatusText => _statusState switch
    {
        StatusState.Loading => App.Loc?.Get("Library.Loading") ?? "Loading...",
        StatusState.ModelCount => string.Format(App.Loc?.Get("Library.ModelsCount") ?? "Models: {0}", _statusCount),
        StatusState.Scanning => _statusDetail,
        _ => string.Empty,
    };

    private void SetStatus(StatusState state, int count = 0, string detail = "")
    {
        _statusState = state; _statusCount = count; _statusDetail = detail;
        Raise(nameof(StatusText));
    }

    public ICommand RequestFocusSearchCommand { get; }

    public LibraryViewModel(
        IModelRepository? models,
        IModelFileRepository? files,
        ScannerService? scanner,
        PreviewGenerator? previews,
        ITagService? tagService,
        IIntegrationService? integration)
    {
        _models = models; _files = files; _scanner = scanner; _previews = previews;
        _tagService = tagService;
        _integration = integration;
        RequestFocusSearchCommand = new RelayCommand(() => FocusSearchRequested?.Invoke(this, EventArgs.Empty));

        Log.Info("[LibraryViewModel] ctor Models=" + (models != null) + " Files=" + (files != null) +
                 " Scanner=" + (scanner != null) + " Previews=" + (previews != null) +
                 " Tags=" + (tagService != null) + " Integration=" + (integration != null));
    }

    public void RequestFocusSearch() => FocusSearchRequested?.Invoke(this, EventArgs.Empty);

    public void RefreshLocalized()
    {
        Raise(nameof(ScanButtonText));
        Raise(nameof(EmptyStateText));
        Raise(nameof(SearchPlaceholder));
        Raise(nameof(TagsHeader));
        foreach (var c in Cards) c.RefreshLocalized();
        if (_statusState == StatusState.ModelCount) SetStatus(StatusState.ModelCount, _statusCount);
        else Raise(nameof(StatusText));
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        Log.Info("[LibraryViewModel] LoadAsync begin");
        if (_models == null || _files == null || _previews == null)
        {
            Log.Warn("[LibraryViewModel] LoadAsync SKIP: services not initialized (" +
                     "Models=" + (_models != null) + " Files=" + (_files != null) + " Previews=" + (_previews != null) + ")");
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.ServicesNotInitialized") ?? "Services not initialized.");
            return;
        }
        IsBusy = true;
        try
        {
            SetStatus(StatusState.Loading);
            await RefreshIntegrationFlagsAsync(ct);
            await LoadTagsAsync(ct);
            await ReloadModelsCoreAsync(ct);
        }
        finally { IsBusy = false; }
        Log.Info("[LibraryViewModel] LoadAsync done cards=" + Cards.Count);
    }

    private async Task RefreshIntegrationFlagsAsync(CancellationToken ct)
    {
        if (_integration == null) return;
        try
        {
            var apps = await _integration.GetAppsAsync(ct);
            _hasSlicer = apps.Any(a => a.Kind == IntegrationAppKind.Slicer && a.IsAvailable);
            _hasEditor = apps.Any(a => a.Kind == IntegrationAppKind.Editor && a.IsAvailable);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] RefreshIntegrationFlags failed", ex); }
    }

    private async Task LoadTagsAsync(CancellationToken ct)
    {
        if (_tagService == null || _models == null) return;
        try
        {
            _suppressTagReload = true;
            Tags.Clear();
            var allModels = await _models.GetAllAsync(ct);
            var tagUsages = await _tagService.GetAllWithUsageAsync(ct);
            var allLabel = App.Loc?.Get("Library.AllModels") ?? "All models";
            Tags.Add(new TagWithUsage("", allLabel, null, null, allModels.Count));
            foreach (var t in tagUsages) Tags.Add(t);

            var currentId = _selectedTag?.Id;
            _selectedTag = currentId != null
                ? Tags.FirstOrDefault(t => t.Id == currentId)
                : Tags.FirstOrDefault();
            Raise(nameof(SelectedTag));
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] LoadTags failed", ex); }
        finally { _suppressTagReload = false; }
    }

    private async Task ReloadModelsAsync(CancellationToken ct)
    {
        IsBusy = true;
        try { await ReloadModelsCoreAsync(ct); }
        finally { IsBusy = false; }
    }

    private async Task ReloadModelsCoreAsync(CancellationToken ct)
    {
        if (_models == null || _files == null || _previews == null) return;
        var models = await _models.SearchAsync(
            string.IsNullOrWhiteSpace(SearchQuery) ? null : SearchQuery,
            FilterTagId, ct);

        Cards.Clear();
        Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count + " (previews serialized via SemaphoreSlim)");
        foreach (var m in models)
        {
            var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                _integration, _hasSlicer, _hasEditor);
            Cards.Add(card);
            _ = Task.Run(async () =>
            {
                await _previewSemaphore.WaitAsync(ct);
                try
                {
                    await card.LoadDetailsAsync(_files, _previews, ct);
                }
                catch (Exception ex)
                {
                    Log.Exception("[LibraryViewModel] LoadDetails failed model=" + m.Id, ex);
                }
                finally
                {
                    _previewSemaphore.Release();
                }
            }, ct);
        }
        SetStatus(Cards.Count == 0 ? StatusState.None : StatusState.ModelCount, Cards.Count);
        Raise(nameof(IsEmpty));
    }

    public async Task ScanAsync(IEnumerable<string> folders, CancellationToken ct = default)
    {
        var folderList = folders.ToList();
        Log.Info("[LibraryViewModel] ScanAsync begin folders=" + folderList.Count +
                 " scanner=" + (_scanner != null) + " models=" + (_models != null) + " files=" + (_files != null));

        if (_scanner == null || _models == null || _files == null || _previews == null)
        {
            Log.Warn("[LibraryViewModel] ScanAsync ABORT: services not initialized (" +
                     "Scanner=" + (_scanner != null) + " Models=" + (_models != null) +
                     " Files=" + (_files != null) + " Previews=" + (_previews != null) + ")");
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.ServicesNotInitialized") ?? "Services not initialized.");
            return;
        }
        if (folderList.Count == 0)
        {
            Log.Warn("[LibraryViewModel] ScanAsync ABORT: no folders selected");
            return;
        }

        IsBusy = true;
        SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Scanning") ?? "Scanning...");
        try
        {
            var progress = new Progress<ScanProgress>(p =>
            {
                var fmt = App.Loc?.Get("Library.ScanningProgress") ?? "Scanning: {0}/{1} (+{2}, ~{3}, ={4})";
                SetStatus(StatusState.Scanning, 0, string.Format(fmt, p.ProcessedFiles, p.TotalFiles, p.Added, p.Updated, p.Skipped));
            });
            Log.Info("[LibraryViewModel] ScanAsync calling Scanner.ScanAsync");
            await _scanner.ScanAsync(folderList, progress, ct);
            Log.Info("[LibraryViewModel] ScanAsync Scanner done");
        }
        catch (Exception ex)
        {
            Log.Exception("[LibraryViewModel] ScanAsync exception", ex);
        }
        finally
        {
            Log.Info("[LibraryViewModel] ScanAsync reload tags + models");
            try { await LoadTagsAsync(ct); } catch (Exception ex) { Log.Exception("[LibraryViewModel] post-scan LoadTags", ex); }
            try { await ReloadModelsCoreAsync(ct); } catch (Exception ex) { Log.Exception("[LibraryViewModel] post-scan ReloadModels", ex); }
            IsBusy = false;
            Log.Info("[LibraryViewModel] ScanAsync end cards=" + Cards.Count);
        }
    }

    private void OnOpenRequested(Model m) => OpenCardRequested?.Invoke(this, m);
    private void OnAddTagForModel(Model m) => OpenCardWithTabRequested?.Invoke(this, (m, 2));

    private async void OnRemoveFromLibrary(Model m)
    {
        if (_models == null) return;
        try
        {
            await _models.DeleteAsync(m.Id);
            var card = Cards.FirstOrDefault(c => c.Model.Id == m.Id);
            if (card != null) Cards.Remove(card);
            SetStatus(Cards.Count == 0 ? StatusState.None : StatusState.ModelCount, Cards.Count);
            Raise(nameof(IsEmpty));
            await LoadTagsAsync(CancellationToken.None);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] OnRemoveFromLibrary failed", ex); }
    }

    public async Task OnPreviewsRegeneratedAsync(string modelId)
    {
        if (_files == null || _previews == null) return;
        var card = Cards.FirstOrDefault(c => c.Model.Id == modelId);
        if (card == null) return;
        await card.ReloadPreviewsAsync(_files, _previews);
    }
}
'@

# ============ ScannerService.cs (GC.Collect every 10 files) ============
$scannerCs = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class ScannerService : IScannerService
{
    private const long MaxFileSizeBytes = 2L * 1024L * 1024L * 1024L;
    private const int GcEveryNFiles = 10;

    private readonly IMeshLoader _meshLoader;
    private readonly IModelRepository _modelRepo;
    private readonly IModelFileRepository _fileRepo;

    public ScannerService(IMeshLoader meshLoader, IModelRepository modelRepo, IModelFileRepository fileRepo)
    {
        _meshLoader = meshLoader;
        _modelRepo = modelRepo;
        _fileRepo = fileRepo;
    }

    public async Task ScanAsync(
        IEnumerable<string> rootFolders,
        IProgress<ScanProgress>? progress = null,
        CancellationToken ct = default)
    {
        var report = progress ?? new Progress<ScanProgress>();
        var state = new ScanProgress();
        var folderList = new List<string>(rootFolders);
        Log.Info("[Scanner] SCAN START folders=[" + string.Join(", ", folderList) + "]");

        var files = new List<FileInfo>();
        foreach (var root in folderList)
        {
            if (ct.IsCancellationRequested) return;
            if (!Directory.Exists(root))
            {
                state.Errors++;
                state.LastError = "Folder not found: " + root;
                Log.Warn("[Scanner] FOLDER missing path=" + root);
                report.Report(state);
                continue;
            }
            try
            {
                var count = 0;
                foreach (var file in Directory.EnumerateFiles(root, "*.*", SearchOption.AllDirectories))
                {
                    if (ct.IsCancellationRequested) break;
                    var ext = Path.GetExtension(file).TrimStart('.').ToLowerInvariant();
                    if (_meshLoader.SupportedExtensions.Contains(ext))
                    {
                        files.Add(new FileInfo(file));
                        count++;
                    }
                }
                Log.Info("[Scanner] FOLDER scanned path=" + root + " matched=" + count);
            }
            catch (Exception ex)
            {
                state.Errors++;
                state.LastError = ex.Message;
                Log.Exception("[Scanner] FOLDER error path=" + root, ex);
                report.Report(state);
            }
        }

        state.TotalFiles = files.Count;
        report.Report(state);
        Log.Info("[Scanner] SCAN FILES total=" + files.Count);

        foreach (var fi in files)
        {
            if (ct.IsCancellationRequested) break;

            var sw = Stopwatch.StartNew();
            var fileName = fi.Name;
            var filePath = fi.FullName;
            var fileSize = fi.Length;

            if (fileSize > MaxFileSizeBytes)
            {
                Log.Warn("[Scanner] FILE skip-too-large path=" + fileName + " size=" + fileSize);
                state.Skipped++;
                state.ProcessedFiles++;
                report.Report(state);
                continue;
            }

            Log.Info("[Scanner] FILE start path=" + fileName + " size=" + fileSize);
            state.CurrentFile = fileName;

            try
            {
                var existing = await _fileRepo.GetByPathAsync(filePath, ct);
                if (existing != null && existing.FileSizeBytes == fileSize && existing.LastWriteTimeUtc == fi.LastWriteTimeUtc)
                {
                    state.Skipped++;
                    Log.Info("[Scanner] FILE skip-unchanged path=" + fileName + " took=" + sw.ElapsedMilliseconds + "ms");
                }
                else
                {
                    var info = _meshLoader.Load(filePath);
                    if (info == null)
                    {
                        state.Errors++;
                        state.LastError = "Parse failed: " + filePath;
                        Log.Warn("[Scanner] FILE parse-failed path=" + fileName + " took=" + sw.ElapsedMilliseconds + "ms");
                    }
                    else if (existing != null)
                    {
                        existing.FileSizeBytes = info.FileSizeBytes;
                        existing.LastWriteTimeUtc = fi.LastWriteTimeUtc;
                        existing.PolygonCount = info.PolygonCount;
                        await _fileRepo.UpsertAsync(existing, ct);
                        var model = await _modelRepo.GetAsync(existing.ModelId, ct);
                        if (model != null)
                        {
                            model.UpdatedAt = DateTime.UtcNow;
                            await _modelRepo.UpsertAsync(model, ct);
                        }
                        state.Updated++;
                        Log.Info("[Scanner] FILE update-ok path=" + fileName + " polys=" + info.PolygonCount + " took=" + sw.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
                    }
                    else
                    {
                        var model = new Model
                        {
                            Title = Path.GetFileNameWithoutExtension(fileName),
                            CreatedAt = DateTime.UtcNow,
                            UpdatedAt = DateTime.UtcNow,
                        };
                        await _modelRepo.UpsertAsync(model, ct);
                        var newFile = new ModelFile
                        {
                            ModelId = model.Id,
                            Path = filePath,
                            FileRole = "main",
                            FileSizeBytes = info.FileSizeBytes,
                            PolygonCount = info.PolygonCount,
                            LastWriteTimeUtc = fi.LastWriteTimeUtc,
                        };
                        await _fileRepo.UpsertAsync(newFile, ct);
                        model.PrimaryModelFileId = newFile.Id;
                        await _modelRepo.UpsertAsync(model, ct);
                        state.Added++;
                        Log.Info("[Scanner] FILE add-ok path=" + fileName + " polys=" + info.PolygonCount + " took=" + sw.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
                    }
                }
            }
            catch (Exception ex)
            {
                state.Errors++;
                state.LastError = fileName + ": " + ex.Message;
                Log.Exception("[Scanner] FILE error path=" + fileName + " took=" + sw.ElapsedMilliseconds + "ms", ex);
            }

            state.ProcessedFiles++;
            report.Report(state);

            if (state.ProcessedFiles % GcEveryNFiles == 0)
            {
                try
                {
                    GC.Collect(GC.MaxGeneration, GCCollectionMode.Optimized, blocking: false);
                }
                catch { }
                Log.Info("[Scanner] GC after " + state.ProcessedFiles + " files mem=" + Log.MemoryMb() + "MB");
            }
        }

        Log.Info("[Scanner] SCAN DONE added=" + state.Added + " updated=" + state.Updated + " skipped=" + state.Skipped + " errors=" + state.Errors + " mem=" + Log.MemoryMb() + "MB");
    }
}
'@

# ============ README ============
$readme = @'
# Patch 0.4.5a3 - Fix Assimp OOM

**Iteration:** 0.4.5

## Root cause (from user log)

1. LibraryViewModel.ReloadModelsCoreAsync launched 76 x Task.Run(LoadDetailsAsync) in parallel.
   Each LoadDetails calls PreviewGenerator -> Assimp ImportFile for a 1.5M-poly model (~500 MB native).
   76 simultaneous native allocations -> "bad allocation" (native OOM).

2. PreviewGenerator called LoadGeometry 4 times per model (once per angle).
   4x time and 4x peak memory for the same model.

3. GC did not release native Assimp scene memory between models (no forced collection).

## Fixes

1. LibraryViewModel: SemaphoreSlim(1,1) around LoadDetailsAsync.
   Only ONE preview generator runs at a time. Others queue.
   UI remains responsive (Task.Run). Previews appear one-by-one.

2. PreviewGenerator:
   - LoadGeometry called ONCE per model, reused for all 4 angles.
   - Explicit GC.Collect after each model (releases native scene memory).
   - Logs per-model: LoadGeometry took, Render per angle, total mem.

3. ScannerService:
   - GC.Collect every 10 processed files.
   - Logs forced GC after N files with mem.

## Expected result

- Scanning 76 x 1.5M poly models no longer OOM.
- Speed: ~90s Assimp Import + 4x ~1s render per model, sequential.
  Total ~2 hours for 76 models. Slow but STABLE.
- Log shows PreviewGen START / LoadGeometry / Render / DONE per model.
- Memory stays bounded (~2 GB peak instead of 10+ GB).

## Not in this patch (planned for 0.4.5a4)

- Fast binary STL header parser for Scan (polys from header, no full Assimp import).
  This will reduce Scan time from ~2 hours to ~5 minutes for 76 x 1.5M STL files.
- Skip preview generation for huge models (>5M tris).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48 (PreviewGeneratorTests still pass - EnsurePreviewsAsync behavior unchanged from caller perspective).
- Scan folder: no OOM, scan completes.
- Log shows PreviewGen per-model with serialized execution.
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $previewGenPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\PreviewGenerator.cs'
    $libVmPath      = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
    $scannerPath    = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\ScannerService.cs'

    Backup-File $previewGenPath
    Backup-File $libVmPath
    Backup-File $scannerPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    Write-Text -Path $previewGenPath -Content $previewGenCs
    Write-Log 'updated: src\MiniCodex.Core\Services\PreviewGenerator.cs (load once, GC after)'

    Write-Text -Path $libVmPath -Content $libVmCs
    Write-Log 'updated: src\MiniCodex.App\ViewModels\LibraryViewModel.cs (SemaphoreSlim 1 preview at a time)'

    Write-Text -Path $scannerPath -Content $scannerCs
    Write-Log 'updated: src\MiniCodex.Core\Services\ScannerService.cs (GC every 10 files)'

    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.5a3\README.md'

    # Verify
    $verifyPg = [IO.File]::ReadAllText($previewGenPath, [Text.Encoding]::UTF8)
    if ($verifyPg -match 'geometry == null') { Write-Log 'verify OK: PreviewGenerator loads geometry once' }
    else { Write-Log 'verify FAIL: load-once not found' 'WARN' }

    $verifyLib = [IO.File]::ReadAllText($libVmPath, [Text.Encoding]::UTF8)
    if ($verifyLib -match '_previewSemaphore') { Write-Log 'verify OK: LibraryViewModel has SemaphoreSlim' }
    else { Write-Log 'verify FAIL: SemaphoreSlim not found' 'WARN' }

    $verifyScn = [IO.File]::ReadAllText($scannerPath, [Text.Encoding]::UTF8)
    if ($verifyScn -match 'GC after .*files') { Write-Log 'verify OK: ScannerService has GC after N files' }
    else { Write-Log 'verify FAIL: GC after N files not found' 'WARN' }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a3 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.5a3: Assimp OOM during scan (76 parallel previews -> SemaphoreSlim 1, load-once per model, GC after each).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a2\].*)$', "$entry`$1"
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
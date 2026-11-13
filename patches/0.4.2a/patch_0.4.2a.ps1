#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.2a - PreviewGenerator uses orientation (plumbing).
.DESCRIPTION
    Extends IPreviewGenerator with baseYaw/basePitch/forceRegenerate.
    ModelCardViewModel passes Model.OrientationJson offset.
    No UI change; button comes in 0.4.2b.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.2a'
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

$Files = @{}

# ============ IPreviewGenerator.cs ============
$Files['src\MiniCodex.Core\Services\IPreviewGenerator.cs'] = @'
namespace MiniCodex.Core.Services;

public interface IPreviewGenerator
{
    /// <summary>
    /// Guarantees 4 PNG previews for the model.
    /// baseYawDegrees / basePitchDegrees are ADDITIVE offsets on top of standard angles
    /// (default 180, 270, 0, 90 yaw and 15 pitch). forceRegenerate bypasses the cache check.
    /// </summary>
    Task<IReadOnlyList<string?>> EnsurePreviewsAsync(
        string modelId,
        string meshPath,
        DateTime sourceUpdatedAt,
        float baseYawDegrees = 0f,
        float basePitchDegrees = 0f,
        bool forceRegenerate = false,
        CancellationToken ct = default);
}
'@

# ============ PreviewGenerator.cs ============
$Files['src\MiniCodex.Core\Services\PreviewGenerator.cs'] = @'
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MiniCodex.Core.Services;

public class PreviewGenerator : IPreviewGenerator
{
    // Bumped only when the render algorithm changes. Base orientation is tracked separately.
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
            () => GenerateAll(modelId, meshPath, sourceUpdatedAt,
                              baseYawDegrees, basePitchDegrees, forceRegenerate, ct),
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

        for (int i = 0; i < _options.YawDegrees.Length; i++)
        {
            if (ct.IsCancellationRequested) return results;
            var pngPath = Path.Combine(modelDir, $"{(int)_options.YawDegrees[i]}.png");
            if (needsRegen || !File.Exists(pngPath))
            {
                var yaw = _options.YawDegrees[i] + baseYaw;
                var pitch = _options.PitchDegrees + basePitch;
                pngPath = RenderOne(meshPath, yaw, pitch, pngPath, ct);
            }
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
                BaseYaw = baseYaw,
                BasePitch = basePitch,
            };
            File.WriteAllText(metaPath, JsonSerializer.Serialize(newMeta, new JsonSerializerOptions { WriteIndented = true }));
        }
        return results;
    }

    private string RenderOne(string meshPath, float yaw, float pitch, string outPath, CancellationToken ct)
    {
        var geometry = _loader.LoadGeometry(meshPath);
        if (geometry == null || geometry.TriangleCount == 0) return outPath;
        if (ct.IsCancellationRequested) return outPath;

        var png = _renderer.Render(geometry, _options.Width, _options.Height, yaw, pitch);
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
        [JsonPropertyName("baseYaw")] public float BaseYaw { get; set; }
        [JsonPropertyName("basePitch")] public float BasePitch { get; set; }
    }
}
'@

# ============ ModelCardViewModel.cs ============
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

    private readonly Bitmap?[] _previews = new Bitmap?[4];
    private int _previewIndex;
    private bool _isHovered;
    private bool _hasSlicer;
    private bool _hasEditor;
    private string? _primaryFilePath;

    public bool IsHovered
    {
        get => _isHovered;
        set { if (_isHovered != value) { _isHovered = value; Raise(); } }
    }

    public Bitmap? PreviewImage => _previews.Length > _previewIndex ? _previews[_previewIndex] : null;

    public bool CanOpenInSlicer => _hasSlicer && !string.IsNullOrEmpty(_primaryFilePath);
    public bool CanOpenInEditor => _hasEditor && !string.IsNullOrEmpty(_primaryFilePath);
    public bool HasMultipleFiles { get; private set; }

    private string _totalSizeText = string.Empty;
    public string TotalSizeText { get => _totalSizeText; private set { _totalSizeText = value; Raise(); } }

    private string _polygonsText = string.Empty;
    public string PolygonsText { get => _polygonsText; private set { _polygonsText = value; Raise(); } }

    private string _fileCountText = string.Empty;
    public string FileCountText { get => _fileCountText; private set { _fileCountText = value; Raise(); } }

    public string ContextMenuOpenCard => Loc("Library.ContextMenu.OpenCard", "Open card");
    public string ContextMenuCopyPath => Loc("Library.ContextMenu.CopyPath", "Copy path");
    public string ContextMenuAddTag => Loc("Library.ContextMenu.AddTag", "Add tag");
    public string ContextMenuRemoveFromLibrary => Loc("Library.ContextMenu.RemoveFromLibrary", "Remove from library");
    public string QuickActionToSlicer => Loc("Library.QuickActions.ToSlicer", "To slicer");
    public string QuickActionToEditor => Loc("Library.QuickActions.ToEditor", "To editor");
    public string QuickActionShowInFolder => Loc("Library.QuickActions.ShowInFolder", "Show in folder");
    public string MoreActionsTooltip => Loc("Library.MoreActions", "More...");

    public ICommand OpenCommand { get; }
    public ICommand CopyPathCommand { get; }
    public ICommand AddTagCommand { get; }
    public ICommand RemoveFromLibraryCommand { get; }
    public ICommand ShowInFolderCommand { get; }
    public ICommand ToSlicerCommand { get; }
    public ICommand ToEditorCommand { get; }

    private readonly Action<Model> _onOpen;
    private readonly Action<Model> _onAddTag;
    private readonly Action<Model> _onRemoveFromLibrary;
    private readonly IIntegrationService? _integration;

    public ModelCardViewModel(
        Model model,
        Action<Model> onOpen,
        Action<Model> onAddTag,
        Action<Model> onRemoveFromLibrary,
        IIntegrationService? integration,
        bool hasSlicer,
        bool hasEditor)
    {
        Model = model;
        _onOpen = onOpen;
        _onAddTag = onAddTag;
        _onRemoveFromLibrary = onRemoveFromLibrary;
        _integration = integration;
        _hasSlicer = hasSlicer;
        _hasEditor = hasEditor;

        OpenCommand = new RelayCommand(() => _onOpen(Model));
        CopyPathCommand = new RelayCommand(async () => await CopyPathAsync());
        AddTagCommand = new RelayCommand(() => _onAddTag(Model));
        RemoveFromLibraryCommand = new RelayCommand(() => _onRemoveFromLibrary(Model));
        ShowInFolderCommand = new RelayCommand(() => ShowInFolder());
        ToSlicerCommand = new RelayCommand(async () => await LaunchAsync(IntegrationAppKind.Slicer));
        ToEditorCommand = new RelayCommand(async () => await LaunchAsync(IntegrationAppKind.Editor));
    }

    public void RotateTo(int index)
    {
        if (index < 0 || index >= _previews.Length) return;
        if (index == _previewIndex) return;
        if (_previews[index] == null) return;
        _previewIndex = index;
        Raise(nameof(PreviewImage));
    }

    public bool HasRotation => _previews.All(b => b != null);

    public void RefreshLocalized()
    {
        Raise(nameof(ContextMenuOpenCard));
        Raise(nameof(ContextMenuCopyPath));
        Raise(nameof(ContextMenuAddTag));
        Raise(nameof(ContextMenuRemoveFromLibrary));
        Raise(nameof(QuickActionToSlicer));
        Raise(nameof(QuickActionToEditor));
        Raise(nameof(QuickActionShowInFolder));
        Raise(nameof(MoreActionsTooltip));
    }

    public async Task ReloadPreviewsAsync(
        IModelFileRepository files,
        PreviewGenerator previews,
        CancellationToken ct = default)
    {
        for (int i = 0; i < _previews.Length; i++) _previews[i] = null;
        _previewIndex = 0;
        Raise(nameof(PreviewImage));
        Raise(nameof(HasRotation));
        await LoadDetailsAsync(files, previews, ct);
    }

    public async Task LoadDetailsAsync(
        IModelFileRepository files,
        PreviewGenerator previews,
        CancellationToken ct = default)
    {
        try
        {
            var allFiles = await files.GetByModelAsync(Model.Id, ct);
            if (allFiles.Count > 0)
            {
                var totalSize = allFiles.Sum(f => f.FileSizeBytes ?? 0);
                var totalPoly = allFiles.Sum(f => (long)(f.PolygonCount ?? 0));
                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    TotalSizeText = FormatSize(totalSize);
                    PolygonsText = string.Format(Loc("Library.Hover.PolygonsFormat", "{0:N0} tris"), totalPoly);
                    HasMultipleFiles = allFiles.Count > 1;
                    Raise(nameof(HasMultipleFiles));
                    FileCountText = string.Format(Loc("Library.Hover.FilesFormat", "{0} files"), allFiles.Count);
                });
            }

            if (Model.PrimaryModelFileId == null) return;
            var primary = allFiles.FirstOrDefault(f => f.Id == Model.PrimaryModelFileId);
            if (primary == null) return;
            _primaryFilePath = primary.Path;

            var (yawOff, pitchOff) = ParseOrientationOffset(Model.OrientationJson);

            var results = await previews.EnsurePreviewsAsync(
                Model.Id, primary.Path, Model.UpdatedAt, yawOff, pitchOff, false, ct);
            for (int i = 0; i < _previews.Length && i < results.Count; i++)
            {
                var path = results[i];
                if (path == null) continue;
                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    try
                    {
                        using var stream = File.OpenRead(path);
                        _previews[i] = new Bitmap(stream);
                    }
                    catch { }
                });
            }
            await Dispatcher.UIThread.InvokeAsync(() =>
            {
                Raise(nameof(PreviewImage));
                Raise(nameof(HasRotation));
                Raise(nameof(CanOpenInSlicer));
                Raise(nameof(CanOpenInEditor));
            });
        }
        catch { }
    }

    private static (float yaw, float pitch) ParseOrientationOffset(string? json)
    {
        var o = ModelOrientation.Parse(json);
        return (o.Yaw - 180f, o.Pitch - 15f);
    }

    private async Task CopyPathAsync()
    {
        if (string.IsNullOrEmpty(_primaryFilePath)) return;
        try
        {
            if (Avalonia.Application.Current?.ApplicationLifetime is Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime desktop
                && desktop.MainWindow?.Clipboard != null)
            {
                await desktop.MainWindow.Clipboard.SetTextAsync(_primaryFilePath);
            }
        }
        catch { }
    }

    private void ShowInFolder()
    {
        if (string.IsNullOrEmpty(_primaryFilePath)) return;
        try
        {
            if (OperatingSystem.IsWindows())
                Services.FileSystemHelper.ShowInExplorer(_primaryFilePath);
        }
        catch { }
    }

    private async Task LaunchAsync(IntegrationAppKind kind)
    {
        if (_integration == null || string.IsNullOrEmpty(_primaryFilePath)) return;
        try
        {
            var apps = await _integration.GetAppsAsync();
            var first = apps.FirstOrDefault(a => a.Kind == kind && a.IsAvailable);
            if (first == null) return;
            await _integration.LaunchAsync(first.Id, _primaryFilePath);
        }
        catch { }
    }

    private static string FormatSize(long bytes)
    {
        string[] units = { "B", "KB", "MB", "GB" };
        double v = bytes; int u = 0;
        while (v >= 1024 && u < units.Length - 1) { v /= 1024; u++; }
        return $"{v:F1} {units[u]}";
    }

    private static string Loc(string key, string fallback) => App.Loc?.Get(key) ?? fallback;
}
'@

# ============ README ============
$Files['patches\0.4.2a\README.md'] = @'
# Patch 0.4.2a - PreviewGenerator uses orientation (plumbing)

**Iteration:** 0.4

## What it does

- IPreviewGenerator.EnsurePreviewsAsync: 3 new optional params (baseYawDegrees, basePitchDegrees, forceRegenerate).
  Backward compatible: existing 4-arg calls use defaults (0, 0, false).
- PreviewGenerator:
  - Effective yaw = standard_yaw + baseYaw; effective pitch = 15 + basePitch.
  - CacheMetadata now stores baseYaw, basePitch. Cache invalidates if they differ from stored by >0.01.
  - forceRegenerate bypasses cache check.
  - RendererVersion kept at "0.2.3c" to avoid mass regen for models with default orientation.
- ModelCardViewModel.LoadDetailsAsync:
  - Reads Model.OrientationJson.
  - Computes offset relative to defaults (180 yaw, 15 pitch): offset = (o.Yaw - 180, o.Pitch - 15).
  - Passes offset to EnsurePreviewsAsync.
  - Models without orientation -> offset (0, 0) -> same behavior as before.
- ModelCardViewModel.ReloadPreviewsAsync: clears _previews[], reloads (used by 0.4.2b).

## No UI change

The "Regenerate previews" button and library tile refresh come in 0.4.2b.
Effect after 0.4.2a: if user saved orientation and reloads library (restart, rescan),
the tile shows the new angle. No button yet.

## DoD

- dotnet build: 0 errors.
- dotnet test: 40/40 (PreviewGeneratorTests still pass; stub call signature unchanged for Render).
- App starts and behaves as 0.4.2 (no regressions).
'@

# ============ Main ============
try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.Core\Services\IPreviewGenerator.cs',
        'src\MiniCodex.Core\Services\PreviewGenerator.cs',
        'src\MiniCodex.App\ViewModels\ModelCardViewModel.cs',
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
    $marker = '<!-- patch 0.4.2a applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.2a] - 2026-11-10`r`n`r`n### Added`r`n- IPreviewGenerator: baseYawDegrees, basePitchDegrees, forceRegenerate.`r`n- PreviewGenerator: base yaw/pitch in cache metadata, invalidation on mismatch.`r`n- ModelCardViewModel: passes orientation offset from Model.OrientationJson.`r`n- ModelCardViewModel.ReloadPreviewsAsync (for 0.4.2b).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.2\].*)$', "$entry`$1"
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
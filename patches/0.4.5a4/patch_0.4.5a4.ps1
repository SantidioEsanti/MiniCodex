#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a4 - Preview progress in status bar, cancel pending on detach, no duplicates.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a4'
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

# ============ LibraryViewModel.cs (progress + cancellation) ============
$libVmCs = @'
using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Windows.Input;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public class LibraryViewModel : INotifyPropertyChanged, IAsyncDisposable
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

    private readonly SemaphoreSlim _previewSemaphore = new SemaphoreSlim(1, 1);
    private CancellationTokenSource _lifetimeCts = new CancellationTokenSource();
    private bool _disposed;

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

    private enum StatusState { None, Loading, ModelCount, Scanning, Previews }
    private StatusState _statusState = StatusState.None;
    private int _statusCount;
    private string _statusDetail = string.Empty;

    private int _previewsDone;
    private int _previewsTotal;
    public int PreviewsDone { get => _previewsDone; private set { _previewsDone = value; Raise(); } }
    public int PreviewsTotal { get => _previewsTotal; private set { _previewsTotal = value; Raise(); } }

    public string StatusText => _statusState switch
    {
        StatusState.Loading => App.Loc?.Get("Library.Loading") ?? "Loading...",
        StatusState.ModelCount => string.Format(App.Loc?.Get("Library.ModelsCount") ?? "Models: {0}", _statusCount),
        StatusState.Scanning => _statusDetail,
        StatusState.Previews => string.Format(App.Loc?.Get("Library.PreviewsProgress") ?? "Previews: {0} / {1}", _previewsDone, _previewsTotal),
        _ => string.Empty,
    };

    private void SetStatus(StatusState state, int count = 0, string detail = "")
    {
        _statusState = state; _statusCount = count; _statusDetail = detail;
        Raise(nameof(StatusText));
    }

    private void UpdatePreviewsStatus()
    {
        if (_previewsTotal > 0 && _previewsDone < _previewsTotal)
            SetStatus(StatusState.Previews);
        else if (Cards.Count > 0)
            SetStatus(StatusState.ModelCount, Cards.Count);
        else
            SetStatus(StatusState.None);
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
                 " Scanner=" + (scanner != null) + " Previews=" + (previews != null));
    }

    public void RequestFocusSearch() => FocusSearchRequested?.Invoke(this, EventArgs.Empty);

    public void RefreshLocalized()
    {
        Raise(nameof(ScanButtonText));
        Raise(nameof(EmptyStateText));
        Raise(nameof(SearchPlaceholder));
        Raise(nameof(TagsHeader));
        foreach (var c in Cards) c.RefreshLocalized();
        UpdatePreviewsStatus();
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        Log.Info("[LibraryViewModel] LoadAsync begin");
        if (_models == null || _files == null || _previews == null)
        {
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
        if (_disposed) return;
        var models = await _models.SearchAsync(
            string.IsNullOrWhiteSpace(SearchQuery) ? null : SearchQuery,
            FilterTagId, ct);
        if (_disposed) return;

        Cards.Clear();
        PreviewsDone = 0;
        PreviewsTotal = models.Count;
        Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count);

        var lifetimeToken = _lifetimeCts.Token;
        foreach (var m in models)
        {
            var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                _integration, _hasSlicer, _hasEditor);
            Cards.Add(card);
            _ = Task.Run(async () =>
            {
                if (lifetimeToken.IsCancellationRequested) return;
                await _previewSemaphore.WaitAsync(lifetimeToken).ConfigureAwait(false);
                try
                {
                    if (lifetimeToken.IsCancellationRequested) return;
                    await card.LoadDetailsAsync(_files, _previews, lifetimeToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException) { }
                catch (Exception ex)
                {
                    Log.Exception("[LibraryViewModel] LoadDetails failed model=" + m.Id, ex);
                }
                finally
                {
                    _previewSemaphore.Release();
                    Avalonia.Threading.Dispatcher.UIThread.Post(() =>
                    {
                        PreviewsDone++;
                        UpdatePreviewsStatus();
                    });
                }
            }, lifetimeToken);
        }

        UpdatePreviewsStatus();
        Raise(nameof(IsEmpty));
    }

    public async Task ScanAsync(IEnumerable<string> folders, CancellationToken ct = default)
    {
        var folderList = folders.ToList();
        Log.Info("[LibraryViewModel] ScanAsync begin folders=" + folderList.Count +
                 " scanner=" + (_scanner != null) + " models=" + (_models != null) + " files=" + (_files != null));

        if (_scanner == null || _models == null || _files == null || _previews == null)
        {
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.ServicesNotInitialized") ?? "Services not initialized.");
            return;
        }
        if (folderList.Count == 0) return;

        IsBusy = true;
        SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Scanning") ?? "Scanning...");
        try
        {
            var progress = new Progress<ScanProgress>(p =>
            {
                var fmt = App.Loc?.Get("Library.ScanningProgress") ?? "Scanning: {0}/{1} (+{2}, ~{3}, ={4})";
                SetStatus(StatusState.Scanning, 0, string.Format(fmt, p.ProcessedFiles, p.TotalFiles, p.Added, p.Updated, p.Skipped));
            });
            await _scanner.ScanAsync(folderList, progress, ct);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] ScanAsync exception", ex); }
        finally
        {
            try { await LoadTagsAsync(ct); } catch { }
            try { await ReloadModelsCoreAsync(ct); } catch { }
            IsBusy = false;
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

    public ValueTask DisposeAsync()
    {
        if (_disposed) return ValueTask.CompletedTask;
        _disposed = true;
        try { _lifetimeCts.Cancel(); } catch { }
        try { _lifetimeCts.Dispose(); } catch { }
        try { _previewSemaphore.Dispose(); } catch { }
        Log.Info("[LibraryViewModel] disposed (pending preview tasks cancelled)");
        return ValueTask.CompletedTask;
    }
}
'@

# ============ LibraryView.axaml.cs (dispose on detach) ============
$libViewCs = @'
using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using MiniCodex.App.ViewModels;
using MiniCodex.Core.Logging;

namespace MiniCodex.App.Views;

public partial class LibraryView : UserControl
{
    public LibraryView()
    {
        InitializeComponent();
    }

    protected override void OnAttachedToVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        if (DataContext is LibraryViewModel vm)
            vm.FocusSearchRequested += OnFocusSearchRequested;
    }

    protected override async void OnDetachedFromVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        if (DataContext is LibraryViewModel vm)
        {
            vm.FocusSearchRequested -= OnFocusSearchRequested;
            try
            {
                await vm.DisposeAsync();
            }
            catch (Exception ex)
            {
                Log.Exception("[LibraryView] dispose failed", ex);
            }
        }
        base.OnDetachedFromVisualTree(e);
    }

    private void OnFocusSearchRequested(object? sender, EventArgs e)
    {
        SearchBox?.Focus();
    }

    protected override async void OnLoaded(RoutedEventArgs e)
    {
        base.OnLoaded(e);
        try
        {
            if (DataContext is LibraryViewModel vm)
            {
                Log.Info("[LibraryView] OnLoaded -> vm.LoadAsync");
                await vm.LoadAsync();
            }
        }
        catch (Exception ex) { Log.Exception("[LibraryView] OnLoaded failed", ex); }
    }

    private async void OnScanClick(object? sender, RoutedEventArgs e)
    {
        try
        {
            Log.Info("[LibraryView] OnScanClick begin");
            if (DataContext is not LibraryViewModel vm) return;
            var topLevel = TopLevel.GetTopLevel(this);
            if (topLevel?.StorageProvider is null) return;

            var folders = await topLevel.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
            {
                Title = App.Loc?.Get("Library.ScanFolderTitle") ?? "Select source folder",
                AllowMultiple = true,
            });
            Log.Info("[LibraryView] OnScanClick folders=" + folders.Count);
            if (folders.Count == 0) return;

            var paths = folders
                .Select(f => f.TryGetLocalPath())
                .Where(p => !string.IsNullOrEmpty(p))
                .Cast<string>()
                .ToList();
            if (paths.Count == 0) return;

            await vm.ScanAsync(paths);
        }
        catch (Exception ex) { Log.Exception("[LibraryView] OnScanClick failed", ex); }
    }
}
'@

# ============ lang updates (PreviewsProgress) ============
$langEn = @'
{
  "Library.PreviewsProgress": "Previews: {0} / {1}"
}
'@
$langRu = @'
{
  "Library.PreviewsProgress": "Превью: {0} / {1}"
}
'@

# ============ README ============
$readme = @'
# Patch 0.4.5a4 - Preview progress, no duplicates

**Iteration:** 0.4.5

## What it does

1. LibraryViewModel: preview progress in status bar.
   - PreviewsDone / PreviewsTotal counters.
   - Status: "Previews: 8 / 248" during queue, back to "Models: 248" when done.

2. LibraryViewModel: IAsyncDisposable.
   - CancellationTokenSource _lifetimeCts cancels all pending preview tasks on dispose.
   - OnDetachedFromVisualTree in LibraryView calls vm.DisposeAsync().
   - Prevents duplicate parallel PreviewGen (old VM no longer queues tasks).

3. LibraryView: clean dispose on detach.

4. lang: Library.PreviewsProgress.

## Why

User closed app while previews were still generating (log showed EXIT after 8/248 models).
Without progress UI, "still working" looked like "hanging".
Without cancellation, navigating away/back created a second LibraryViewModel whose SemaphoreSlim
allowed a second parallel PreviewGen (memory spike to 1.6 GB, potential re-OOM on huge libs).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Scan a large folder: status bar shows "Previews: X / Y" until done, then "Models: Y".
- Navigate to Settings and back: no duplicate parallel PreviewGen in log.
- Close app mid-generation: pending tasks cancelled cleanly.
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $libVmPath   = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
    $libViewPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\LibraryView.axaml.cs'
    $enPath      = Join-Path $ProjectRoot 'lang\en.json'
    $ruPath      = Join-Path $ProjectRoot 'lang\ru.json'

    Backup-File $libVmPath
    Backup-File $libViewPath
    Backup-File $enPath
    Backup-File $ruPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    Write-Text -Path $libVmPath -Content $libVmCs
    Write-Log 'updated: LibraryViewModel.cs (progress + cancellation + dispose)'

    Write-Text -Path $libViewPath -Content $libViewCs
    Write-Log 'updated: LibraryView.axaml.cs (dispose on detach)'

    # ============ lang/en.json ============
    if (Test-Path $enPath) {
        $en = [IO.File]::ReadAllText($enPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not ($en.Library.PSObject.Properties.Name -contains 'PreviewsProgress')) {
            $en.Library | Add-Member -NotePropertyName 'PreviewsProgress' -NotePropertyValue 'Previews: {0} / {1}' -Force
        }
        $outEn = $en | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($enPath, $outEn, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: lang\en.json (PreviewsProgress)'
    }

    # ============ lang/ru.json (char-array) ============
    if (Test-Path $ruPath) {
        $ru = [IO.File]::ReadAllText($ruPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $ruPreview = -join ((0x041F,0x0440,0x0435,0x0432,0x044C,0x044E,0x003A,0x0020,0x007B,0x0030,0x007D,0x0020,0x002F,0x0020,0x007B,0x0031,0x007D) | ForEach-Object { [char]$_ })
        if (-not ($ru.Library.PSObject.Properties.Name -contains 'PreviewsProgress')) {
            $ru.Library | Add-Member -NotePropertyName 'PreviewsProgress' -NotePropertyValue $ruPreview -Force
        }
        $outRu = $ru | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($ruPath, $outRu, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: lang\ru.json (PreviewsProgress)'
    }

    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.5a4\README.md'

    # Verify
    $verify = [IO.File]::ReadAllText($libVmPath, [Text.Encoding]::UTF8)
    $checks = @(
        @('PreviewsDone counter', ($verify -match 'public int PreviewsDone')),
        @('IAsyncDisposable', ($verify -match 'IAsyncDisposable')),
        @('_lifetimeCts', ($verify -match '_lifetimeCts'))
    )
    foreach ($c in $checks) {
        if ($c[1]) { Write-Log ("verify OK: " + $c[0]) }
        else { Write-Log ("verify FAIL: " + $c[0]) 'WARN' }
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a4 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a4] - 2026-11-12`r`n`r`n### Added`r`n- Preview generation progress in status bar (Previews: X / Y).`r`n- LibraryViewModel implements IAsyncDisposable; cancels pending preview tasks on detach.`r`n`r`n### Fixed`r`n- Duplicate parallel PreviewGen when navigating away and back.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a3\].*)$', "$entry`$1"
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
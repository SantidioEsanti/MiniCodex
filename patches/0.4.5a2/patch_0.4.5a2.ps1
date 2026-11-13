#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a2 - Restore DatabaseInitializer + AppServices.Init (lost in 0.4.5a1), add null-service logging.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a2'
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

# ============ App.axaml.cs (restore DatabaseInitializer + AppServices.Init) ============
$appCs = @'
using System;
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using MiniCodex.App.Services;
using MiniCodex.App.Views;
using MiniCodex.Core.Logging;
using MiniCodex.Data;

namespace MiniCodex.App;

public partial class App : Application
{
    public static AppPaths Paths { get; private set; } = null!;
    public static LocalizationService Loc { get; private set; } = null!;
    public static ThemeService Theme { get; private set; } = null!;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            Dispatcher.UIThread.UnhandledException += (s, e) =>
            {
                Log.Exception("[Dispatcher.UIThread.UnhandledException]", e.Exception);
                e.Handled = false;
            };

            Paths = new AppPaths();
            Paths.EnsureCreated();
            Log.Info("[App] Paths.Root=" + Paths.Root + " LibraryDb=" + Paths.LibraryDb);

            try
            {
                Log.Info("[App] DatabaseInitializer.InitializeAsync begin");
                DatabaseInitializer.InitializeAsync(Paths.LibraryDb).GetAwaiter().GetResult();
                Log.Info("[App] DatabaseInitializer.InitializeAsync ok");
            }
            catch (Exception ex)
            {
                Log.Exception("[App] DatabaseInitializer failed", ex);
                throw;
            }

            try
            {
                Log.Info("[App] AppServices.Init begin");
                AppServices.Init(Paths);
                Log.Info("[App] AppServices.Init ok: Models=" + (AppServices.Models != null) +
                         " ModelFiles=" + (AppServices.ModelFiles != null) +
                         " Scanner=" + (AppServices.Scanner != null) +
                         " Preview=" + (AppServices.PreviewGenerator != null) +
                         " Settings=" + (AppServices.Settings != null) +
                         " AssetService=" + (AppServices.AssetService != null) +
                         " TagService=" + (AppServices.TagService != null) +
                         " Integration=" + (AppServices.IntegrationService != null));
            }
            catch (Exception ex)
            {
                Log.Exception("[App] AppServices.Init failed", ex);
                throw;
            }

            Loc = new LocalizationService(Paths, "en");
            Loc.LoadInitial();
            Log.Info("[App] language=" + Loc.Current);

            Theme = new ThemeService(this);

            desktop.MainWindow = new MainWindow();
        }
        base.OnFrameworkInitializationCompleted();
    }
}
'@

# ============ LibraryViewModel.cs (add logging around ScanAsync) ============
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
        foreach (var m in models)
        {
            var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                _integration, _hasSlicer, _hasEditor);
            Cards.Add(card);
            _ = Task.Run(() => card.LoadDetailsAsync(_files, _previews, ct), ct);
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

# ============ LibraryView.axaml.cs (log OnScanClick flow) ============
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

    protected override void OnDetachedFromVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        if (DataContext is LibraryViewModel vm)
            vm.FocusSearchRequested -= OnFocusSearchRequested;
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
                Log.Info("[LibraryView] OnLoaded done");
            }
            else
            {
                Log.Warn("[LibraryView] OnLoaded: DataContext is not LibraryViewModel");
            }
        }
        catch (Exception ex)
        {
            Log.Exception("[LibraryView] OnLoaded failed", ex);
        }
    }

    private async void OnScanClick(object? sender, RoutedEventArgs e)
    {
        try
        {
            Log.Info("[LibraryView] OnScanClick begin");
            if (DataContext is not LibraryViewModel vm)
            {
                Log.Warn("[LibraryView] OnScanClick: DataContext is not LibraryViewModel");
                return;
            }
            var topLevel = TopLevel.GetTopLevel(this);
            if (topLevel?.StorageProvider is null)
            {
                Log.Warn("[LibraryView] OnScanClick: StorageProvider is null");
                return;
            }

            var folders = await topLevel.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
            {
                Title = App.Loc?.Get("Library.ScanFolderTitle") ?? "Select source folder",
                AllowMultiple = true,
            });
            Log.Info("[LibraryView] OnScanClick: folder picker returned count=" + folders.Count);
            if (folders.Count == 0)
            {
                Log.Info("[LibraryView] OnScanClick: user cancelled or nothing selected");
                return;
            }

            var paths = folders
                .Select(f => f.TryGetLocalPath())
                .Where(p => !string.IsNullOrEmpty(p))
                .Cast<string>()
                .ToList();
            Log.Info("[LibraryView] OnScanClick: resolved paths=" + paths.Count);
            foreach (var p in paths) Log.Info("[LibraryView] OnScanClick: path=" + p);
            if (paths.Count == 0)
            {
                Log.Warn("[LibraryView] OnScanClick: all TryGetLocalPath returned null");
                return;
            }

            await vm.ScanAsync(paths);
            Log.Info("[LibraryView] OnScanClick done");
        }
        catch (Exception ex)
        {
            Log.Exception("[LibraryView] OnScanClick failed", ex);
        }
    }
}
'@

# ============ README ============
$readme = @'
# Patch 0.4.5a2 - Restore Init + null-service logging

**Iteration:** 0.4.5

## Root cause

0.4.5a1 rewrote App.axaml.cs and LOST two critical calls:
  DatabaseInitializer.InitializeAsync(Paths.LibraryDb)
  AppServices.Init(Paths)

Without them: AppServices.Scanner = null, Models = null, etc.
LibraryViewModel.ScanAsync silently returns at first null check.
No "SCAN START" in log; no scanning; no user feedback.

## What it does

1. App.axaml.cs: restore DatabaseInitializer.InitializeAsync + AppServices.Init.
   Each step logs begin/ok/fail. Logs service availability after Init.

2. LibraryViewModel:
   - ctor logs which services are non-null.
   - LoadAsync logs begin / skip-reason / done.
   - ScanAsync logs begin + folder count + service availability.
     ABORT reasons (services null / empty folders) logged as WARN.
     try/catch around Scanner call + post-scan reload; final "end cards=N".

3. LibraryView.axaml.cs:
   - OnLoaded logs begin / DataContext type / end.
   - OnScanClick logs each step: click, DataContext type, StorageProvider null-check,
     folder picker returned count, resolved paths, each path, vm.ScanAsync call, end.
   - try/catch -> Log.Exception.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Scan folder works. Log shows [LibraryView] OnScanClick -> [LibraryViewModel] ScanAsync
  -> [Scanner] SCAN START -> FILE start/ok per file -> SCAN DONE -> post-scan reload.

## If crash now

Log tail after crash clearly shows:
- last [Scanner] FILE start path=X (but no following add-ok) -> crash on X
- OutOfMemoryException stack -> memory
- AccessViolationException -> native crash
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $appPath = Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml.cs'
    $libVmPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
    $libViewPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Views\LibraryView.axaml.cs'

    Backup-File $appPath
    Backup-File $libVmPath
    Backup-File $libViewPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    Write-Text -Path $appPath -Content $appCs
    Write-Log 'updated: src\MiniCodex.App\App.axaml.cs (restored DatabaseInitializer + AppServices.Init)'

    Write-Text -Path $libVmPath -Content $libVmCs
    Write-Log 'updated: src\MiniCodex.App\ViewModels\LibraryViewModel.cs (logging)'

    Write-Text -Path $libViewPath -Content $libViewCs
    Write-Log 'updated: src\MiniCodex.App\Views\LibraryView.axaml.cs (logging)'

    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.5a2\README.md'

    # Verify App.axaml.cs has both calls
    $appVerify = [IO.File]::ReadAllText($appPath, [Text.Encoding]::UTF8)
    $checks = @(
        @('DatabaseInitializer.InitializeAsync present', ($appVerify -match 'DatabaseInitializer\.InitializeAsync')),
        @('AppServices.Init present', ($appVerify -match 'AppServices\.Init\(Paths\)'))
    )
    foreach ($c in $checks) {
        if ($c[1]) { Write-Log ("verify OK: " + $c[0]) }
        else { Write-Log ("verify FAIL: " + $c[0]) 'WARN' }
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a2 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n### Fixed`r`n- 0.4.5a2: restored DatabaseInitializer.InitializeAsync + AppServices.Init (lost in 0.4.5a1) - scanning was silently no-op.`r`n- 0.4.5a2: LibraryView/LibraryViewModel log every step of scan flow.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a1\].*)$', "$entry`$1"
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
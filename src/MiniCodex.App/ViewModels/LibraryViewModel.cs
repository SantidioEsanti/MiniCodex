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
    private bool _showScanWarning;
    public bool ShowScanWarning
    {
        get => _showScanWarning;
        private set { _showScanWarning = value; Raise(); }
    }

    private List<string> _pendingScanFolders = new();

    public string ScanWarningTitle => App.Loc?.Get("Library.ScanWarning.Title") ?? "Long scan";
    public string ScanWarningMessage => App.Loc?.Get("Library.ScanWarning.Message") ?? "Large libraries with high-poly models may take 15-30 minutes. The app stays responsive and shows progress. Continue?";
    public string ScanWarningContinueText => App.Loc?.Get("Library.ScanWarning.Continue") ?? "Continue";
    public string ScanWarningCancelText => App.Loc?.Get("Library.ScanWarning.Cancel") ?? "Cancel";

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
    public ICommand ConfirmScanCommand { get; }
    public ICommand CancelScanCommand { get; }

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
        ConfirmScanCommand = new RelayCommand(async () => await ConfirmScanAsync());
        CancelScanCommand = new RelayCommand(CancelScan);

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
        Raise(nameof(ScanWarningTitle));
        Raise(nameof(ScanWarningMessage));
        Raise(nameof(ScanWarningContinueText));
        Raise(nameof(ScanWarningCancelText));
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

        // First-scan warning (once, persisted in Setting)
        if (AppServices.Settings != null)
        {
            try
            {
                var warningShown = await AppServices.Settings.GetAsync("Scan.WarningShown", ct);
                if (warningShown != "true")
                {
                    _pendingScanFolders = folderList;
                    ShowScanWarning = true;
                    Log.Info("[LibraryViewModel] First scan -> showing warning dialog");
                    return;
                }
            }
            catch (Exception ex) { Log.Exception("[LibraryViewModel] read Scan.WarningShown failed", ex); }
        }

        await DoScanAsync(folderList, ct);
    }

    private async Task ConfirmScanAsync()
    {
        ShowScanWarning = false;
        if (AppServices.Settings != null)
        {
            try { await AppServices.Settings.SetAsync("Scan.WarningShown", "true"); } catch { }
        }
        var folders = _pendingScanFolders;
        _pendingScanFolders = new List<string>();
        if (folders.Count > 0)
        {
            Log.Info("[LibraryViewModel] Warning confirmed -> starting scan");
            await DoScanAsync(folders, CancellationToken.None);
        }
    }

    private void CancelScan()
    {
        ShowScanWarning = false;
        _pendingScanFolders = new List<string>();
        Log.Info("[LibraryViewModel] Warning cancelled -> scan not started");
    }

    private async Task DoScanAsync(List<string> folderList, CancellationToken ct)
    {
        IsBusy = true;
        SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Scanning") ?? "Scanning...");
        try
        {
            var progress = new Progress<ScanProgress>(p =>
            {
                var fmt = App.Loc?.Get("Library.ScanningProgress") ?? "Scanning: {0}/{1} (+{2}, ~{3}, ={4})";
                SetStatus(StatusState.Scanning, 0, string.Format(fmt, p.ProcessedFiles, p.TotalFiles, p.Added, p.Updated, p.Skipped));
            });
            await _scanner!.ScanAsync(folderList, progress, ct);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] DoScanAsync exception", ex); }
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
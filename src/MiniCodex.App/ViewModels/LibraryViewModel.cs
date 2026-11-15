using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Windows.Input;
using MiniCodex.Core.Logging;
using Avalonia.Threading;
using Avalonia.Media;
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
    private readonly ICollectionService? _collectionService;
    private readonly RelayCommand _deleteCollectionCommand;
    private bool _showSaveFilterDialog;
    private string _newCollectionName = string.Empty;
    private bool _showRenameTagDialog;
    private string _newTagName = string.Empty;
    private TagNodeViewModel? _renameTagTarget;
    private bool _showDeleteTagConfirm;
    private TagNodeViewModel? _deleteTagTarget;
    private string _deleteTagMessage = string.Empty;
    private bool _showColorPickerDialog;
    private string _newTagColor = "#E67E22";
    private TagNodeViewModel? _colorPickerTagTarget;

    // --- multi-select (0.5.6b.1) ---
    private int _lastClickedIndex = -1;
    private bool _showGroupTagDialog;
    private string _groupTagName = string.Empty;
    private bool _showGroupRemoveConfirm;
    private string _groupRemoveMessage = string.Empty;

    private readonly Dictionary<string, int> _tagDirectUsage = new(StringComparer.OrdinalIgnoreCase);

    private readonly SemaphoreSlim _previewSemaphore = new SemaphoreSlim(1, 1);
    private readonly SemaphoreSlim _loadSemaphore = new SemaphoreSlim(1, 1);
    private CancellationTokenSource _lifetimeCts = new CancellationTokenSource();
    

        public ObservableCollection<ModelCardViewModel> Cards { get; } = new();
    public ObservableCollection<TagNodeViewModel> Tags { get; } = new();
    public ObservableCollection<CollectionRow> Collections { get; } = new();
    public ObservableCollection<ModelCardViewModel> SelectedCards { get; } = new();
    public ObservableCollection<string> GroupTagCandidates { get; } = new();

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

    private TagNodeViewModel? _selectedTag;
    public TagNodeViewModel? SelectedTag
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

    private CollectionRow? _selectedCollection;
    public CollectionRow? SelectedCollection
    {
        get => _selectedCollection;
        set
        {
            if (Equals(_selectedCollection, value)) return;
            _selectedCollection = value;
            Raise();
            _deleteCollectionCommand?.RaiseCanExecuteChanged();
            if (value != null)
                _ = ApplyCollectionAsync(value);
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

        private string? FilterTagIds => string.IsNullOrEmpty(SelectedTag?.Id) ? null : GetDescendantIds(SelectedTag);

    private string GetDescendantIds(TagNodeViewModel node)
    {
        var ids = new List<string> { node.Id };
        foreach (var child in node.Children)
        {
            ids.AddRange(GetDescendantIds(child).Split(',', StringSplitOptions.RemoveEmptyEntries));
        }
        return string.Join(",", ids);
    }

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

        private bool _showDuplicatesOnly;
    public bool ShowDuplicatesOnly
    {
        get => _showDuplicatesOnly;
        set
        {
            if (_showDuplicatesOnly == value) return;
            _showDuplicatesOnly = value;
            Raise();
            Raise(nameof(DuplicatesButtonText));
            _ = ReloadModelsAsync(CancellationToken.None);
        }
    }

    public string DuplicatesButtonText => ShowDuplicatesOnly ? (App.Loc?.Get("Library.ShowAll") ?? "Show all") : (App.Loc?.Get("Library.FindDuplicates") ?? "Find duplicates");

    public bool ShowSaveFilterDialog
    {
        get => _showSaveFilterDialog;
        set { if (_showSaveFilterDialog == value) return; _showSaveFilterDialog = value; Raise(); }
    }
    public string NewCollectionName
    {
        get => _newCollectionName;
        set { if (_newCollectionName == value) return; _newCollectionName = value; Raise(); }
    }
    public string SaveFilterDialogTitle => App.Loc?.Get("Library.SaveFilterDialog.Title") ?? "Name your collection";
    public string SaveFilterDialogPlaceholder => App.Loc?.Get("Library.SaveFilterDialog.Placeholder") ?? "Collection name";
    public string SaveFilterDialogSaveText => App.Loc?.Get("Library.SaveFilterDialog.Save") ?? "Save";
    public string SaveFilterDialogCancelText => App.Loc?.Get("Library.SaveFilterDialog.Cancel") ?? "Cancel";

    public bool ShowRenameTagDialog
    {
        get => _showRenameTagDialog;
        set { if (_showRenameTagDialog == value) return; _showRenameTagDialog = value; Raise(); }
    }
    public string NewTagName
    {
        get => _newTagName;
        set { if (_newTagName == value) return; _newTagName = value; Raise(); }
    }
    public string RenameTagDialogTitle => App.Loc?.Get("Library.RenameTagDialog.Title") ?? "Rename tag";
    public string RenameTagDialogPlaceholder => App.Loc?.Get("Library.RenameTagDialog.Placeholder") ?? "Tag name";
    public string RenameTagDialogSaveText => App.Loc?.Get("Library.RenameTagDialog.Save") ?? "Save";
    public string RenameTagDialogCancelText => App.Loc?.Get("Library.RenameTagDialog.Cancel") ?? "Cancel";

    public bool ShowDeleteTagConfirm
    {
        get => _showDeleteTagConfirm;
        set { if (_showDeleteTagConfirm == value) return; _showDeleteTagConfirm = value; Raise(); }
    }
    public string DeleteTagMessage
    {
        get => _deleteTagMessage;
        private set { if (_deleteTagMessage == value) return; _deleteTagMessage = value; Raise(); }
    }
    public string DeleteTagDialogTitle => App.Loc?.Get("Library.DeleteTagDialog.Title") ?? "Delete tag?";
    public string DeleteTagDialogDeleteText => App.Loc?.Get("Library.DeleteTagDialog.Delete") ?? "Delete";
    public string DeleteTagDialogCancelText => App.Loc?.Get("Library.DeleteTagDialog.Cancel") ?? "Cancel";

    public bool ShowColorPickerDialog
    {
        get => _showColorPickerDialog;
        set { if (_showColorPickerDialog == value) return; _showColorPickerDialog = value; Raise(); }
    }
    public string NewTagColor
    {
        get => _newTagColor;
        set
        {
            if (_newTagColor == value) return;
            _newTagColor = value;
            Raise();
            Raise(nameof(ColorPreviewBrush));
        }
    }
    public IBrush? ColorPreviewBrush
    {
        get
        {
            if (string.IsNullOrWhiteSpace(_newTagColor)) return null;
            if (Avalonia.Media.Color.TryParse(_newTagColor, out var c)) return new SolidColorBrush(c);
            return null;
        }
    }
    public string ColorPickerTitle => App.Loc?.Get("Library.ColorPickerDialog.Title") ?? "Custom color";
    public string ColorPickerPlaceholder => App.Loc?.Get("Library.ColorPickerDialog.Placeholder") ?? "#RRGGBB";
    public string ColorPickerSaveText => App.Loc?.Get("Library.ColorPickerDialog.Save") ?? "Save";
    public string ColorPickerCancelText => App.Loc?.Get("Library.ColorPickerDialog.Cancel") ?? "Cancel";

    public ICommand ToggleDuplicatesCommand { get; }
    public ICommand RequestFocusSearchCommand { get; }
    public ICommand ConfirmScanCommand { get; }
    public ICommand CancelScanCommand { get; }
    public ICommand SaveCurrentFilterAsCollectionCommand { get; }
    public ICommand DeleteCollectionCommand => _deleteCollectionCommand;
    public ICommand ConfirmSaveFilterCommand { get; }
    public ICommand CancelSaveFilterCommand { get; }
    public ICommand ConfirmRenameTagCommand { get; }
    public ICommand CancelRenameTagCommand { get; }
    public ICommand ConfirmDeleteTagCommand { get; }
    public ICommand CancelDeleteTagCommand { get; }
    public ICommand ConfirmColorPickerCommand { get; }
    public ICommand CancelColorPickerCommand { get; }
    public ICommand ClearSelectionCommand { get; }
    public ICommand SelectAllVisibleCommand { get; }
    public ICommand GroupAddTagCommand { get; }
    public ICommand GroupRemoveCommand { get; }
    public ICommand GroupCopyPathsCommand { get; }
    public ICommand GroupFindDuplicatesCommand { get; }
    public ICommand ConfirmGroupTagCommand { get; }
    public ICommand CancelGroupTagCommand { get; }
    public ICommand ConfirmGroupRemoveCommand { get; }
    public ICommand CancelGroupRemoveCommand { get; }

    public LibraryViewModel(
        IModelRepository? models,
        IModelFileRepository? files,
        ScannerService? scanner,
        PreviewGenerator? previews,
        ITagService? tagService,
        IIntegrationService? integration,
        ICollectionService? collectionService = null)
    {
        _models = models; _files = files; _scanner = scanner; _previews = previews;
        _tagService = tagService;
        _integration = integration;
        _collectionService = collectionService;
        RequestFocusSearchCommand = new RelayCommand(() => FocusSearchRequested?.Invoke(this, EventArgs.Empty));
        ToggleDuplicatesCommand = new RelayCommand(() => ShowDuplicatesOnly = !ShowDuplicatesOnly);
        ConfirmScanCommand = new RelayCommand(async () => await ConfirmScanAsync());
        CancelScanCommand = new RelayCommand(CancelScan);
        SaveCurrentFilterAsCollectionCommand = new RelayCommand(() => OpenSaveFilterDialog());
        ConfirmSaveFilterCommand = new RelayCommand(() => _ = ConfirmSaveFilterAsync());
        CancelSaveFilterCommand = new RelayCommand(CancelSaveFilter);
        ConfirmRenameTagCommand = new RelayCommand(() => _ = ConfirmRenameTagAsync());
        CancelRenameTagCommand = new RelayCommand(() => { ShowRenameTagDialog = false; _renameTagTarget = null; });
        ConfirmDeleteTagCommand = new RelayCommand(() => _ = ConfirmDeleteTagAsync());
        CancelDeleteTagCommand = new RelayCommand(() => { ShowDeleteTagConfirm = false; _deleteTagTarget = null; });
        ConfirmColorPickerCommand = new RelayCommand(() => _ = ConfirmColorPickerAsync());
        CancelColorPickerCommand = new RelayCommand(CancelColorPicker);
        _deleteCollectionCommand = new RelayCommand(
            () => { if (SelectedCollection != null) _ = DeleteCollectionAsync(SelectedCollection); },
            () => SelectedCollection != null);

        // --- multi-select (0.5.6b.1) ---
        ClearSelectionCommand = new RelayCommand(ClearSelection);
        SelectAllVisibleCommand = new RelayCommand(SelectAllVisible);
        GroupAddTagCommand = new RelayCommand(() => OpenGroupAddTagDialog());
        GroupRemoveCommand = new RelayCommand(() => OpenGroupRemoveDialog());
        GroupCopyPathsCommand = new RelayCommand(() => _ = GroupCopyPathsAsync());
        GroupFindDuplicatesCommand = new RelayCommand(() => _ = GroupFindDuplicatesAsync());
        ConfirmGroupTagCommand = new RelayCommand(() => _ = GroupAddTagAsync());
        CancelGroupTagCommand = new RelayCommand(() => { ShowGroupTagDialog = false; GroupTagName = string.Empty; });
        ConfirmGroupRemoveCommand = new RelayCommand(() => _ = GroupRemoveAsync());
        CancelGroupRemoveCommand = new RelayCommand(() => { ShowGroupRemoveConfirm = false; });

        Log.Info("[LibraryViewModel] ctor Models=" + (models != null) + " Files=" + (files != null) +
                 " Scanner=" + (scanner != null) + " Previews=" + (previews != null));
    }

    public void RequestFocusSearch() => FocusSearchRequested?.Invoke(this, EventArgs.Empty);

    public string GroupSelectionStatusText => string.Format(GroupSelectionStatusFormat, SelectedCount);
    public string GroupClearText => App.Loc?.Get("Library.Group.Clear") ?? "Clear";

    private bool HasAnyModalOpen()
    {
        return _showScanWarning || _showSaveFilterDialog || _showRenameTagDialog
            || _showDeleteTagConfirm || _showColorPickerDialog
            || _showGroupTagDialog || _showGroupRemoveConfirm;
    }

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
        Raise(nameof(CollectionsHeader));
        Raise(nameof(SaveFilterButtonText));
        Raise(nameof(DeleteCollectionTooltip));
        foreach (var t in Tags) t.RefreshLocalized();
        foreach (var c in Cards) c.RefreshLocalized();
        Raise(nameof(GroupTagDialogTitle));
        Raise(nameof(GroupTagDialogPlaceholder));
        Raise(nameof(GroupTagDialogAddText));
        Raise(nameof(GroupTagDialogCancelText));
        Raise(nameof(GroupRemoveDialogTitle));
        Raise(nameof(GroupRemoveDialogRemoveText));
        Raise(nameof(GroupRemoveDialogCancelText));
        Raise(nameof(GroupAddTagMenuText));
        Raise(nameof(GroupRemoveMenuText));
        Raise(nameof(GroupCopyPathsMenuText));
        Raise(nameof(GroupFindDuplicatesMenuText));
        Raise(nameof(GroupSelectionStatusFormat));
        Raise(nameof(GroupSelectionStatusText));
        Raise(nameof(GroupClearText));
        UpdatePreviewsStatus();
    }

    // ============================================================
    // Multi-select (0.5.6b.1)
    // ============================================================
    public int SelectedCount => SelectedCards.Count;
    public bool HasSelection => SelectedCards.Count > 0;
    public bool IsMultiSelection => SelectedCards.Count > 1;

    public bool ShowGroupTagDialog
    {
        get => _showGroupTagDialog;
        set { if (_showGroupTagDialog == value) return; _showGroupTagDialog = value; Raise(); }
    }
    public string GroupTagName
    {
        get => _groupTagName;
        set { if (_groupTagName == value) return; _groupTagName = value; Raise(); }
    }
    public string GroupTagDialogTitle => App.Loc?.Get("Library.GroupTagDialog.Title") ?? "Add tag to selection";
    public string GroupTagDialogPlaceholder => App.Loc?.Get("Library.GroupTagDialog.Placeholder") ?? "Tag name";
    public string GroupTagDialogAddText => App.Loc?.Get("Library.GroupTagDialog.Add") ?? "Add";
    public string GroupTagDialogCancelText => App.Loc?.Get("Library.GroupTagDialog.Cancel") ?? "Cancel";

    public bool ShowGroupRemoveConfirm
    {
        get => _showGroupRemoveConfirm;
        set { if (_showGroupRemoveConfirm == value) return; _showGroupRemoveConfirm = value; Raise(); }
    }
    public string GroupRemoveMessage
    {
        get => _groupRemoveMessage;
        private set { if (_groupRemoveMessage == value) return; _groupRemoveMessage = value; Raise(); }
    }
    public string GroupRemoveDialogTitle => App.Loc?.Get("Library.GroupRemoveDialog.Title") ?? "Remove models?";
    public string GroupRemoveDialogRemoveText => App.Loc?.Get("Library.GroupRemoveDialog.Remove") ?? "Remove";
    public string GroupRemoveDialogCancelText => App.Loc?.Get("Library.GroupRemoveDialog.Cancel") ?? "Cancel";

    public string GroupAddTagMenuText => App.Loc?.Get("Library.Group.AddTag") ?? "Add tag to selected";
    public string GroupRemoveMenuText => App.Loc?.Get("Library.Group.Remove") ?? "Remove selected";
    public string GroupCopyPathsMenuText => App.Loc?.Get("Library.Group.CopyPaths") ?? "Copy paths of selected";
    public string GroupFindDuplicatesMenuText => App.Loc?.Get("Library.Group.FindDuplicates") ?? "Find duplicates in selection";
    public string GroupSelectionStatusFormat => App.Loc?.Get("Library.Group.SelectionCount") ?? "Selected: {0}";

    public void ClearSelection()
    {
        if (HasAnyModalOpen()) return;
        foreach (var c in Cards) c.IsSelected = false;
        _lastClickedIndex = -1;
        RefreshSelectionCollections();
    }

    public void SelectAllVisible()
    {
        if (HasAnyModalOpen()) return;
        foreach (var c in Cards) c.IsSelected = true;
        _lastClickedIndex = Cards.Count - 1;
        RefreshSelectionCollections();
    }

    // Public entry point for code-behind (0.5.6b.2): handles plain / Ctrl / Shift clicks.
    public void OnCardClicked(ModelCardViewModel card, bool isCtrl, bool isShift)
    {
        if (card == null) return;
        int idx = Cards.IndexOf(card);
        if (idx < 0) return;

        if (isShift && _lastClickedIndex >= 0 && _lastClickedIndex < Cards.Count)
        {
            var from = Math.Min(_lastClickedIndex, idx);
            var to = Math.Max(_lastClickedIndex, idx);
            foreach (var c in Cards) c.IsSelected = false;
            for (int i = from; i <= to; i++) Cards[i].IsSelected = true;
        }
        else if (isCtrl)
        {
            card.IsSelected = !card.IsSelected;
            _lastClickedIndex = idx;
        }
        else
        {
            foreach (var c in Cards) c.IsSelected = false;
            card.IsSelected = true;
            _lastClickedIndex = idx;
        }
        RefreshSelectionCollections();
    }

    private void OnCardClickedInternal(ModelCardViewModel card, bool isCtrl, bool isShift)
        => OnCardClicked(card, isCtrl, isShift);

    public void RefreshSelectionCollections()
    {
        SelectedCards.Clear();
        foreach (var c in Cards) if (c.IsSelected) SelectedCards.Add(c);
        Raise(nameof(SelectedCount));
        Raise(nameof(HasSelection));
        Raise(nameof(IsMultiSelection));
        Raise(nameof(GroupSelectionStatusText));
    }

    private void RefreshGroupTagCandidates()
    {
        GroupTagCandidates.Clear();
        void AddRec(TagNodeViewModel node)
        {
            if (!string.IsNullOrEmpty(node.Id)) GroupTagCandidates.Add(node.Name);
            foreach (var child in node.Children) AddRec(child);
        }
        foreach (var t in Tags) AddRec(t);
    }

    private void OpenGroupAddTagDialog()
    {
        if (SelectedCards.Count == 0) return;
        RefreshGroupTagCandidates();
        GroupTagName = string.Empty;
        ShowGroupTagDialog = true;
    }

    private async Task GroupAddTagAsync()
    {
        if (!ShowGroupTagDialog) return;
        if (_tagService == null || SelectedCards.Count == 0) return;
        var name = (_groupTagName ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(name)) return;
        try
        {
            int count = 0;
            foreach (var card in SelectedCards.ToList())
            {
                try { await _tagService.AddToModelAsync(card.Model.Id, name); count++; } catch { }
            }
            ShowGroupTagDialog = false;
            GroupTagName = string.Empty;
            var fmt = App.Loc?.Get("Library.Group.TagAppliedFormat") ?? "Applied tag to {0} models";
            SetStatus(StatusState.Scanning, 0, string.Format(fmt, count));
            await LoadTagsAsync(CancellationToken.None);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] GroupAddTag failed", ex); }
    }

    private void OpenGroupRemoveDialog()
    {
        if (SelectedCards.Count == 0) return;
        var fmt = App.Loc?.Get("Library.GroupRemoveDialog.Message") ?? "Remove {0} models from library? This cannot be undone.";
        GroupRemoveMessage = string.Format(fmt, SelectedCards.Count);
        ShowGroupRemoveConfirm = true;
    }

    private async Task GroupRemoveAsync()
    {
        if (!ShowGroupRemoveConfirm) return;
        if (_models == null || SelectedCards.Count == 0) return;
        var cards = SelectedCards.ToList();
        try
        {
            foreach (var card in cards)
            {
                try { await _models.DeleteAsync(card.Model.Id); } catch { }
            }
            foreach (var card in cards) Cards.Remove(card);
            ClearSelection();
            ShowGroupRemoveConfirm = false;
            SetStatus(Cards.Count == 0 ? StatusState.None : StatusState.ModelCount, Cards.Count);
            Raise(nameof(IsEmpty));
            await LoadTagsAsync(CancellationToken.None);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] GroupRemove failed", ex); }
    }

    private async Task GroupCopyPathsAsync()
    {
        if (_files == null || SelectedCards.Count == 0) return;
        var paths = new List<string>();
        foreach (var card in SelectedCards)
        {
            try
            {
                var fs = await _files.GetByModelAsync(card.Model.Id);
                var primary = fs.FirstOrDefault(f => f.Id == card.Model.PrimaryModelFileId) ?? fs.FirstOrDefault();
                if (primary?.Path != null) paths.Add(primary.Path);
            }
            catch { }
        }
        if (paths.Count == 0) return;
        try
        {
            if (Avalonia.Application.Current?.ApplicationLifetime is Avalonia.Controls.ApplicationLifetimes.IClassicDesktopStyleApplicationLifetime desktop
                && desktop.MainWindow?.Clipboard != null)
            {
                await desktop.MainWindow.Clipboard.SetTextAsync(string.Join(Environment.NewLine, paths));
                var fmt = App.Loc?.Get("Library.Group.CopiedFormat") ?? "Copied {0} paths";
                SetStatus(StatusState.Scanning, 0, string.Format(fmt, paths.Count));
            }
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] GroupCopyPaths failed", ex); }
    }

    private async Task GroupFindDuplicatesAsync()
    {
        if (_files == null || SelectedCards.Count == 0) return;
        var hashToModels = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var card in SelectedCards)
        {
            try
            {
                var fs = await _files.GetByModelAsync(card.Model.Id);
                foreach (var f in fs)
                {
                    if (string.IsNullOrEmpty(f.FileHash)) continue;
                    if (!hashToModels.TryGetValue(f.FileHash, out var list))
                    {
                        list = new List<string>();
                        hashToModels[f.FileHash] = list;
                    }
                    if (!list.Contains(card.Model.Id)) list.Add(card.Model.Id);
                }
            }
            catch { }
        }
        var dupIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var kv in hashToModels)
            if (kv.Value.Count > 1)
                foreach (var id in kv.Value) dupIds.Add(id);
        if (dupIds.Count == 0)
        {
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Group.NoDuplicates") ?? "No duplicates found in selection");
            return;
        }
        var toRemove = Cards.Where(c => !dupIds.Contains(c.Model.Id)).ToList();
        foreach (var c in toRemove) Cards.Remove(c);
        ClearSelection();
        SetStatus(StatusState.ModelCount, Cards.Count);
        Raise(nameof(IsEmpty));
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
            _selectedTag = null; // Reset filter to "All Models" on load
            await LoadTagsAsync(ct);
            await LoadCollectionsAsync(ct);
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
            
            var rootAll = new TagNodeViewModel { Id = "", Name = allLabel, UsageCount = allModels.Count };
            Tags.Add(rootAll);

            var dict = new Dictionary<string, TagNodeViewModel>();
            foreach (var t in tagUsages)
            {
                dict[t.Id] = new TagNodeViewModel
                {
                    Id = t.Id,
                    Name = t.Name,
                    ParentId = t.ParentId,
                    UsageCount = t.UsageCount,
                    Color = t.Color,
                    OnColorChange = (node, c) => _ = ChangeTagColorAsync(node, c),
                    OnRename = OpenRenameTagDialog,
                    OnDelete = OpenDeleteTagDialog,
                    OnCustomColor = OpenColorPickerDialog,
                };
            }

            foreach (var t in tagUsages)
            {
                if (!string.IsNullOrEmpty(t.ParentId) && dict.TryGetValue(t.ParentId, out var parent))
                {
                    parent.Children.Add(dict[t.Id]);
                }
                else
                {
                    Tags.Add(dict[t.Id]);
                }
            }

            _tagDirectUsage.Clear();
            foreach (var t in tagUsages) _tagDirectUsage[t.Id] = t.UsageCount;

            void SumUsage(TagNodeViewModel node)
            {
                int sum = node.UsageCount;
                foreach (var child in node.Children)
                {
                    SumUsage(child);
                    sum += child.UsageCount;
                }
                node.UsageCount = sum;
            }
            foreach (var t in Tags)
            {
                if (t.Id != "") SumUsage(t);
            }

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
        await _loadSemaphore.WaitAsync(ct);
        try
        {
            var models = await _models.SearchAsync(
                string.IsNullOrWhiteSpace(SearchQuery) ? null : SearchQuery,
                FilterTagIds, ct);

            if (ShowDuplicatesOnly)
            {
                var dupIds = await _models.GetDuplicateModelIdsAsync(ct);
                var dupSet = new HashSet<string>(dupIds);
                models = models.Where(m => dupSet.Contains(m.Id)).ToList();
            }

            Cards.Clear();
            _lastClickedIndex = -1;
            SelectedCards.Clear();
            Raise(nameof(SelectedCount));
            Raise(nameof(HasSelection));
            Raise(nameof(IsMultiSelection));
            PreviewsDone = 0;
            PreviewsTotal = models.Count;
            Log.Info("[LibraryViewModel] ReloadModels cards=" + models.Count);

            var lifetimeToken = _lifetimeCts.Token;
            foreach (var m in models)
            {
                var card = new ModelCardViewModel(m, OnOpenRequested, OnAddTagForModel, OnRemoveFromLibrary,
                    _integration, _hasSlicer, _hasEditor, OnCardClickedInternal);
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
                    catch (Exception ex) { Log.Exception("[LibraryViewModel] LoadDetails failed", ex); }
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
        catch (Exception ex)
        {
            Log.Exception("[LibraryViewModel] ReloadModelsCoreAsync failed", ex);
        }
        finally
        {
            _loadSemaphore.Release();
        }
    }

    public string CollectionsHeader => App.Loc?.Get("Library.CollectionsHeader") ?? "Collections";
    public string SaveFilterButtonText => App.Loc?.Get("Library.SaveFilterButton") ?? "Save filter";
    public string DeleteCollectionTooltip => App.Loc?.Get("Library.DeleteCollection") ?? "Delete collection";

    private async Task LoadCollectionsAsync(CancellationToken ct = default)
    {
        if (_collectionService == null) return;
        try
        {
            var all = await _collectionService.GetSmartAsync(ct);
            Collections.Clear();
            foreach (var c in all)
            {
                var row = CollectionRow.From(c);
                row.OnColorChange = (r, col) => _ = ChangeCollectionColorAsync(r, col);
                Collections.Add(row);
            }
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] LoadCollections failed", ex); }
    }

    private void OpenSaveFilterDialog()
    {
        var tag = _selectedTag;
        var filter = new SmartCollectionFilter(
            string.IsNullOrWhiteSpace(_searchQuery) ? null : _searchQuery.Trim(),
            string.IsNullOrEmpty(tag?.Id) ? null : tag!.Id,
            string.IsNullOrEmpty(tag?.Id) ? null : tag!.Name);
        if (filter.IsEmpty)
        {
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.SaveFilterEmpty") ?? "Filter is empty - set a search or a tag first.");
            return;
        }
        NewCollectionName = string.IsNullOrEmpty(tag?.Name)
            ? ("Filter " + DateTime.Now.ToString("HH:mm"))
            : tag!.Name;
        ShowSaveFilterDialog = true;
    }

    private async Task ConfirmSaveFilterAsync()
    {
        var name = NewCollectionName;
        ShowSaveFilterDialog = false;
        await SaveCurrentFilterAsync(name);
    }

    private void CancelSaveFilter()
    {
        ShowSaveFilterDialog = false;
    }

    public async Task SaveCurrentFilterAsync(string? name)
    {
        if (_collectionService == null) return;
        var tag = _selectedTag;
        var filter = new SmartCollectionFilter(
            string.IsNullOrWhiteSpace(_searchQuery) ? null : _searchQuery.Trim(),
            string.IsNullOrEmpty(tag?.Id) ? null : tag!.Id,
            string.IsNullOrEmpty(tag?.Id) ? null : tag!.Name);
        if (filter.IsEmpty)
        {
            SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.SaveFilterEmpty") ?? "Nothing to save: filter is empty.");
            return;
        }
        if (string.IsNullOrWhiteSpace(name))
            name = "Filter " + DateTime.Now.ToString("HH:mm:ss");
        try
        {
            await _collectionService.SaveSmartAsync(name.Trim(), filter);
            await LoadCollectionsAsync();
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] SaveCurrentFilterAsync failed", ex); }
    }

    public async Task DeleteCollectionAsync(CollectionRow row)
    {
        if (_collectionService == null || row == null) return;
        try
        {
            await _collectionService.DeleteAsync(row.Id);
            Collections.Remove(row);
            if (Equals(_selectedCollection, row)) _selectedCollection = null;
            Raise(nameof(SelectedCollection));
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] DeleteCollectionAsync failed", ex); }
    }

    public async Task ChangeCollectionColorAsync(CollectionRow row, string? color)
    {
        if (_collectionService == null || row == null || string.IsNullOrEmpty(row.Id)) return;
        try
        {
            await _collectionService.SetColorAsync(row.Id, color);
            row.Color = color;
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] ChangeCollectionColorAsync failed", ex); }
    }

    public async Task ChangeTagColorAsync(TagNodeViewModel tag, string? color)
    {
        if (_tagService == null || tag == null || string.IsNullOrEmpty(tag.Id)) return;
        try
        {
            await _tagService.SetColorAsync(tag.Id, color);
            tag.Color = color;
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] ChangeTagColorAsync failed", ex); }
    }

    private void OpenRenameTagDialog(TagNodeViewModel node)
    {
        if (node == null || string.IsNullOrEmpty(node.Id)) return;
        _renameTagTarget = node;
        NewTagName = node.Name;
        ShowRenameTagDialog = true;
    }

    private async Task ConfirmRenameTagAsync()
    {
        var target = _renameTagTarget;
        var name = NewTagName;
        ShowRenameTagDialog = false;
        _renameTagTarget = null;
        if (_tagService == null || target == null || string.IsNullOrEmpty(target.Id)) return;
        if (string.IsNullOrWhiteSpace(name)) return;
        try
        {
            await _tagService.RenameAsync(target.Id, name.Trim());
            await LoadTagsAsync(CancellationToken.None);
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] ConfirmRenameTagAsync failed", ex); }
    }

    private void OpenDeleteTagDialog(TagNodeViewModel node)
    {
        if (node == null || string.IsNullOrEmpty(node.Id)) return;
        _deleteTagTarget = node;
        int direct = _tagDirectUsage.TryGetValue(node.Id, out var d) ? d : node.UsageCount;
        int total = node.UsageCount;
        int descendantsOnly = Math.Max(0, total - direct);
        var fmt = App.Loc?.Get("Library.DeleteTagDialog.Message") ?? "Delete tag {0}? Directly tagged: {1}, in subtree (children): {2}.";
        DeleteTagMessage = string.Format(fmt, node.Name, direct, descendantsOnly);
        ShowDeleteTagConfirm = true;
    }

    private async Task ConfirmDeleteTagAsync()
    {
        var target = _deleteTagTarget;
        ShowDeleteTagConfirm = false;
        _deleteTagTarget = null;
        if (_tagService == null || target == null || string.IsNullOrEmpty(target.Id)) return;
        try
        {
            await _tagService.DeleteAsync(target.Id);
            await LoadTagsAsync(CancellationToken.None);
            if (SelectedTag == null && Tags.Count > 0)
                SelectedTag = Tags[0];
        }
        catch (Exception ex) { Log.Exception("[LibraryViewModel] ConfirmDeleteTagAsync failed", ex); }
    }

    private void OpenColorPickerDialog(TagNodeViewModel node)
    {
        if (node == null || string.IsNullOrEmpty(node.Id)) return;
        _colorPickerTagTarget = node;
        NewTagColor = string.IsNullOrWhiteSpace(node.Color) ? "#E67E22" : node.Color;
        ShowColorPickerDialog = true;
    }

    private async Task ConfirmColorPickerAsync()
    {
        var target = _colorPickerTagTarget;
        var color = NewTagColor;
        ShowColorPickerDialog = false;
        _colorPickerTagTarget = null;
        if (_tagService == null || target == null || string.IsNullOrEmpty(target.Id)) return;
        if (string.IsNullOrWhiteSpace(color)) return;

        if (!Avalonia.Media.Color.TryParse(color.Trim(), out _)) return;

        await ChangeTagColorAsync(target, color.Trim());
    }

    private void CancelColorPicker()
    {
        ShowColorPickerDialog = false;
        _colorPickerTagTarget = null;
    }

    private async Task ApplyCollectionAsync(CollectionRow row)
    {
        _suppressTagReload = true;
        try
        {
            _searchQuery = row.Filter.Search ?? string.Empty;
            Raise(nameof(SearchQuery));

            if (!string.IsNullOrEmpty(row.Filter.TagId))
                _selectedTag = FindTagById(row.Filter.TagId);
            else
                _selectedTag = Tags.FirstOrDefault();
            Raise(nameof(SelectedTag));
        }
        finally { _suppressTagReload = false; }

        await ReloadModelsAsync(CancellationToken.None);
    }

    private TagNodeViewModel? FindTagById(string id)
    {
        foreach (var root in Tags)
        {
            var f = FindTagByIdRec(root, id);
            if (f != null) return f;
        }
        return null;
    }

    private static TagNodeViewModel? FindTagByIdRec(TagNodeViewModel node, string id)
    {
        if (string.Equals(node.Id, id, StringComparison.Ordinal)) return node;
        foreach (var child in node.Children)
        {
            var f = FindTagByIdRec(child, id);
            if (f != null) return f;
        }
        return null;
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
            if (card != null)
            {
                Cards.Remove(card);
            }
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
        // Ignored: LibraryViewModel is a singleton owned by MainWindowViewModel.
        // It must survive navigation to/from model cards.
        Log.Info("[LibraryViewModel] DisposeAsync called, but ignored to keep singleton alive.");
        return ValueTask.CompletedTask;
    }
    public void ResetFilter()
{
    _showDuplicatesOnly = false;
    Raise(nameof(DuplicatesButtonText));
    _searchQuery = string.Empty;
    Raise(nameof(SearchQuery));
    _selectedTag = null;
    Raise(nameof(SelectedTag));
    _ = ReloadModelsAsync(CancellationToken.None);
}
        public async Task ForceShowAllAsync()
    {
        _searchQuery = string.Empty;
        Raise(nameof(SearchQuery));
        _selectedTag = Tags.FirstOrDefault(t => string.IsNullOrEmpty(t.Id));
        Raise(nameof(SelectedTag));
        await ReloadModelsCoreAsync(CancellationToken.None);
    }
}
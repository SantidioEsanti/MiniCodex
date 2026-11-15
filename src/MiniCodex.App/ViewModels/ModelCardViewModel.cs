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

    // --- multi-select (0.5.6b.1) ---
    private bool _isSelected;
    public bool IsSelected
    {
        get => _isSelected;
        set { if (_isSelected != value) { _isSelected = value; Raise(); } }
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
    private readonly Action<ModelCardViewModel, bool, bool>? _onClick;
    private readonly IIntegrationService? _integration;

    public ModelCardViewModel(
        Model model,
        Action<Model> onOpen,
        Action<Model> onAddTag,
        Action<Model> onRemoveFromLibrary,
        IIntegrationService? integration,
        bool hasSlicer,
        bool hasEditor,
        Action<ModelCardViewModel, bool, bool>? onClick = null)
    {
        Model = model;
        _onOpen = onOpen;
        _onAddTag = onAddTag;
        _onRemoveFromLibrary = onRemoveFromLibrary;
        _integration = integration;
        _onClick = onClick;
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

    // 0.5.6b.2: click plumbing (LibraryView passes ctrl/shift + this card)
    public void HandleClick(bool isCtrl, bool isShift) => _onClick?.Invoke(this, isCtrl, isShift);

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
                    catch (Exception ex) { MiniCodex.Core.Logging.Log.Exception("[ModelCard] Failed to load preview: " + path, ex); }
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
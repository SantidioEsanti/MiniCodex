#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.1a - Hover-panel, Quick Actions, rotation (ASCII-safe).
.DESCRIPTION
    Fix of 0.4.1 (PS 5.1 failed on non-ASCII in UTF-8 without BOM).
    Pure ASCII script; Russian strings injected via base64 at runtime.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.1a'
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

function Decode-B64 {
    param([string]$b64)
    if ([string]::IsNullOrEmpty($b64)) { return '' }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
}

$Files = @{}

# ============ App/Services/FileSystemHelper.cs ============
$Files['src\MiniCodex.App\Services\FileSystemHelper.cs'] = @'
using System.Diagnostics;
using System.Runtime.Versioning;

namespace MiniCodex.App.Services;

[SupportedOSPlatform("windows")]
public static class FileSystemHelper
{
    public static void ShowInExplorer(string path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"/select,\"{path}\"",
                UseShellExecute = true,
            });
        }
        catch { }
    }
}
'@

# ============ App/ViewModels/ModelCardViewModel.cs ============
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

            var results = await previews.EnsurePreviewsAsync(Model.Id, primary.Path, Model.UpdatedAt, ct);
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

# ============ App/Views/ModelCardTile.axaml ============
$Files['src\MiniCodex.App\Views\ModelCardTile.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.ModelCardTile"
             x:DataType="vm:ModelCardViewModel">
    <Border Width="220" Height="260" Margin="6"
            BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
            BorderThickness="1" CornerRadius="6" Padding="6">
        <Border.ContextMenu>
            <ContextMenu>
                <MenuItem Header="{Binding ContextMenuOpenCard}" Command="{Binding OpenCommand}"/>
                <MenuItem Header="{Binding ContextMenuCopyPath}" Command="{Binding CopyPathCommand}"/>
                <MenuItem Header="{Binding ContextMenuAddTag}" Command="{Binding AddTagCommand}"/>
                <MenuItem Header="{Binding QuickActionShowInFolder}" Command="{Binding ShowInFolderCommand}"/>
                <Separator/>
                <MenuItem Header="{Binding QuickActionToSlicer}" Command="{Binding ToSlicerCommand}" IsEnabled="{Binding CanOpenInSlicer}"/>
                <MenuItem Header="{Binding QuickActionToEditor}" Command="{Binding ToEditorCommand}" IsEnabled="{Binding CanOpenInEditor}"/>
                <Separator/>
                <MenuItem Header="{Binding ContextMenuRemoveFromLibrary}" Command="{Binding RemoveFromLibraryCommand}"/>
            </ContextMenu>
        </Border.ContextMenu>
        <Grid RowDefinitions="180,*,Auto">
            <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}" CornerRadius="4">
                <Image Source="{Binding PreviewImage}" Stretch="Uniform" Margin="4"/>
            </Border>

            <Border Grid.Row="0" VerticalAlignment="Bottom" IsVisible="{Binding IsHovered}"
                    Background="#A0000000" CornerRadius="0,0,4,4" Padding="6,3">
                <StackPanel Orientation="Horizontal" Spacing="8">
                    <TextBlock Text="{Binding TotalSizeText}" Foreground="White" FontSize="10"/>
                    <TextBlock Text="{Binding PolygonsText}" Foreground="White" FontSize="10"/>
                    <TextBlock Text="{Binding FileCountText}" Foreground="#D0D0D0" FontSize="10"
                               IsVisible="{Binding HasMultipleFiles}"/>
                </StackPanel>
            </Border>

            <Button Grid.Row="0"
                    HorizontalAlignment="Right" VerticalAlignment="Top"
                    Margin="4" Padding="6,0" MinWidth="26" MinHeight="26"
                    Content="&#x22EF;"
                    ToolTip.Tip="{Binding MoreActionsTooltip}"
                    IsVisible="{Binding IsHovered}">
                <Button.Flyout>
                    <MenuFlyout Placement="BottomEdgeAlignedRight">
                        <MenuItem Header="{Binding ContextMenuOpenCard}" Command="{Binding OpenCommand}"/>
                        <MenuItem Header="{Binding ContextMenuCopyPath}" Command="{Binding CopyPathCommand}"/>
                        <MenuItem Header="{Binding ContextMenuAddTag}" Command="{Binding AddTagCommand}"/>
                        <MenuItem Header="{Binding QuickActionShowInFolder}" Command="{Binding ShowInFolderCommand}"/>
                        <Separator/>
                        <MenuItem Header="{Binding QuickActionToSlicer}" Command="{Binding ToSlicerCommand}" IsEnabled="{Binding CanOpenInSlicer}"/>
                        <MenuItem Header="{Binding QuickActionToEditor}" Command="{Binding ToEditorCommand}" IsEnabled="{Binding CanOpenInEditor}"/>
                        <Separator/>
                        <MenuItem Header="{Binding ContextMenuRemoveFromLibrary}" Command="{Binding RemoveFromLibraryCommand}"/>
                    </MenuFlyout>
                </Button.Flyout>
            </Button>

            <TextBlock Grid.Row="1" Text="{Binding Title}"
                       FontWeight="Bold" TextTrimming="CharacterEllipsis"
                       Margin="0,6,0,0"/>
            <TextBlock Grid.Row="2" FontSize="11"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                       Text="{Binding StatusText}"/>
        </Grid>
    </Border>
</UserControl>
'@

# ============ App/Views/ModelCardTile.axaml.cs ============
$Files['src\MiniCodex.App\Views\ModelCardTile.axaml.cs'] = @'
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class ModelCardTile : UserControl
{
    public ModelCardTile()
    {
        InitializeComponent();
    }

    protected override void OnPointerEntered(PointerEventArgs e)
    {
        base.OnPointerEntered(e);
        if (DataContext is ModelCardViewModel vm)
            vm.IsHovered = true;
    }

    protected override void OnPointerExited(PointerEventArgs e)
    {
        base.OnPointerExited(e);
        if (DataContext is ModelCardViewModel vm)
            vm.IsHovered = false;
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        if (DataContext is not ModelCardViewModel vm) return;
        if (!vm.IsHovered || !vm.HasRotation) return;

        var pos = e.GetPosition(this);
        var width = Bounds.Width;
        if (width <= 0) return;

        var relative = Math.Clamp(pos.X / width, 0.0, 0.9999);
        var index = (int)(relative * 4);
        vm.RotateTo(index);
    }
}
'@

# ============ App/ViewModels/LibraryViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\LibraryViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
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
        catch { }
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
        catch { }
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
        if (_scanner == null || _models == null || _files == null || _previews == null) return;
        IsBusy = true;
        SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Scanning") ?? "Scanning...");
        try
        {
            var progress = new Progress<ScanProgress>(p =>
            {
                var fmt = App.Loc?.Get("Library.ScanningProgress") ?? "Scanning: {0}/{1} (+{2}, ~{3}, ={4})";
                SetStatus(StatusState.Scanning, 0, string.Format(fmt, p.ProcessedFiles, p.TotalFiles, p.Added, p.Updated, p.Skipped));
            });
            await _scanner.ScanAsync(folders, progress, ct);
        }
        finally
        {
            await LoadTagsAsync(ct);
            await ReloadModelsCoreAsync(ct);
            IsBusy = false;
        }
    }

    private void OnOpenRequested(Model m) => OpenCardRequested?.Invoke(this, m);
    private void OnAddTagForModel(Model m) => OpenCardWithTabRequested?.Invoke(this, (m, 3));

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
        catch { }
    }
}
'@

# ============ App/ViewModels/MainWindowViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\MainWindowViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
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
            Raise(nameof(LibraryButtonText));
            Raise(nameof(SettingsButtonText));
            Library.RefreshLocalized();
            (CurrentPage as ModelCardPageViewModel)?.RefreshLocalized();
            (CurrentPage as SettingsViewModel)?.RefreshLocalized();
        }
    }

    private string _theme = "auto";
    public string CurrentTheme
    {
        get => _theme;
        set { if (Set(ref _theme, value)) App.Theme.Apply(value); }
    }

    public string Title => App.Loc.Get("App.Name");
    public string LibraryButtonText => App.Loc.Get("Menu.Library");
    public string SettingsButtonText => App.Loc.Get("Menu.Settings");

    public LibraryViewModel Library { get; }

    private object? _currentPage;
    public object? CurrentPage
    {
        get => _currentPage;
        private set { _currentPage = value; Raise(); }
    }

    public ICommand RequestFocusSearchCommand { get; }
    public ICommand ShowLibraryCommand { get; }
    public ICommand ShowSettingsCommand { get; }

    public MainWindowViewModel()
    {
        Library = new LibraryViewModel(
            AppServices.Models,
            AppServices.ModelFiles,
            AppServices.Scanner,
            AppServices.PreviewGenerator,
            AppServices.TagService,
            AppServices.IntegrationService);
        Library.OpenCardRequested += OnOpenCard;
        Library.OpenCardWithTabRequested += OnOpenCardWithTab;
        CurrentPage = Library;

        RequestFocusSearchCommand = new RelayCommand(() =>
        {
            if (CurrentPage is LibraryViewModel lib) lib.RequestFocusSearch();
        });
        ShowLibraryCommand = new RelayCommand(() => CurrentPage = Library);
        ShowSettingsCommand = new RelayCommand(() =>
        {
            var vm = new SettingsViewModel();
            CurrentPage = vm;
            _ = vm.LoadAsync();
        });
    }

    private void OnOpenCard(object? sender, Model model) => OpenCardInternal(model, 0);
    private void OnOpenCardWithTab(object? sender, (Model model, int tabIndex) args) => OpenCardInternal(args.model, args.tabIndex);

    private void OpenCardInternal(Model model, int tabIndex)
    {
        if (AppServices.Models == null || AppServices.ModelFiles == null) return;
        var page = new ModelCardPageViewModel(model, AppServices.Models, AppServices.ModelFiles,
            onBack: () => CurrentPage = Library)
        {
            SelectedTabIndex = tabIndex
        };
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

# ============ App/Views/LibraryView.axaml ============
$Files['src\MiniCodex.App\Views\LibraryView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             x:Class="MiniCodex.App.Views.LibraryView"
             x:DataType="vm:LibraryViewModel">
    <Grid ColumnDefinitions="200,*">
        <Border Grid.Column="0"
                BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
                BorderThickness="0,0,1,0" Padding="4">
            <Grid RowDefinitions="Auto,*">
                <TextBlock Grid.Row="0" Text="{Binding TagsHeader}" FontWeight="Bold" Margin="6,4,6,8"/>
                <ListBox Grid.Row="1" ItemsSource="{Binding Tags}" SelectedItem="{Binding SelectedTag}">
                    <ListBox.ItemTemplate>
                        <DataTemplate>
                            <Grid ColumnDefinitions="*,Auto">
                                <TextBlock Text="{Binding Name}" TextTrimming="CharacterEllipsis"/>
                                <TextBlock Grid.Column="1" Text="{Binding UsageCount}"
                                           Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                           FontSize="11" Margin="6,0,0,0"/>
                            </Grid>
                        </DataTemplate>
                    </ListBox.ItemTemplate>
                </ListBox>
            </Grid>
        </Border>

        <Grid Grid.Column="1" RowDefinitions="Auto,*">
            <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="8" Margin="8">
                <TextBox x:Name="SearchBox" Text="{Binding SearchQuery}"
                         Watermark="{Binding SearchPlaceholder}" Width="300" VerticalAlignment="Center"/>
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
                        <DataTemplate DataType="vm:ModelCardViewModel">
                            <views:ModelCardTile/>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
            </ScrollViewer>

            <TextBlock Grid.Row="1" Text="{Binding EmptyStateText}"
                       HorizontalAlignment="Center" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                       IsVisible="{Binding IsEmpty}"/>
        </Grid>
    </Grid>
</UserControl>
'@

# ============ README (ASCII-only) ============
$Files['patches\0.4.1a\README.md'] = @'
# Patch 0.4.1a - Hover-panel, Quick Actions, rotation

**Iteration:** 0.4

Fixes 0.4.1 (PS 5.1 parser error from non-ASCII chars in UTF-8 without BOM).
This script is pure ASCII; Russian strings are injected via base64 at runtime.

## What it does

- Hover-panel on each card: total size, polygon count, file count (if >1).
- Rotation on hover: horizontal mouse movement switches the 4 preview angles.
- Context menu (right-click + "..." button):
  - Open card, Copy path, Add tag (opens card on Tags tab), Show in folder
  - To slicer / To editor (first available)
  - Remove from library (DB only, files NOT touched)
- New files: ModelCardTile.axaml(.cs), FileSystemHelper.cs.
- Updated: ModelCardViewModel, LibraryViewModel, MainWindowViewModel, LibraryView.axaml.
- New lang keys: Library.Hover.PolygonsFormat, Library.Hover.FilesFormat, Library.MoreActions.

## Deferred to 0.4.1b

- Del key (needs card selection model).
- Grid virtualization.

## DoD

- dotnet build: 0 errors.
- dotnet test: 40/40.
- Hover on card: metadata strip at bottom, "..." at top-right.
- Horizontal mouse movement: preview rotates.
- Right-click: context menu works.
- Remove from library: card disappears, files on disk stay.
'@

# ============ Main ============
try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.App\ViewModels\ModelCardViewModel.cs',
        'src\MiniCodex.App\ViewModels\LibraryViewModel.cs',
        'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs',
        'src\MiniCodex.App\Views\LibraryView.axaml',
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

    # --- lang/en.json: add 3 keys, pure ASCII ---
    $enPath = Join-Path $ProjectRoot 'lang\en.json'
    if (Test-Path $enPath) {
        $enContent = [IO.File]::ReadAllText($enPath, [Text.Encoding]::UTF8)
        if ($enContent -notmatch '"PolygonsFormat"') {
            $enContent = $enContent -replace '("Hover"\s*:\s*\{)', "`$1`r`n      `"PolygonsFormat`": `"{0:N0} tris`",`r`n      `"FilesFormat`": `"{0} files`","
        }
        if ($enContent -notmatch '"MoreActions"') {
            $enContent = $enContent -replace '("AllModels"\s*:\s*"[^"]*",)', "`$1`r`n    `"MoreActions`": `"More...`","
        }
        [IO.File]::WriteAllText($enPath, $enContent, [Text.UTF8Encoding]::new($false))
        Write-Log "updated: lang\en.json"
    }

    # --- lang/ru.json: decode Cyrillic from base64 at runtime ---
    $ruPath = Join-Path $ProjectRoot 'lang\ru.json'
    if (Test-Path $ruPath) {
        $ruPolygonsFmt = Decode-B64 'ezA6TjB9INC/0L7Qu9C40LPQvtC90L7Qsg=='
        $ruFilesFmt    = Decode-B64 'ezB9INGE0LDQudC70L7Qsg=='
        $ruMore        = Decode-B64 '0JXRidGR4oCm'

        $ruJson = [IO.File]::ReadAllText($ruPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not ($ruJson.Library.Hover.PSObject.Properties.Name -contains 'PolygonsFormat')) {
            $ruJson.Library.Hover | Add-Member -NotePropertyName 'PolygonsFormat' -NotePropertyValue $ruPolygonsFmt -Force
        }
        if (-not ($ruJson.Library.Hover.PSObject.Properties.Name -contains 'FilesFormat')) {
            $ruJson.Library.Hover | Add-Member -NotePropertyName 'FilesFormat' -NotePropertyValue $ruFilesFmt -Force
        }
        if (-not ($ruJson.Library.PSObject.Properties.Name -contains 'MoreActions')) {
            $ruJson.Library | Add-Member -NotePropertyName 'MoreActions' -NotePropertyValue $ruMore -Force
        }

        $outRu = $ruJson | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($ruPath, $outRu, [Text.UTF8Encoding]::new($false))
        Write-Log "updated: lang\ru.json"
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.1a applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.1a] - 2026-11-10`r`n`r`n### Added`r`n- Hover-panel with metadata, rotation on hover.`r`n- Context menu + More (...) button.`r`n- Quick Actions: To slicer, To editor, Show in folder.`r`n- Copy path, Add tag (opens card on Tags tab), Remove from library.`r`n`r`n### Fixed`r`n- ASCII-only .ps1 (fixes 0.4.1 PS 5.1 parser error).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.0d\].*)$', "$entry`$1"
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
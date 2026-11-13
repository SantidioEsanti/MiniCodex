#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.3.0b — фикс инверсии вращения + локализация карточки модели.
.DESCRIPTION
    ThreeDViewer: _yaw += dx (было -=).
    Card page: все строки через App.Loc + RefreshLocalized + bindings.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.3.0b'
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

# ============ ThreeDViewer.axaml ============
$Files['src\MiniCodex.App\Views\ThreeDViewer.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             x:Class="MiniCodex.App.Views.ThreeDViewer">
    <Grid>
        <Border Background="#E0E0E0" CornerRadius="4">
            <Image x:Name="PreviewHost" Stretch="Uniform"/>
        </Border>
        <TextBlock Text="{Binding ThreeDStatusText}"
                   IsVisible="{Binding ThreeDStatusVisible}"
                   HorizontalAlignment="Center" VerticalAlignment="Center"
                   Foreground="#666" FontSize="14"/>
    </Grid>
</UserControl>
'@

# ============ ThreeDViewer.axaml.cs ============
$Files['src\MiniCodex.App\Views\ThreeDViewer.axaml.cs'] = @'
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using MiniCodex.App.ViewModels;
using MiniCodex.Core.Models;
using MiniCodex.Render.Loaders;
using MiniCodex.Render.Rendering;

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

    private void SetViewState(ThreeDViewState state, string? error = null)
    {
        if (DataContext is ModelCardPageViewModel vm)
        {
            vm.ThreeDViewState = state;
            vm.ThreeDErrorMessage = error;
        }
    }

    private async Task LoadGeometryAsync(string? path)
    {
        _geometry = null;
        PreviewHost.Source = null;

        if (string.IsNullOrEmpty(path))
        {
            SetViewState(ThreeDViewState.FileNotChosen);
            return;
        }

        SetViewState(ThreeDViewState.Loading);
        try
        {
            var geo = await Task.Run(() => _loader.LoadGeometry(path));
            if (geo == null)
            {
                SetViewState(ThreeDViewState.ParseFailed);
                return;
            }
            _geometry = geo;
            SetViewState(ThreeDViewState.Loaded);
            RequestRender();
        }
        catch (Exception ex)
        {
            SetViewState(ThreeDViewState.Error, ex.Message);
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
        _yaw += dx * 0.5f;
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

# ============ ModelCardPageViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs'] = @'
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
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

    // ---------- ThreeD state ----------
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

    // ---------- Save status ----------
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

    // ---------- Localized labels (computed) ----------
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
    public string AssociationsPlaceholder => Loc("Card.Placeholder.AssociationsSoon", "Associations — coming in 0.3.1");
    public string TagsPlaceholder => Loc("Card.Placeholder.TagsSoon", "Tags — coming in 0.3.2");

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
        Raise(nameof(AssociationsPlaceholder));
        Raise(nameof(TagsPlaceholder));
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

    private static string? NullIfEmpty(string s) => string.IsNullOrWhiteSpace(s) ? null : s;

    private static string Loc(string key, string fallback)
        => App.Loc?.Get(key) ?? fallback;
}
'@

# ============ MainWindowViewModel.cs — RefreshLocalized для карточки ============
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
            (CurrentPage as ModelCardPageViewModel)?.RefreshLocalized();
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

# ============ ModelCardView.axaml — все строки через bindings ============
$Files['src\MiniCodex.App\Views\ModelCardView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             x:Class="MiniCodex.App.Views.ModelCardView">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Orientation="Horizontal" Spacing="8" Margin="8">
            <Button Content="{Binding BackButtonText}" Command="{Binding GoBackCommand}"/>
            <Button Content="{Binding SaveButtonText}" Command="{Binding SaveCommand}"/>
            <TextBlock Text="{Binding SaveStatusText}" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
        </StackPanel>

        <Grid Grid.Row="1" ColumnDefinitions="480,*" Margin="8,0,8,8">
            <views:ThreeDViewer Grid.Column="0" MeshFilePath="{Binding MeshFilePath}" Margin="0,0,8,0"/>

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
                                                 Command="{Binding $parent[UserControl].((vm:ModelCardPageViewModel)DataContext).SetPrimaryCommand}"
                                                 CommandParameter="{Binding}"
                                                 GroupName="PrimaryFile"
                                                 xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"/>
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
                    <TextBlock Text="{Binding AssociationsPlaceholder}"
                               HorizontalAlignment="Center" VerticalAlignment="Center"
                               Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
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

# ============ lang/en.json ============
$Files['lang\en.json'] = @'
{
  "App": {
    "Name": "MiniCodex",
    "Version": "0.0.0",
    "Tagline": "Portable 3D model library"
  },
  "Menu": {
    "Library": "Library",
    "Settings": "Settings",
    "About": "About"
  },
  "Common": {
    "Ok": "OK",
    "Cancel": "Cancel",
    "Save": "Save",
    "Delete": "Delete",
    "Close": "Close",
    "Browse": "Browse…",
    "Loading": "Loading…",
    "Error": "Error",
    "Warning": "Warning"
  },
  "Settings": {
    "Title": "Settings",
    "Section": {
      "Sources": "Source folders",
      "AssetsRoot": "Associations root",
      "Integrations": "Slicers & editors",
      "Appearance": "Appearance",
      "Database": "Database"
    },
    "Theme": {
      "Label": "Theme",
      "Light": "Light",
      "Dark": "Dark",
      "Auto": "Auto"
    },
    "Language": {
      "Label": "Language",
      "Ru": "Русский",
      "En": "English"
    },
    "LowDiskSpace": "Less than 500 MB free on the data drive."
  },
  "Library": {
    "Title": "Library",
    "SearchPlaceholder": "Search by name, tag, author, source…",
    "Empty": "No models yet. Click “Scan folder”.",
    "ScanButton": "Scan folder",
    "ScanFolderTitle": "Select source folder",
    "Loading": "Loading library…",
    "ModelsCount": "Models: {0}",
    "Scanning": "Scanning…",
    "ScanningProgress": "Scanning: {0}/{1} (+{2}, ~{3}, ={4})",
    "ServicesNotInitialized": "Services not initialized.",
    "Hover": {
      "TotalSize": "Total size",
      "Polygons": "Polygons",
      "Files": "Files",
      "Status": "Status"
    },
    "Status": {
      "Planned": "Planned",
      "Printed": "Printed",
      "Painted": "Painted"
    },
    "QuickActions": {
      "ToSlicer": "To slicer",
      "ToEditor": "To editor",
      "ShowInFolder": "Show in folder"
    },
    "ContextMenu": {
      "CopyPath": "Copy path",
      "RemoveFromLibrary": "Remove from library",
      "AddTag": "Add tag",
      "OpenCard": "Open card"
    }
  },
  "Card": {
    "Tabs": {
      "Info": "Info",
      "Files": "Files",
      "Associations": "Associations",
      "Tags": "Tags",
      "Notes": "Notes",
      "Scale": "Scale"
    },
    "Actions": {
      "Back": "← Back",
      "Save": "Save",
      "Orient": "Orient",
      "RegeneratePreviews": "Regenerate previews",
      "OpenInSlicer": "Open in slicer",
      "OpenInEditor": "Open in editor",
      "ShowInFolder": "Show in folder"
    },
    "Fields": {
      "Title": "Title",
      "Author": "Author",
      "SourceUrl": "Source URL",
      "Status": "Status",
      "Difficulty": "Paint difficulty",
      "Notes": "Notes",
      "RealHeightMm": "Prototype real height (mm)",
      "ModelHeightMm": "Model height (mm)",
      "Scale": "Target scale",
      "PrototypeType": "Prototype type"
    },
    "FileRole": {
      "Main": "Main",
      "Part": "Part",
      "Presupported": "Pre-supported",
      "Hollowed": "Hollowed",
      "Variant": "Variant",
      "Accessory": "Accessory"
    },
    "AssetType": {
      "Reference": "Reference",
      "Render": "Render",
      "Photo": "Photo",
      "Document": "Document",
      "Profile": "Print profile"
    },
    "Status": {
      "Saved": "Saved",
      "ErrorPrefix": "Error: "
    },
    "Placeholder": {
      "AssociationsSoon": "Associations — coming in 0.3.1",
      "TagsSoon": "Tags — coming in 0.3.2"
    },
    "ThreeD": {
      "Loading": "Loading 3D…",
      "FileNotChosen": "No model file selected",
      "ParseFailed": "Failed to parse model",
      "ErrorPrefix": "Error: "
    },
    "RemoveFromCard": "Remove from card"
  },
  "About": {
    "Title": "About",
    "License": "Licensed under MIT.",
    "Support": "Support the author"
  },
  "Error": {
    "ParseFailed": "Failed to parse mesh file",
    "FolderUnavailable": "Source folder is unavailable"
  }
}
'@

# ============ lang/ru.json ============
$Files['lang\ru.json'] = @'
{
  "App": {
    "Name": "MiniCodex",
    "Version": "0.0.0",
    "Tagline": "Portable-библиотека 3D-моделей"
  },
  "Menu": {
    "Library": "Библиотека",
    "Settings": "Настройки",
    "About": "О программе"
  },
  "Common": {
    "Ok": "ОК",
    "Cancel": "Отмена",
    "Save": "Сохранить",
    "Delete": "Удалить",
    "Close": "Закрыть",
    "Browse": "Обзор…",
    "Loading": "Загрузка…",
    "Error": "Ошибка",
    "Warning": "Предупреждение"
  },
  "Settings": {
    "Title": "Настройки",
    "Section": {
      "Sources": "Папки-источники",
      "AssetsRoot": "Корень ассоциаций",
      "Integrations": "Слайсеры и редакторы",
      "Appearance": "Внешний вид",
      "Database": "База данных"
    },
    "Theme": {
      "Label": "Тема",
      "Light": "Светлая",
      "Dark": "Тёмная",
      "Auto": "Авто"
    },
    "Language": {
      "Label": "Язык",
      "Ru": "Русский",
      "En": "English"
    },
    "LowDiskSpace": "Свободно менее 500 МБ на диске с данными."
  },
  "Library": {
    "Title": "Библиотека",
    "SearchPlaceholder": "Поиск по имени, тегу, автору, источнику…",
    "Empty": "Пока нет моделей. Нажмите «Сканировать папку».",
    "ScanButton": "Сканировать папку",
    "ScanFolderTitle": "Выберите папку-источник",
    "Loading": "Загрузка библиотеки…",
    "ModelsCount": "Моделей: {0}",
    "Scanning": "Сканирование…",
    "ScanningProgress": "Сканирование: {0}/{1} (+{2}, ~{3}, ={4})",
    "ServicesNotInitialized": "Сервисы не инициализированы.",
    "Hover": {
      "TotalSize": "Общий размер",
      "Polygons": "Полигоны",
      "Files": "Файлы",
      "Status": "Статус"
    },
    "Status": {
      "Planned": "В планах",
      "Printed": "Напечатано",
      "Painted": "Покрашено"
    },
    "QuickActions": {
      "ToSlicer": "В слайсер",
      "ToEditor": "В редактор",
      "ShowInFolder": "В папке"
    },
    "ContextMenu": {
      "CopyPath": "Копировать путь",
      "RemoveFromLibrary": "Удалить из библиотеки",
      "AddTag": "Добавить тег",
      "OpenCard": "Открыть карточку"
    }
  },
  "Card": {
    "Tabs": {
      "Info": "Инфо",
      "Files": "Файлы",
      "Associations": "Ассоциации",
      "Tags": "Теги",
      "Notes": "Заметки",
      "Scale": "Масштаб"
    },
    "Actions": {
      "Back": "← Назад",
      "Save": "Сохранить",
      "Orient": "Ориентировать",
      "RegeneratePreviews": "Перегенерировать превью",
      "OpenInSlicer": "Открыть в слайсере",
      "OpenInEditor": "Открыть в редакторе",
      "ShowInFolder": "Показать в папке"
    },
    "Fields": {
      "Title": "Название",
      "Author": "Автор",
      "SourceUrl": "Источник (URL)",
      "Status": "Статус",
      "Difficulty": "Сложность покраса",
      "Notes": "Заметки",
      "RealHeightMm": "Реальная высота прототипа (мм)",
      "ModelHeightMm": "Высота модели (мм)",
      "Scale": "Целевой масштаб",
      "PrototypeType": "Тип прототипа"
    },
    "FileRole": {
      "Main": "Основной",
      "Part": "Часть",
      "Presupported": "Pre-supported",
      "Hollowed": "Полый",
      "Variant": "Вариант",
      "Accessory": "Аксессуар"
    },
    "AssetType": {
      "Reference": "Референс",
      "Render": "Рендер",
      "Photo": "Фото готовой работы",
      "Document": "Документ",
      "Profile": "Профиль печати"
    },
    "Status": {
      "Saved": "Сохранено",
      "ErrorPrefix": "Ошибка: "
    },
    "Placeholder": {
      "AssociationsSoon": "Ассоциации — в патче 0.3.1",
      "TagsSoon": "Теги — в патче 0.3.2"
    },
    "ThreeD": {
      "Loading": "Загрузка 3D…",
      "FileNotChosen": "Файл модели не выбран",
      "ParseFailed": "Не удалось разобрать модель",
      "ErrorPrefix": "Ошибка: "
    },
    "RemoveFromCard": "Убрать из карточки"
  },
  "About": {
    "Title": "О программе",
    "License": "Лицензия MIT.",
    "Support": "Поддержать автора"
  },
  "Error": {
    "ParseFailed": "Не удалось разобрать файл модели",
    "FolderUnavailable": "Папка-источник недоступна"
  }
}
'@

# ============ README ============
$Files['patches\0.3.0b\README.md'] = @'
# Патч 0.3.0b — фикс инверсии вращения + локализация карточки

**Итерация:** 0.3 · **Статус:** реализован

## Причины

1. **Горизонтальное вращение мышью инвертировано.** `_yaw -= dx` — при движении мыши
   вправо модель поворачивалась влево. По вертикали было `_pitch += dy` (правильно).
2. **Карточка модели не локализовалась.** Все строки («← Назад», «Сохранить»,
   заголовки вкладок, метки полей, «Сохранено», «Загрузка 3D…», «Файл модели не выбран»)
   были захардкожены по-русски.

## Что делает

- `ThreeDViewer.OnPointerMoved`: `_yaw += dx * 0.5f` (симметрично с pitch).
- `ThreeDViewer` больше не пишет в `StatusLabel` напрямую — через `DataContext`
  выставляет `ThreeDViewState` на `ModelCardPageViewModel`; текст — binding на `ThreeDStatusText`.
- `ModelCardPageViewModel`: `ThreeDViewState`, `ThreeDErrorMessage`, `SaveState`,
  `SaveErrorMessage` + computed `ThreeDStatusText`, `ThreeDStatusVisible`,
  `SaveStatusText`, `BackButtonText`, `SaveButtonText`, `Tab*Header`, `Label*`,
  `AssociationsPlaceholder`, `TagsPlaceholder`, `RefreshLocalized()`.
- `MainWindowViewModel.CurrentLanguage.set`: дополнительно вызывает
  `(CurrentPage as ModelCardPageViewModel)?.RefreshLocalized()`.
- `ModelCardView.axaml`: все строки → `{Binding ...}`.
- `lang/en.json` + `lang/ru.json`: новые ключи `Card.Actions.Back`, `Card.Actions.Save`,
  `Card.Status.Saved`, `Card.Status.ErrorPrefix`, `Card.Placeholder.*`, `Card.ThreeD.*`.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.0b\patch_0.3.0b.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24/24.
- Горизонтальный drag вращает модель в сторону движения мыши.
- Переключение языка `ru`→`en` мгновенно меняет все надписи на карточке: «← Back»,
  «Save», «Info/Files/Associations/Tags/Notes», «Title/Author/Source URL/...»
- Если 3D в состоянии «Файл не выбран» — текст тоже переключается.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.App\Views\ThreeDViewer.axaml',
        'src\MiniCodex.App\Views\ThreeDViewer.axaml.cs',
        'src\MiniCodex.App\Views\ModelCardView.axaml',
        'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs',
        'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs',
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

    # CHANGELOG
    $marker = '<!-- patch 0.3.0b applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Fixed`n- 0.3.0b: горизонтальное вращение 3D-вьюера больше не инвертировано.`n- 0.3.0b: карточка модели локализуется при смене языка (RU/EN).`n"
            $cl = $cl -replace '(?m)^(## \[0\.3\.0a\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.3.0b.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}
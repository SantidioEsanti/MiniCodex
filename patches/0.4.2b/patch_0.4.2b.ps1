#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.2b - "Regenerate previews" button + library tile auto-refresh.
.DESCRIPTION
    Full rewrite: ModelCardPageViewModel, ModelCardView.axaml.
    Targeted string.Replace: MainWindowViewModel (event sub + handler), LibraryViewModel (method).
    JSON surgery: lang/en.json, lang/ru.json (2 new keys).
    ASCII-only.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.2b'
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

# ============ ModelCardPageViewModel.cs (full rewrite) ============
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
    public event EventHandler<string>? PreviewsRegenerated;

    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private readonly IModelRepository _models;
    private readonly IModelFileRepository _files;
    private readonly Action _onBack;

    public Model Model { get; }

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

    public ObservableCollection<ModelFileRowViewModel> FileRows { get; } = new();

    private string? _meshFilePath;
    public string? MeshFilePath
    {
        get => _meshFilePath;
        set { _meshFilePath = value; Raise(); Raise(nameof(CanLaunch)); Raise(nameof(CanRegeneratePreviews)); }
    }

    private int _selectedTabIndex;
    public int SelectedTabIndex { get => _selectedTabIndex; set { _selectedTabIndex = value; Raise(); } }

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

    // ---------- Orientation (TwoWay) ----------
    private float _viewerYaw = 180f;
    public float ViewerYaw
    {
        get => _viewerYaw;
        set { if (Math.Abs(_viewerYaw - value) > 0.001f) { _viewerYaw = value; Raise(); } }
    }

    private float _viewerPitch = 15f;
    public float ViewerPitch
    {
        get => _viewerPitch;
        set { if (Math.Abs(_viewerPitch - value) > 0.001f) { _viewerPitch = value; Raise(); } }
    }

    private string _orientationStatusText = string.Empty;
    public string OrientationStatusText
    {
        get => _orientationStatusText;
        private set { _orientationStatusText = value; Raise(); }
    }

    private bool _isRegenerating;
    public bool IsRegenerating
    {
        get => _isRegenerating;
        private set { _isRegenerating = value; Raise(); Raise(nameof(CanRegeneratePreviews)); }
    }

    public bool CanRegeneratePreviews => !_isRegenerating && !string.IsNullOrEmpty(MeshFilePath);

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
        ThreeDViewState.Loading => Loc("Card.ThreeD.Loading", "Loading 3D..."),
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
    public string BackButtonText => Loc("Card.Actions.Back", "\u2190 Back");
    public string SaveButtonText => Loc("Card.Actions.Save", "Save");
    public string ResetOrientationText => Loc("Card.Actions.ResetOrientation", "Reset");
    public string SaveOrientationText => Loc("Card.Actions.SaveOrientation", "Save orientation");
    public string RegeneratePreviewsText => Loc("Card.Actions.RegeneratePreviews", "Regenerate previews");
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

    public string AddFileButtonText => Loc("Card.Assoc.AddFile", "Add file");
    public string AutoLinkButtonText => Loc("Card.Assoc.AutoLink", "Auto-link");
    public string DropHintText => Loc("Card.Assoc.DropHint", "Drop files here to attach");
    public string RemoveAssetText => Loc("Card.Assoc.Remove", "Remove");
    public string AssetStatusText { get; private set; } = string.Empty;

    public string TagPlaceholderText => Loc("Card.Tags.Placeholder", "Enter tag...");
    public string AddTagButtonText => Loc("Card.Tags.Add", "Add");
    public string EmptyTagsText => Loc("Card.Tags.Empty", "No tags yet");

    public string SlicerLabel => Loc("Card.Launch.SlicerLabel", "Slicer:");
    public string EditorLabel => Loc("Card.Launch.EditorLabel", "Editor:");
    public string OpenInSlicerText => Loc("Card.Launch.OpenInSlicer", "Open in slicer");
    public string OpenInEditorText => Loc("Card.Launch.OpenInEditor", "Open in editor");
    public string NoSlicerText => Loc("Card.Launch.NoSlicer", "No slicers configured (Settings)");
    public string NoEditorText => Loc("Card.Launch.NoEditor", "No editors configured (Settings)");

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

    public ObservableCollection<TagRowViewModel> TagRows { get; } = new();
    private string _newTagName = string.Empty;
    public string NewTagName { get => _newTagName; set { _newTagName = value; Raise(); } }

    public ObservableCollection<IntegrationApp> AvailableSlicers { get; } = new();
    public ObservableCollection<IntegrationApp> AvailableEditors { get; } = new();

    private IntegrationApp? _selectedSlicer;
    public IntegrationApp? SelectedSlicer { get => _selectedSlicer; set { _selectedSlicer = value; Raise(); Raise(nameof(CanLaunchSlicer)); } }

    private IntegrationApp? _selectedEditor;
    public IntegrationApp? SelectedEditor { get => _selectedEditor; set { _selectedEditor = value; Raise(); Raise(nameof(CanLaunchEditor)); } }

    public bool HasSlicers => AvailableSlicers.Count > 0;
    public bool HasEditors => AvailableEditors.Count > 0;
    public bool HasAnyIntegration => HasSlicers || HasEditors;
    public bool CanLaunchSlicer => SelectedSlicer != null && !string.IsNullOrEmpty(MeshFilePath);
    public bool CanLaunchEditor => SelectedEditor != null && !string.IsNullOrEmpty(MeshFilePath);
    public bool CanLaunch => !string.IsNullOrEmpty(MeshFilePath);

    public ICommand SaveCommand { get; }
    public ICommand GoBackCommand { get; }
    public ICommand SetPrimaryCommand { get; }
    public ICommand AutoLinkCommand { get; }
    public ICommand AddTagCommand { get; }
    public ICommand LaunchInSlicerCommand { get; }
    public ICommand LaunchInEditorCommand { get; }
    public ICommand SaveOrientationCommand { get; }
    public ICommand ResetOrientationCommand { get; }
    public ICommand RegeneratePreviewsCommand { get; }

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
        AddTagCommand = new RelayCommand(async () => await AddTagAsync());
        LaunchInSlicerCommand = new RelayCommand(async () => await LaunchAsync(SelectedSlicer));
        LaunchInEditorCommand = new RelayCommand(async () => await LaunchAsync(SelectedEditor));
        SaveOrientationCommand = new RelayCommand(async () => await SaveOrientationAsync());
        ResetOrientationCommand = new RelayCommand(ResetOrientation);
        RegeneratePreviewsCommand = new RelayCommand(async () => await RegeneratePreviewsAsync());
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        var orientation = ModelOrientation.Parse(Model.OrientationJson);
        _viewerYaw = orientation.Yaw;
        _viewerPitch = orientation.Pitch;
        Raise(nameof(ViewerYaw));
        Raise(nameof(ViewerPitch));

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
        await ReloadTagsAsync(ct);
        await ReloadIntegrationsAsync(ct);
    }

    private async Task SaveOrientationAsync()
    {
        try
        {
            var o = new ModelOrientation { Yaw = ViewerYaw, Pitch = ViewerPitch };
            Model.OrientationJson = o.Serialize();
            await _models.UpsertAsync(Model);
            OrientationStatusText = Loc("Card.Orientation.Saved", "Orientation saved");
        }
        catch (Exception ex)
        {
            OrientationStatusText = Loc("Card.Status.ErrorPrefix", "Error: ") + ex.Message;
        }
    }

    private void ResetOrientation()
    {
        ViewerYaw = 180f;
        ViewerPitch = 15f;
        OrientationStatusText = string.Empty;
    }

    private async Task RegeneratePreviewsAsync()
    {
        if (AppServices.PreviewGenerator == null) return;
        if (string.IsNullOrEmpty(MeshFilePath)) return;
        if (IsRegenerating) return;

        try
        {
            IsRegenerating = true;
            OrientationStatusText = Loc("Card.Status.Regenerating", "Regenerating...");

            // Persist current orientation so cache uses it.
            var o = new ModelOrientation { Yaw = ViewerYaw, Pitch = ViewerPitch };
            Model.OrientationJson = o.Serialize();
            await _models.UpsertAsync(Model);

            var yawOff = ViewerYaw - 180f;
            var pitchOff = ViewerPitch - 15f;

            await AppServices.PreviewGenerator.EnsurePreviewsAsync(
                Model.Id, MeshFilePath, Model.UpdatedAt, yawOff, pitchOff, true);

            OrientationStatusText = Loc("Card.Status.Regenerated", "Previews updated");
            PreviewsRegenerated?.Invoke(this, Model.Id);
        }
        catch (Exception ex)
        {
            OrientationStatusText = Loc("Card.Status.ErrorPrefix", "Error: ") + ex.Message;
        }
        finally
        {
            IsRegenerating = false;
        }
    }

    private async Task ReloadIntegrationsAsync(CancellationToken ct)
    {
        if (AppServices.IntegrationService == null) return;
        try
        {
            var apps = await AppServices.IntegrationService.GetAppsAsync(ct);
            AvailableSlicers.Clear();
            AvailableEditors.Clear();
            foreach (var a in apps)
            {
                if (!a.IsAvailable) continue;
                if (a.Kind == IntegrationAppKind.Slicer) AvailableSlicers.Add(a);
                else AvailableEditors.Add(a);
            }
            SelectedSlicer = AvailableSlicers.FirstOrDefault();
            SelectedEditor = AvailableEditors.FirstOrDefault();
            Raise(nameof(HasSlicers));
            Raise(nameof(HasEditors));
            Raise(nameof(HasAnyIntegration));
            Raise(nameof(CanLaunchSlicer));
            Raise(nameof(CanLaunchEditor));
        }
        catch { }
    }

    private async Task LaunchAsync(IntegrationApp? app)
    {
        if (app == null || string.IsNullOrEmpty(MeshFilePath)) return;
        if (AppServices.IntegrationService == null) return;
        await AppServices.IntegrationService.LaunchAsync(app.Id, MeshFilePath);
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
                try { using var stream = File.OpenRead(path); row.SetThumbnail(new Bitmap(stream)); }
                catch { }
            });
        }
        catch { }
    }

    private void RebuildFilteredAssets()
    {
        FilteredAssets.Clear();
        foreach (var r in AssetRows)
            if (_selectedAssetFilter == "all" || r.Asset.AssetType == _selectedAssetFilter)
                FilteredAssets.Add(r);
    }

    private void SetAssetStatus(string text) { AssetStatusText = text; Raise(nameof(AssetStatusText)); }

    public async Task ImportAssetsAsync(IEnumerable<string> sourcePaths)
    {
        if (AppServices.AssetService == null) return;
        var count = 0;
        foreach (var p in sourcePaths)
        {
            try { await AppServices.AssetService.ImportAsync(Model.Id, p, SelectedAssetType); count++; }
            catch { }
        }
        SetAssetStatus(string.Format(Loc("Card.Assoc.Imported", "Imported: {0}"), count));
        await ReloadAssetsAsync(CancellationToken.None);
    }

    private async Task AutoLinkAsync()
    {
        if (AppServices.AssetService == null) return;
        SetAssetStatus(Loc("Card.Assoc.AutoLinkRunning", "Searching..."));
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

    private async Task ReloadTagsAsync(CancellationToken ct)
    {
        if (AppServices.TagService == null) return;
        try
        {
            TagRows.Clear();
            var tags = await AppServices.TagService.GetTagsForModelAsync(Model.Id, ct);
            foreach (var t in tags) TagRows.Add(new TagRowViewModel(t, OnRemoveTagAsync));
        }
        catch { }
    }

    private async Task AddTagAsync()
    {
        if (AppServices.TagService == null) return;
        if (string.IsNullOrWhiteSpace(NewTagName)) return;
        try
        {
            await AppServices.TagService.AddToModelAsync(Model.Id, NewTagName.Trim());
            NewTagName = string.Empty;
            await ReloadTagsAsync(CancellationToken.None);
        }
        catch { }
    }

    private async Task OnRemoveTagAsync(TagRowViewModel row)
    {
        if (AppServices.TagService == null) return;
        try { await AppServices.TagService.RemoveFromModelAsync(Model.Id, row.Tag.Id); TagRows.Remove(row); }
        catch { }
    }

    public void RefreshLocalized()
    {
        Raise(nameof(BackButtonText));
        Raise(nameof(SaveButtonText));
        Raise(nameof(ResetOrientationText));
        Raise(nameof(SaveOrientationText));
        Raise(nameof(RegeneratePreviewsText));
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
        Raise(nameof(AddFileButtonText));
        Raise(nameof(AutoLinkButtonText));
        Raise(nameof(DropHintText));
        Raise(nameof(RemoveAssetText));
        Raise(nameof(TagPlaceholderText));
        Raise(nameof(AddTagButtonText));
        Raise(nameof(EmptyTagsText));
        Raise(nameof(SlicerLabel));
        Raise(nameof(EditorLabel));
        Raise(nameof(OpenInSlicerText));
        Raise(nameof(OpenInEditorText));
        Raise(nameof(NoSlicerText));
        Raise(nameof(NoEditorText));
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
        catch (Exception ex) { SaveErrorMessage = ex.Message; SaveState = SaveState.Error; }
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

# ============ ModelCardView.axaml (full rewrite: + Regenerate button) ============
$Files['src\MiniCodex.App\Views\ModelCardView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.ModelCardView"
             x:DataType="vm:ModelCardPageViewModel">
    <Grid RowDefinitions="Auto,Auto,*">
        <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="8" Margin="8">
            <Button Content="{Binding BackButtonText}" Command="{Binding GoBackCommand}"/>
            <Button Content="{Binding SaveButtonText}" Command="{Binding SaveCommand}"/>
            <TextBlock Text="{Binding SaveStatusText}" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
            <Button Content="{Binding ResetOrientationText}" Command="{Binding ResetOrientationCommand}"/>
            <Button Content="{Binding SaveOrientationText}" Command="{Binding SaveOrientationCommand}"/>
            <Button Content="{Binding RegeneratePreviewsText}" Command="{Binding RegeneratePreviewsCommand}"
                    IsEnabled="{Binding CanRegeneratePreviews}"/>
            <TextBlock Text="{Binding OrientationStatusText}" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
            <TextBlock Text="{Binding LabelMinLambert}" VerticalAlignment="Center" Margin="12,0,4,0"/>
            <Slider Value="{Binding MinLambertValue}" Minimum="0" Maximum="1" Width="100" VerticalAlignment="Center"/>
            <CheckBox Content="{Binding LabelWireframe}" IsChecked="{Binding WireframeMode}" VerticalAlignment="Center"/>
        </StackPanel>

        <StackPanel Grid.Row="1" Orientation="Horizontal" Spacing="8" Margin="8,0,8,4" IsVisible="{Binding HasAnyIntegration}">
            <TextBlock Text="{Binding SlicerLabel}" VerticalAlignment="Center"/>
            <ComboBox ItemsSource="{Binding AvailableSlicers}" SelectedItem="{Binding SelectedSlicer}"
                      DisplayMemberBinding="{Binding DisplayName}" Width="180" IsVisible="{Binding HasSlicers}"/>
            <Button Content="{Binding OpenInSlicerText}" Command="{Binding LaunchInSlicerCommand}"
                    IsEnabled="{Binding CanLaunchSlicer}" IsVisible="{Binding HasSlicers}"/>
            <TextBlock Text="{Binding NoSlicerText}" VerticalAlignment="Center" Foreground="#888"
                       IsVisible="{Binding !HasSlicers}"/>
            <TextBlock Text="{Binding EditorLabel}" VerticalAlignment="Center" Margin="16,0,0,0"/>
            <ComboBox ItemsSource="{Binding AvailableEditors}" SelectedItem="{Binding SelectedEditor}"
                      DisplayMemberBinding="{Binding DisplayName}" Width="180" IsVisible="{Binding HasEditors}"/>
            <Button Content="{Binding OpenInEditorText}" Command="{Binding LaunchInEditorCommand}"
                    IsEnabled="{Binding CanLaunchEditor}" IsVisible="{Binding HasEditors}"/>
            <TextBlock Text="{Binding NoEditorText}" VerticalAlignment="Center" Foreground="#888"
                       IsVisible="{Binding !HasEditors}"/>
        </StackPanel>

        <Grid Grid.Row="2" ColumnDefinitions="480,*" Margin="8,0,8,8">
            <views:ThreeDViewer Grid.Column="0"
                                MeshFilePath="{Binding MeshFilePath}"
                                MinLambert="{Binding MinLambertValue}"
                                Wireframe="{Binding WireframeMode}"
                                Yaw="{Binding ViewerYaw, Mode=TwoWay}"
                                Pitch="{Binding ViewerPitch, Mode=TwoWay}"
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
                                    <TextBlock Grid.Column="1" Text="{Binding DisplayName}" VerticalAlignment="Center" Margin="6,0"/>
                                    <TextBlock Grid.Column="2" Text="{Binding RoleText}" VerticalAlignment="Center" Width="80"/>
                                    <TextBlock Grid.Column="3" Text="{Binding SizeText}" VerticalAlignment="Center" Width="80"/>
                                    <TextBlock Grid.Column="4" Text="{Binding PolygonsText}" VerticalAlignment="Center" Width="80"/>
                                </Grid>
                            </DataTemplate>
                        </ListBox.ItemTemplate>
                    </ListBox>
                </TabItem>

                <TabItem Header="{Binding TabAssociationsHeader}">
                    <Grid RowDefinitions="Auto,Auto,*">
                        <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="6" Margin="6">
                            <ComboBox ItemsSource="{Binding AssetTypeChoices}" SelectedItem="{Binding SelectedAssetType}" Width="110"/>
                            <Button Content="{Binding AddFileButtonText}" Click="OnAddFileClick"/>
                            <Button Content="{Binding AutoLinkButtonText}" Command="{Binding AutoLinkCommand}"/>
                            <ComboBox ItemsSource="{Binding AssetFilterChoices}" SelectedItem="{Binding SelectedAssetFilter}" Width="110" Margin="12,0,0,0"/>
                            <TextBlock Text="{Binding AssetStatusText}" VerticalAlignment="Center" Margin="8,0,0,0"
                                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                        </StackPanel>
                        <Border Grid.Row="1" Margin="6" Padding="8" MinHeight="60"
                                BorderThickness="1" BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
                                CornerRadius="6" Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                DragDrop.AllowDrop="True">
                            <TextBlock Text="{Binding DropHintText}" HorizontalAlignment="Center" VerticalAlignment="Center"
                                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                        </Border>
                        <ScrollViewer Grid.Row="2">
                            <ItemsControl ItemsSource="{Binding FilteredAssets}" Margin="6">
                                <ItemsControl.ItemsPanel>
                                    <ItemsPanelTemplate><WrapPanel Orientation="Horizontal"/></ItemsPanelTemplate>
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
                                                    <Button Grid.Column="1" Content="&#x00D7;" Command="{Binding RemoveCommand}"
                                                            Padding="6,0" MinWidth="24"/>
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
                    <Grid RowDefinitions="Auto,*">
                        <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="6" Margin="8">
                            <TextBox Text="{Binding NewTagName}" Watermark="{Binding TagPlaceholderText}" Width="200"/>
                            <Button Content="{Binding AddTagButtonText}" Command="{Binding AddTagCommand}"/>
                        </StackPanel>
                        <ScrollViewer Grid.Row="1">
                            <ItemsControl ItemsSource="{Binding TagRows}" Margin="8">
                                <ItemsControl.ItemsPanel>
                                    <ItemsPanelTemplate><WrapPanel Orientation="Horizontal"/></ItemsPanelTemplate>
                                </ItemsControl.ItemsPanel>
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                CornerRadius="12" Padding="8,2" Margin="4">
                                            <StackPanel Orientation="Horizontal" Spacing="4">
                                                <TextBlock Text="{Binding Name}" VerticalAlignment="Center"/>
                                                <Button Content="&#x00D7;" Command="{Binding RemoveCommand}"
                                                        Padding="4,0" MinWidth="20" MinHeight="20"
                                                        Background="Transparent" BorderThickness="0"/>
                                            </StackPanel>
                                        </Border>
                                    </DataTemplate>
                                </ItemsControl.ItemTemplate>
                            </ItemsControl>
                        </ScrollViewer>
                    </Grid>
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

# ============ README ============
$Files['patches\0.4.2b\README.md'] = @'
# Patch 0.4.2b - Regenerate previews button + tile auto-refresh

**Iteration:** 0.4

## What it does

- ModelCardPageViewModel:
  - RegeneratePreviewsCommand: saves current orientation, force-regenerates 4 PNGs, raises PreviewsRegenerated(modelId).
  - IsRegenerating / CanRegeneratePreviews: button disabled during work or if no primary file.
  - Status feedback: "Regenerating..." -> "Previews updated" (uses OrientationStatusText).
- ModelCardView: "Regenerate previews" button after "Save orientation".
- MainWindowViewModel: subscribes to PreviewsRegenerated and calls Library.OnPreviewsRegeneratedAsync(modelId).
- LibraryViewModel.OnPreviewsRegeneratedAsync: finds card by id, calls ReloadPreviewsAsync.
- lang/en.json + lang/ru.json: Card.Status.Regenerating, Card.Status.Regenerated.

## Effect

User flow: open card -> rotate -> "Save orientation" -> "Regenerate previews" -> back to library.
Tile in library now shows the new angle without restart or rescan.

## DoD

- dotnet build: 0 errors.
- dotnet test: 40/40.
- Save orientation, regenerate, back: tile shows new angle.
- Button disabled while regenerating (fast on small meshes, visible on large).
'@

# ============ Main ============
try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs',
        'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs',
        'src\MiniCodex.App\ViewModels\LibraryViewModel.cs',
        'src\MiniCodex.App\Views\ModelCardView.axaml',
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

    # ============ MainWindowViewModel.cs (targeted edits) ============
    $mwPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs'
    $mw = [IO.File]::ReadAllText($mwPath, [Text.Encoding]::UTF8)
    if ($mw -notmatch 'OnPreviewsRegenerated') {
        # Subscribe after card is created
        $mw = $mw.Replace(
            '        CurrentPage = page;' + "`r`n" + '        _ = page.LoadAsync();',
            '        page.PreviewsRegenerated += OnPreviewsRegenerated;' + "`r`n" +
            '        CurrentPage = page;' + "`r`n" +
            '        _ = page.LoadAsync();'
        )
        # Insert handler before Set<T>
        $marker = '    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)'
        $insert = '    private async void OnPreviewsRegenerated(object? sender, string modelId)' + "`r`n" +
                  '    {' + "`r`n" +
                  '        await Library.OnPreviewsRegeneratedAsync(modelId);' + "`r`n" +
                  '    }' + "`r`n" + "`r`n" + $marker
        if ($mw.Contains($marker)) {
            $mw = $mw.Replace($marker, $insert)
            [IO.File]::WriteAllText($mwPath, $mw, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: src\MiniCodex.App\ViewModels\MainWindowViewModel.cs (event sub + handler)'
        } else {
            Write-Log 'MainWindowViewModel.cs: marker Set<T> not found - MANUAL EDIT NEEDED.' 'WARN'
        }
    } else {
        Write-Log 'MainWindowViewModel.cs: OnPreviewsRegenerated already present, skipping.' 'WARN'
    }

    # ============ LibraryViewModel.cs (targeted edit) ============
    $libPath = Join-Path $ProjectRoot 'src\MiniCodex.App\ViewModels\LibraryViewModel.cs'
    $lib = [IO.File]::ReadAllText($libPath, [Text.Encoding]::UTF8)
    if ($lib -notmatch 'OnPreviewsRegeneratedAsync') {
        $marker = '    private void OnOpenRequested(Model m) => OpenCardRequested?.Invoke(this, m);'
        $insert = '    public async Task OnPreviewsRegeneratedAsync(string modelId)' + "`r`n" +
                  '    {' + "`r`n" +
                  '        if (_files == null || _previews == null) return;' + "`r`n" +
                  '        var card = Cards.FirstOrDefault(c => c.Model.Id == modelId);' + "`r`n" +
                  '        if (card == null) return;' + "`r`n" +
                  '        await card.ReloadPreviewsAsync(_files, _previews);' + "`r`n" +
                  '    }' + "`r`n" + "`r`n" + $marker
        if ($lib.Contains($marker)) {
            $lib = $lib.Replace($marker, $insert)
            [IO.File]::WriteAllText($libPath, $lib, [Text.UTF8Encoding]::new($false))
            Write-Log 'updated: src\MiniCodex.App\ViewModels\LibraryViewModel.cs (OnPreviewsRegeneratedAsync)'
        } else {
            Write-Log 'LibraryViewModel.cs: marker OnOpenRequested not found - MANUAL EDIT NEEDED.' 'WARN'
        }
    } else {
        Write-Log 'LibraryViewModel.cs: OnPreviewsRegeneratedAsync already present, skipping.' 'WARN'
    }

    # ============ lang/en.json ============
    $enPath = Join-Path $ProjectRoot 'lang\en.json'
    if (Test-Path $enPath) {
        $en = [IO.File]::ReadAllText($enPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not ($en.Card.Status.PSObject.Properties.Name -contains 'Regenerating')) {
            $en.Card.Status | Add-Member -NotePropertyName 'Regenerating' -NotePropertyValue 'Regenerating...' -Force
        }
        if (-not ($en.Card.Status.PSObject.Properties.Name -contains 'Regenerated')) {
            $en.Card.Status | Add-Member -NotePropertyName 'Regenerated' -NotePropertyValue 'Previews updated' -Force
        }
        if (-not ($en.Card.Actions.PSObject.Properties.Name -contains 'RegeneratePreviews')) {
            $en.Card.Actions | Add-Member -NotePropertyName 'RegeneratePreviews' -NotePropertyValue 'Regenerate previews' -Force
        }
        $outEn = $en | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($enPath, $outEn, [Text.UTF8Encoding]::new($false))
        Write-Log "updated: lang\en.json"
    }

    # ============ lang/ru.json (char-array strings, ASCII-safe) ============
    $ruPath = Join-Path $ProjectRoot 'lang\ru.json'
    if (Test-Path $ruPath) {
        $ru = [IO.File]::ReadAllText($ruPath, [Text.Encoding]::UTF8) | ConvertFrom-Json

        $ruRegenerating = -join ((0x041E,0x0431,0x043D,0x043E,0x0432,0x043B,0x0435,0x043D,0x0438,0x0435,0x002E,0x002E,0x002E) | ForEach-Object { [char]$_ })
        $ruRegenerated  = -join ((0x041F,0x0440,0x0435,0x0432,0x044C,0x044E,0x0020,0x043E,0x0431,0x043D,0x043E,0x0432,0x043B,0x0435,0x043D,0x044B) | ForEach-Object { [char]$_ })
        $ruRegenerateText = -join ((0x041E,0x0431,0x043D,0x043E,0x0432,0x0438,0x0442,0x044C,0x0020,0x043F,0x0440,0x0435,0x0432,0x044C,0x044E) | ForEach-Object { [char]$_ })

        if (-not ($ru.Card.Status.PSObject.Properties.Name -contains 'Regenerating')) {
            $ru.Card.Status | Add-Member -NotePropertyName 'Regenerating' -NotePropertyValue $ruRegenerating -Force
        }
        if (-not ($ru.Card.Status.PSObject.Properties.Name -contains 'Regenerated')) {
            $ru.Card.Status | Add-Member -NotePropertyName 'Regenerated' -NotePropertyValue $ruRegenerated -Force
        }
        if (-not ($ru.Card.Actions.PSObject.Properties.Name -contains 'RegeneratePreviews')) {
            $ru.Card.Actions | Add-Member -NotePropertyName 'RegeneratePreviews' -NotePropertyValue $ruRegenerateText -Force
        }
        $outRu = $ru | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($ruPath, $outRu, [Text.UTF8Encoding]::new($false))
        Write-Log "updated: lang\ru.json"
    }

    # ============ CHANGELOG ============
    $marker = '<!-- patch 0.4.2b applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.2b] - 2026-11-10`r`n`r`n### Added`r`n- Regenerate previews button (card).`r`n- PreviewsRegenerated event, auto-refresh tile in library.`r`n- Card.Status.Regenerating / Card.Status.Regenerated keys.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.2a\].*)$', "$entry`$1"
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
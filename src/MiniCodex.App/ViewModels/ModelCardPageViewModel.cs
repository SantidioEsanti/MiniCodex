using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Media.Imaging;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;

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
    private CancellationTokenSource? _saveDebounceCts;

    public Model Model { get; }

    private string _title = string.Empty;
    public string Title { get => _title; set { if (_title != value) { _title = value; Raise(); ScheduleSave(); } } }
    private string _author = string.Empty;
    public string Author { get => _author; set { if (_author != value) { _author = value; Raise(); ScheduleSave(); } } }
    private string _sourceUrl = string.Empty;
    public string SourceUrl { get => _sourceUrl; set { if (_sourceUrl != value) { _sourceUrl = value; Raise(); ScheduleSave(); } } }
    private string _status = string.Empty;
    public string Status { get => _status; set { _status = value; Raise(); } }
    private string _difficulty = string.Empty;
    public string Difficulty { get => _difficulty; set { _difficulty = value; Raise(); } }

    private int _difficultyValue;
    public bool IsPlanned => string.Equals(_status, "planned", StringComparison.OrdinalIgnoreCase);
    public bool IsPrinted => string.Equals(_status, "printed", StringComparison.OrdinalIgnoreCase);
    public bool IsPainted => string.Equals(_status, "painted", StringComparison.OrdinalIgnoreCase);

    public int DifficultyValue
    {
        get => _difficultyValue;
        set
        {
            var clamped = Math.Clamp(value, 0, 5);
            if (_difficultyValue == clamped) return;
            _difficultyValue = clamped;
            _difficulty = clamped > 0 ? clamped.ToString(CultureInfo.InvariantCulture) : string.Empty;
            Raise();
            Raise(nameof(Difficulty));
            Raise(nameof(Star1Glyph));
            Raise(nameof(Star2Glyph));
            Raise(nameof(Star3Glyph));
            Raise(nameof(Star4Glyph));
            Raise(nameof(Star5Glyph));
        }
    }

    public string Star1Glyph => _difficultyValue >= 1 ? "\u2605" : "\u2606";
    public string Star2Glyph => _difficultyValue >= 2 ? "\u2605" : "\u2606";
    public string Star3Glyph => _difficultyValue >= 3 ? "\u2605" : "\u2606";
    public string Star4Glyph => _difficultyValue >= 4 ? "\u2605" : "\u2606";
    public string Star5Glyph => _difficultyValue >= 5 ? "\u2605" : "\u2606";

    public string StatusPlannedLabel => Loc("Library.Status.Planned", "Planned");
    public string StatusPrintedLabel => Loc("Library.Status.Printed", "Printed");
    public string StatusPaintedLabel => Loc("Library.Status.Painted", "Painted");
    private string _notes = string.Empty;
    public string Notes { get => _notes; set { if (_notes != value) { _notes = value; Raise(); ScheduleSave(); } } }

    // ---------- Scale ----------
    private string _prototypeType = "any";
    public string PrototypeType
    {
        get => _prototypeType;
        set { if (_prototypeType != value) { _prototypeType = value; Raise(); RefreshScaleChoices(); } }
    }

    public ObservableCollection<string> PrototypeTypeChoices { get; } = new() { "any", "figure", "vehicle", "building", "ship" };
    public ObservableCollection<ScalePreset> ScaleChoices { get; } = new();

    private ScalePreset? _selectedScale;
    public ScalePreset? SelectedScale
    {
        get => _selectedScale;
        set
        {
            if (Equals(_selectedScale, value)) return;
            _selectedScale = value;
            Raise();
            Raise(nameof(SelectedScaleLabel));
            OnScaleChanged();
        }
    }

    public string SelectedScaleLabel => _selectedScale?.Label ?? "";

    private string _manualScaleText = string.Empty;
    public string ManualScaleText
    {
        get => _manualScaleText;
        set { if (_manualScaleText != value) { _manualScaleText = value; Raise(); } }
    }

    private string _realHeightMmText = string.Empty;
    public string RealHeightMmText
    {
        get => _realHeightMmText;
        set
        {
            if (_realHeightMmText == value) return;
            _realHeightMmText = value;
            Raise();
            if (_updatingHeights) return;
            if (float.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var mm)
                && mm > 0 && TryGetDenom(out var d))
            {
                var mh = ScaleCatalog.CalculateModelHeightMm(mm, d);
                if (mh != null) SetHeightsInternal(null, mh.Value);
            }
            ScheduleSave();
        }
    }

    private string _modelHeightMmText = string.Empty;
    public string ModelHeightMmText
    {
        get => _modelHeightMmText;
        set
        {
            if (_modelHeightMmText == value) return;
            _modelHeightMmText = value;
            Raise();
            if (_updatingHeights) return;
            if (float.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var mm)
                && mm > 0 && TryGetDenom(out var d))
            {
                var ph = ScaleCatalog.CalculatePrototypeHeightMm(mm, d);
                if (ph != null) SetHeightsInternal(ph.Value, null);
            }
        }
    }

    private bool _updatingHeights;

    private string _scaleStatus = string.Empty;
    public string ScaleStatus { get => _scaleStatus; private set { _scaleStatus = value; Raise(); } }

    public ObservableCollection<ModelFileRowViewModel> FileRows { get; } = new();

    private string? _meshFilePath;
    public string? MeshFilePath
    {
        get => _meshFilePath;
        set { _meshFilePath = value; Raise(); Raise(nameof(CanLaunch)); Raise(nameof(CanRegeneratePreviews)); }
    }

    private int _selectedTabIndex = 0; // Default: Associations (0.4.3g - Assoc is first tab)
    public int SelectedTabIndex { get => _selectedTabIndex; set { _selectedTabIndex = value; Raise(); } }

    private float _minLambert = 0.45f;
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

    public string BackButtonText => Loc("Card.Actions.Back", "\u2190 Back");
    public string SaveButtonText => Loc("Card.Actions.Save", "Save");
    public string ResetOrientationText => Loc("Card.Actions.ResetOrientation", "Reset");
    public string SaveOrientationText => Loc("Card.Actions.SaveOrientation", "Save orientation");
    public string RegeneratePreviewsText => Loc("Card.Actions.RegeneratePreviews", "Regenerate previews");
    public string TabInfoHeader => Loc("Card.Tabs.Info", "Info");
    public string TabFilesHeader => Loc("Card.Tabs.Files", "Files");
    public string TabAssociationsHeader => Loc("Card.Tabs.Associations", "Associations");
    public string TabTagsHeader => Loc("Card.Tabs.Tags", "Tags");
    public string TabScaleHeader => Loc("Card.Tabs.Scale", "Scale");
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
    public ObservableCollection<AssetRowViewModel> ReferenceAssets { get; } = new();
    public ObservableCollection<AssetRowViewModel> PhotoAssets { get; } = new();

    public bool HasReferenceAssets => ReferenceAssets.Count > 0;
    public bool HasPhotoAssets => PhotoAssets.Count > 0;

    public string ReferenceColumnHeader => Loc("Card.AssetType.Reference", "Reference");
    public string PhotoColumnHeader => Loc("Card.AssetType.Photo", "Photo");
    public string DropReferenceHintText => Loc("Card.Assoc.DropReference", "Drop reference here");
    public string DropPhotoHintText => Loc("Card.Assoc.DropPhoto", "Drop photo here");

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
    public ICommand ApplyManualScaleCommand { get; }
    public ICommand SetStatusCommand { get; }
    public ICommand SetDifficultyCommand { get; }

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
        _difficultyValue = model.Difficulty ?? 0;
        _notes = model.Notes ?? string.Empty;

        // Scale init (private fields to avoid side effects)
        _prototypeType = "any";
        RefreshScaleChoices();
        if (!string.IsNullOrEmpty(model.ScaleRatio))
        {
            var match = ScaleChoices.FirstOrDefault(s => s.Label == model.ScaleRatio);
            if (match != null) _selectedScale = match;
            else _manualScaleText = model.ScaleRatio!;
        }
        _realHeightMmText = model.RealHeightMm.HasValue ? model.RealHeightMm.Value.ToString("F2", CultureInfo.InvariantCulture) : string.Empty;
        _modelHeightMmText = model.ModelHeightMm.HasValue ? model.ModelHeightMm.Value.ToString("F2", CultureInfo.InvariantCulture) : string.Empty;

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
        ApplyManualScaleCommand = new RelayCommand(ApplyManualScale);
        SetStatusCommand = new RelayCommand(p => SetStatus(p as string));
        SetDifficultyCommand = new RelayCommand(p => SetDifficulty(p as string));
    }

    private void RefreshScaleChoices()
    {
        var current = _selectedScale?.Label;
        ScaleChoices.Clear();
        foreach (var s in ScaleCatalog.ForPrototype(_prototypeType)) ScaleChoices.Add(s);
        _selectedScale = current != null
            ? ScaleChoices.FirstOrDefault(s => s.Label == current)
            : ScaleChoices.FirstOrDefault();
        Raise(nameof(SelectedScale));
        Raise(nameof(SelectedScaleLabel));
    }

    private void OnScaleChanged()
    {
        if (_updatingHeights) return;
        if (float.TryParse(_realHeightMmText, NumberStyles.Float, CultureInfo.InvariantCulture, out var realMm)
            && realMm > 0 && TryGetDenom(out var d))
        {
            var mh = ScaleCatalog.CalculateModelHeightMm(realMm, d);
            if (mh != null) SetHeightsInternal(null, mh.Value);
        }
        ScheduleSave();
    }

    private void ScheduleSave()
    {
        _saveDebounceCts?.Cancel();
        _saveDebounceCts = new CancellationTokenSource();
        _ = DebouncedSaveAsync(_saveDebounceCts.Token);
    }

    private async Task DebouncedSaveAsync(CancellationToken ct)
    {
        try
        {
            await Task.Delay(500, ct);
            await SaveAsync();
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { Log.Exception("[ModelCardPageViewModel] autosave failed", ex); }
    }

    private void ApplyManualScale()
    {
        var m = ScaleCatalog.ParseManual(_manualScaleText);
        if (!m.HasValue) { ScaleStatus = Loc("Card.Scale.InvalidManual", "Invalid scale format"); return; }
        _selectedScale = null;
        Raise(nameof(SelectedScale));
        Raise(nameof(SelectedScaleLabel));
        ScaleStatus = string.Format(Loc("Card.Scale.AppliedFormat", "Applied: 1:{0}"), m.Value.ToString("0.##", CultureInfo.InvariantCulture));
        OnScaleChanged();
    }

    private async void SetStatus(string? s)
    {
        if (string.IsNullOrEmpty(s)) return;
        _status = string.Equals(_status, s, StringComparison.OrdinalIgnoreCase) ? string.Empty : s;
        Raise(nameof(Status));
        Raise(nameof(IsPlanned));
        Raise(nameof(IsPrinted));
        Raise(nameof(IsPainted));
        await SaveFieldAsync();
    }

    private async void SetDifficulty(string? s)
    {
        if (s == null || !int.TryParse(s, out var v)) return;
        if (v < 1 || v > 5) return;
        DifficultyValue = (DifficultyValue == v) ? 0 : v;
        await SaveFieldAsync();
    }

    private async Task SaveFieldAsync()
    {
        try
        {
            await _models.UpdateStatusDifficultyAsync(
                Model.Id,
                string.IsNullOrEmpty(_status) ? null : _status,
                _difficultyValue > 0 ? (int?)_difficultyValue : null);
            Model.Status = string.IsNullOrEmpty(_status) ? null : _status;
            Model.Difficulty = _difficultyValue > 0 ? (int?)_difficultyValue : null;
        }
        catch { }
    }

    private bool TryGetDenom(out float denom)
    {
        if (_selectedScale != null) { denom = _selectedScale.Denominator; return true; }
        var m = ScaleCatalog.ParseManual(_manualScaleText);
        if (m.HasValue) { denom = m.Value; return true; }
        denom = 0; return false;
    }

    private void SetHeightsInternal(float? realMm, float? modelMm)
    {
        _updatingHeights = true;
        try
        {
            if (realMm.HasValue) RealHeightMmText = realMm.Value.ToString("F2", CultureInfo.InvariantCulture);
            if (modelMm.HasValue) ModelHeightMmText = modelMm.Value.ToString("F2", CultureInfo.InvariantCulture);
        }
        finally { _updatingHeights = false; }
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        var orientation = ModelOrientation.Parse(Model.OrientationJson);
        _viewerYaw = orientation.Yaw;
        _viewerPitch = orientation.Pitch;
        Raise(nameof(ViewerYaw));
        Raise(nameof(ViewerPitch));
        Raise(nameof(RealHeightMmText));
        Raise(nameof(ModelHeightMmText));
        Raise(nameof(SelectedScale));
        Raise(nameof(ManualScaleText));

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
        finally { IsRegenerating = false; }
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
        RebuildAssetColumns();
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

    private void RebuildAssetColumns()
    {
        ReferenceAssets.Clear();
        PhotoAssets.Clear();
        foreach (var r in AssetRows)
        {
            var t = r.Asset.AssetType?.ToLowerInvariant();
            if (t == "photo") PhotoAssets.Add(r);
            else if (t == "reference" || string.IsNullOrEmpty(t)) ReferenceAssets.Add(r);
            // render/document/profile: not displayed in MVP
        }
        Raise(nameof(HasReferenceAssets));
        Raise(nameof(HasPhotoAssets));
    }

    private void SetAssetStatus(string text) { AssetStatusText = text; Raise(nameof(AssetStatusText)); }

    public async Task ImportAssetsAsync(IEnumerable<string> sourcePaths, string assetType)
    {
        if (AppServices.AssetService == null) return;
        var count = 0;
        foreach (var p in sourcePaths)
        {
            try { await AppServices.AssetService.ImportAsync(Model.Id, p, assetType); count++; }
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
        RebuildAssetColumns();
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
        Raise(nameof(TabScaleHeader));
        Raise(nameof(TabNotesHeader));
        Raise(nameof(LabelTitle));
        Raise(nameof(LabelAuthor));
        Raise(nameof(LabelSourceUrl));
        Raise(nameof(LabelStatus));
        Raise(nameof(StatusPlannedLabel));
        Raise(nameof(StatusPrintedLabel));
        Raise(nameof(StatusPaintedLabel));
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
            Model.Difficulty = _difficultyValue > 0 ? (int?)_difficultyValue : null;
            Model.Notes = NullIfEmpty(Notes);

            // Scale persistence
            if (float.TryParse(_realHeightMmText, NumberStyles.Float, CultureInfo.InvariantCulture, out var rh) && rh > 0)
                Model.RealHeightMm = rh;
            else
                Model.RealHeightMm = null;

            if (float.TryParse(_modelHeightMmText, NumberStyles.Float, CultureInfo.InvariantCulture, out var mh) && mh > 0)
                Model.ModelHeightMm = mh;
            else
                Model.ModelHeightMm = null;

            if (_selectedScale != null) Model.ScaleRatio = _selectedScale.Label;
            else if (ScaleCatalog.ParseManual(_manualScaleText) is float dm)
                Model.ScaleRatio = "1:" + dm.ToString("0.##", CultureInfo.InvariantCulture);
            else
                Model.ScaleRatio = null;

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
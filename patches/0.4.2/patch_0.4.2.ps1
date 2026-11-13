#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.2 - Model orientation (save/load in card).
.DESCRIPTION
    Migration 3 (Model.orientation_json), ThreeDViewer Yaw/Pitch TwoWay,
    SaveOrientation / ResetOrientation in card. ASCII-only script.
    Preview regeneration with orientation is deferred to 0.4.2a.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.2'
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

# ============ Migration 3 ============
$Files['src\MiniCodex.Data\Migrations\Migration_0003_ModelOrientation.cs'] = @'
using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public class Migration_0003_ModelOrientation : IMigration
{
    public int Version => 3;
    public string Description => "Add orientation_json to Model";

    public async Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "ALTER TABLE Model ADD COLUMN orientation_json TEXT;";
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
'@

# ============ DatabaseInitializer ============
$Files['src\MiniCodex.Data\DatabaseInitializer.cs'] = @'
using MiniCodex.Data.Migrations;

namespace MiniCodex.Data;

public static class DatabaseInitializer
{
    public static IReadOnlyList<IMigration> Migrations { get; } = new IMigration[]
    {
        new Migration_0001_InitialSchema(),
        new Migration_0002_ModelFile_LastWriteTime(),
        new Migration_0003_ModelOrientation(),
    };

    public static int LatestSchemaVersion => Migrations.Max(m => m.Version);

    public static async Task InitializeAsync(string dbPath, CancellationToken ct = default)
    {
        var dir = Path.GetDirectoryName(dbPath);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        var factory = new SqliteConnectionFactory(dbPath);
        await using var conn = await factory.OpenAsync(ct);

        var runner = new MigrationRunner(Migrations);
        await runner.RunAsync(conn, ct);
    }
}
'@

# ============ Entities ============
$Files['src\MiniCodex.Core\Models\Entities.cs'] = @'
namespace MiniCodex.Core.Models;

public class Model
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public string? Author { get; set; }
    public string? SourceUrl { get; set; }
    public string? ModelType { get; set; }
    public string? PrimaryModelFileId { get; set; }
    public string? Status { get; set; }
    public int? Difficulty { get; set; }
    public double? RealHeightMm { get; set; }
    public double? ModelHeightMm { get; set; }
    public string? ScaleRatio { get; set; }
    public string? Notes { get; set; }
    public string? OrientationJson { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public class ModelFile
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ModelId { get; set; } = string.Empty;
    public string Path { get; set; } = string.Empty;
    public string? FileRole { get; set; }
    public string? PartName { get; set; }
    public long? FileSizeBytes { get; set; }
    public int? PolygonCount { get; set; }
    public DateTime? LastWriteTimeUtc { get; set; }
}

public class Asset
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ModelId { get; set; } = string.Empty;
    public string? AssetType { get; set; }
    public string AbsolutePath { get; set; } = string.Empty;
    public string? ThumbnailPath { get; set; }
    public int SortOrder { get; set; }
    public string? StorageMode { get; set; }
}

public class Tag
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = string.Empty;
    public string? ParentId { get; set; }
    public string? Color { get; set; }
}

public class Collection
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = string.Empty;
    public string? FilterQuery { get; set; }
    public bool IsSmart { get; set; } = true;
}
'@

# ============ ModelOrientation record ============
$Files['src\MiniCodex.Core\Models\ModelOrientation.cs'] = @'
using System.Text.Json;

namespace MiniCodex.Core.Models;

public class ModelOrientation
{
    public float Yaw { get; set; } = 180f;
    public float Pitch { get; set; } = 15f;

    public static ModelOrientation Default => new();

    public static ModelOrientation Parse(string? json)
    {
        if (string.IsNullOrEmpty(json)) return Default;
        try
        {
            var o = JsonSerializer.Deserialize<ModelOrientation>(json);
            return o ?? Default;
        }
        catch { return Default; }
    }

    public string Serialize() => JsonSerializer.Serialize(this);
}
'@

# ============ ModelRepository (persist orientation_json) ============
$Files['src\MiniCodex.Data\Repositories\ModelRepository.cs'] = @'
using System.Text;
using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class ModelRepository : IModelRepository
{
    private readonly SqliteConnectionFactory _factory;

    public ModelRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<Model?> GetAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        return await ReadOneAsync(conn, "SELECT * FROM Model WHERE id = $id;", id, ct);
    }

    public async Task<IReadOnlyList<Model>> GetAllAsync(CancellationToken ct = default)
    {
        var result = new List<Model>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Model ORDER BY created_at DESC;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task<IReadOnlyList<Model>> SearchAsync(string? query, string? tagId, CancellationToken ct = default)
    {
        var result = new List<Model>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        var sb = new StringBuilder();
        sb.Append("SELECT DISTINCT m.* FROM Model m ");
        if (!string.IsNullOrEmpty(tagId))
            sb.Append("JOIN ModelTag mt ON mt.model_id = m.id ");
        sb.Append("WHERE 1=1 ");
        if (!string.IsNullOrEmpty(tagId))
        {
            sb.Append("AND mt.tag_id = $tagId ");
            cmd.Parameters.AddWithValue("$tagId", tagId);
        }
        if (!string.IsNullOrWhiteSpace(query))
        {
            sb.Append(@"AND (m.title LIKE $q
                        OR COALESCE(m.author, '') LIKE $q
                        OR COALESCE(m.source_url, '') LIKE $q
                        OR EXISTS(SELECT 1 FROM ModelTag mt2
                                  JOIN Tag t2 ON t2.id = mt2.tag_id
                                  WHERE mt2.model_id = m.id AND t2.name LIKE $q)) ");
            cmd.Parameters.AddWithValue("$q", "%" + query.Trim() + "%");
        }
        sb.Append("ORDER BY m.created_at DESC;");
        cmd.CommandText = sb.ToString();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task UpsertAsync(Model m, CancellationToken ct = default)
    {
        m.UpdatedAt = DateTime.UtcNow;
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Model(id, title, author, source_url, model_type, primary_model_file_id, status, difficulty, real_height_mm, model_height_mm, scale_ratio, notes, orientation_json, created_at, updated_at)
VALUES($id, $title, $author, $source_url, $model_type, $primary_model_file_id, $status, $difficulty, $real_height_mm, $model_height_mm, $scale_ratio, $notes, $orientation_json, $created_at, $updated_at)
ON CONFLICT(id) DO UPDATE SET
    title = excluded.title, author = excluded.author, source_url = excluded.source_url,
    model_type = excluded.model_type, primary_model_file_id = excluded.primary_model_file_id,
    status = excluded.status, difficulty = excluded.difficulty,
    real_height_mm = excluded.real_height_mm, model_height_mm = excluded.model_height_mm,
    scale_ratio = excluded.scale_ratio, notes = excluded.notes,
    orientation_json = excluded.orientation_json,
    updated_at = excluded.updated_at;";
        cmd.Parameters.AddWithValue("$id", m.Id);
        cmd.Parameters.AddWithValue("$title", m.Title);
        cmd.Parameters.AddWithValue("$author", (object?)m.Author ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$source_url", (object?)m.SourceUrl ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$model_type", (object?)m.ModelType ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$primary_model_file_id", (object?)m.PrimaryModelFileId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$status", (object?)m.Status ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$difficulty", (object?)m.Difficulty ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$real_height_mm", (object?)m.RealHeightMm ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$model_height_mm", (object?)m.ModelHeightMm ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$scale_ratio", (object?)m.ScaleRatio ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$notes", (object?)m.Notes ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$orientation_json", (object?)m.OrientationJson ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$created_at", m.CreatedAt.ToString("o"));
        cmd.Parameters.AddWithValue("$updated_at", m.UpdatedAt.ToString("o"));
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task DeleteAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM Model WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task<Model?> ReadOneAsync(SqliteConnection conn, string sql, string id, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        cmd.Parameters.AddWithValue("$id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    private static Model Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        Title = r.GetString(1),
        Author = r.IsDBNull(2) ? null : r.GetString(2),
        SourceUrl = r.IsDBNull(3) ? null : r.GetString(3),
        ModelType = r.IsDBNull(4) ? null : r.GetString(4),
        PrimaryModelFileId = r.IsDBNull(5) ? null : r.GetString(5),
        Status = r.IsDBNull(6) ? null : r.GetString(6),
        Difficulty = r.IsDBNull(7) ? null : r.GetInt32(7),
        RealHeightMm = r.IsDBNull(8) ? null : r.GetDouble(8),
        ModelHeightMm = r.IsDBNull(9) ? null : r.GetDouble(9),
        ScaleRatio = r.IsDBNull(10) ? null : r.GetString(10),
        Notes = r.IsDBNull(11) ? null : r.GetString(11),
        CreatedAt = r.IsDBNull(12) ? DateTime.UtcNow : DateTime.Parse(r.GetString(12), null, System.Globalization.DateTimeStyles.RoundtripKind),
        UpdatedAt = r.IsDBNull(13) ? DateTime.UtcNow : DateTime.Parse(r.GetString(13), null, System.Globalization.DateTimeStyles.RoundtripKind),
        OrientationJson = r.IsDBNull(14) ? null : r.GetString(14),
    };
}
'@

# ============ ThreeDViewer (Yaw/Pitch TwoWay) ============
$Files['src\MiniCodex.App\Views\ThreeDViewer.axaml.cs'] = @'
using Avalonia;
using Avalonia.Controls;
using Avalonia.Data;
using Avalonia.Input;
using Avalonia.Media.Imaging;
using Avalonia.Styling;
using Avalonia.Threading;
using MiniCodex.App.ViewModels;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
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
    private bool _suppressPropSync;

    public static readonly StyledProperty<string?> MeshFilePathProperty =
        AvaloniaProperty.Register<ThreeDViewer, string?>(nameof(MeshFilePath));

    public static readonly StyledProperty<float> MinLambertProperty =
        AvaloniaProperty.Register<ThreeDViewer, float>(nameof(MinLambert), 0.4f);

    public static readonly StyledProperty<bool> WireframeProperty =
        AvaloniaProperty.Register<ThreeDViewer, bool>(nameof(Wireframe));

    public static readonly StyledProperty<float> YawProperty =
        AvaloniaProperty.Register<ThreeDViewer, float>(nameof(Yaw), 180f, defaultBindingMode: BindingMode.TwoWay);

    public static readonly StyledProperty<float> PitchProperty =
        AvaloniaProperty.Register<ThreeDViewer, float>(nameof(Pitch), 15f, defaultBindingMode: BindingMode.TwoWay);

    public string? MeshFilePath
    {
        get => GetValue(MeshFilePathProperty);
        set => SetValue(MeshFilePathProperty, value);
    }

    public float MinLambert
    {
        get => GetValue(MinLambertProperty);
        set => SetValue(MinLambertProperty, value);
    }

    public bool Wireframe
    {
        get => GetValue(WireframeProperty);
        set => SetValue(WireframeProperty, value);
    }

    public float Yaw
    {
        get => GetValue(YawProperty);
        set => SetValue(YawProperty, value);
    }

    public float Pitch
    {
        get => GetValue(PitchProperty);
        set => SetValue(PitchProperty, value);
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
        if (Application.Current != null)
            Application.Current.ActualThemeVariantChanged += OnThemeChanged;
    }

    private void OnThemeChanged(object? sender, EventArgs e) => RequestRender();

    protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
    {
        base.OnPropertyChanged(change);
        if (change.Property == MeshFilePathProperty)
            _ = LoadGeometryAsync(change.GetNewValue<string?>());
        else if (change.Property == YawProperty)
        {
            _yaw = change.GetNewValue<float>();
            RequestRender();
        }
        else if (change.Property == PitchProperty)
        {
            _pitch = change.GetNewValue<float>();
            RequestRender();
        }
        else if (change.Property == MinLambertProperty || change.Property == WireframeProperty)
            RequestRender();
    }

    private RenderStyle BuildStyle()
    {
        var isDark = Application.Current?.ActualThemeVariant == ThemeVariant.Dark;
        uint bg = isDark ? 0xFF2D2D2D : 0xFFE0E0E0;
        return new RenderStyle
        {
            BackgroundArgb = bg,
            ModelArgb = 0xFFFFFFFF,
            MinLambert = Math.Clamp(MinLambert, 0f, 1f),
            Wireframe = Wireframe,
        };
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
                var style = BuildStyle();
                if (geo == null) break;

                byte[]? png = null;
                try { png = await Task.Run(() => _renderer.Render(geo, w, h, yaw, pitch, zoom, style)); }
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

        _suppressPropSync = true;
        try
        {
            SetCurrentValue(YawProperty, _yaw);
            SetCurrentValue(PitchProperty, _pitch);
        }
        finally { _suppressPropSync = false; }

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

# ============ ModelCardPageViewModel (add orientation) ============
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
    public string? MeshFilePath { get => _meshFilePath; set { _meshFilePath = value; Raise(); Raise(nameof(CanLaunch)); } }

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
    public string OrientationStatusText { get => _orientationStatusText; private set { _orientationStatusText = value; Raise(); } }

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
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        // Load orientation first, so 3D viewer starts correctly
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

# ============ ModelCardView.axaml (bind Yaw/Pitch + buttons) ============
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
            <TextBlock Text="{Binding OrientationStatusText}" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
            <TextBlock Text="{Binding LabelMinLambert}" VerticalAlignment="Center" Margin="12,0,4,0"/>
            <Slider Value="{Binding MinLambertValue}" Minimum="0" Maximum="1" Width="120" VerticalAlignment="Center"/>
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
$Files['patches\0.4.2\README.md'] = @'
# Patch 0.4.2 - Model orientation (save/load in card)

**Iteration:** 0.4

## What it does

- Migration 3: Model.orientation_json column.
- Model.OrientationJson - {yaw, pitch} as JSON.
- ThreeDViewer.Yaw / ThreeDViewer.Pitch - TwoWay bindable properties (updated on drag).
- ModelCardPageViewModel: ViewerYaw/ViewerPitch, LoadOrientation on open, SaveOrientationCommand, ResetOrientationCommand, OrientationStatusText.
- ModelCardView: "Reset" and "Save orientation" buttons in top row.
- lang/ru.json: 3 new keys (Card.Actions.ResetOrientation, Card.Actions.SaveOrientation, Card.Orientation.Saved).

## Deferred to 0.4.2a

- "Regenerate previews" button.
- PreviewGenerator taking baseYaw/basePitch.
- Library tiles using stored orientation for previews.

## DoD

- dotnet build: 0 errors.
- dotnet test: 40/40 (migration 3 not covered by tests, but LatestSchemaVersion test passes).
- Open card, rotate model, click "Save orientation" -> badge "Orientation saved".
- Close card, reopen -> viewer starts with the saved yaw/pitch.
- Click "Reset" -> viewer goes back to default (180/15).
'@

# ============ Main ============
try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.Data\DatabaseInitializer.cs',
        'src\MiniCodex.Core\Models\Entities.cs',
        'src\MiniCodex.Data\Repositories\ModelRepository.cs',
        'src\MiniCodex.App\Views\ThreeDViewer.axaml.cs',
        'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs',
        'src\MiniCodex.App\Views\ModelCardView.axaml',
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

    # --- lang/ru.json: add 3 keys via char arrays (ASCII-safe source) ---
    $ruPath = Join-Path $ProjectRoot 'lang\ru.json'
    if (Test-Path $ruPath) {
        $ru = [IO.File]::ReadAllText($ruPath, [Text.Encoding]::UTF8) | ConvertFrom-Json

        $ruReset = -join ((0x0421,0x0431,0x0440,0x043E,0x0441) | ForEach-Object { [char]$_ })
        $ruSave  = -join ((0x0421,0x043E,0x0445,0x0440,0x0430,0x043D,0x0438,0x0442,0x044C,0x0020,0x043E,0x0440,0x0438,0x0435,0x043D,0x0442,0x0430,0x0446,0x0438,0x044E) | ForEach-Object { [char]$_ })
        $ruSaved = -join ((0x041E,0x0440,0x0438,0x0435,0x043D,0x0442,0x0430,0x0446,0x0438,0x044F,0x0020,0x0441,0x043E,0x0445,0x0440,0x0430,0x043D,0x0435,0x043D,0x0430) | ForEach-Object { [char]$_ })

        if (-not ($ru.Card.Actions.PSObject.Properties.Name -contains 'ResetOrientation')) {
            $ru.Card.Actions | Add-Member -NotePropertyName 'ResetOrientation' -NotePropertyValue $ruReset -Force
        }
        if (-not ($ru.Card.Actions.PSObject.Properties.Name -contains 'SaveOrientation')) {
            $ru.Card.Actions | Add-Member -NotePropertyName 'SaveOrientation' -NotePropertyValue $ruSave -Force
        }
        if (-not ($ru.Card.PSObject.Properties.Name -contains 'Orientation')) {
            $orientation = [PSCustomObject]@{ Saved = $ruSaved }
            $ru.Card | Add-Member -NotePropertyName 'Orientation' -NotePropertyValue $orientation -Force
        }

        $outRu = $ru | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($ruPath, $outRu, [Text.UTF8Encoding]::new($false))
        Write-Log "updated: lang\ru.json"
    }

    # --- en.json (English keys via base setup only) ---
    $enPath = Join-Path $ProjectRoot 'lang\en.json'
    if (Test-Path $enPath) {
        $en = [IO.File]::ReadAllText($enPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not ($en.Card.Actions.PSObject.Properties.Name -contains 'ResetOrientation')) {
            $en.Card.Actions | Add-Member -NotePropertyName 'ResetOrientation' -NotePropertyValue 'Reset' -Force
        }
        if (-not ($en.Card.Actions.PSObject.Properties.Name -contains 'SaveOrientation')) {
            $en.Card.Actions | Add-Member -NotePropertyName 'SaveOrientation' -NotePropertyValue 'Save orientation' -Force
        }
        if (-not ($en.Card.PSObject.Properties.Name -contains 'Orientation')) {
            $orientation = [PSCustomObject]@{ Saved = 'Orientation saved' }
            $en.Card | Add-Member -NotePropertyName 'Orientation' -NotePropertyValue $orientation -Force
        }
        $outEn = $en | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($enPath, $outEn, [Text.UTF8Encoding]::new($false))
        Write-Log "updated: lang\en.json"
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.2 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.2] - 2026-11-10`r`n`r`n### Added`r`n- Model orientation: save/load in card (migration 3, orientation_json).`r`n- ThreeDViewer Yaw/Pitch TwoWay.`r`n- Reset / Save orientation buttons.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.1a\].*)$', "$entry`$1"
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
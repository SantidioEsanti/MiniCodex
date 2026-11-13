#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.3.2 — Теги + Поиск.
.DESCRIPTION
    IModelTagRepository, TagService, TagRepository.GetAllWithUsageAsync,
    ModelRepository.SearchAsync. UI: вкладка Теги в карточке, сайдбар и поиск в библиотеке.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.3.2'
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

# ============ Core/Models/TagWithUsage.cs ============
$Files['src\MiniCodex.Core\Models\TagWithUsage.cs'] = @'
namespace MiniCodex.Core.Models;

public record TagWithUsage(string Id, string Name, string? ParentId, string? Color, int UsageCount);
'@

# ============ Core/Repositories/IModelTagRepository.cs ============
$Files['src\MiniCodex.Core\Repositories\IModelTagRepository.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Repositories;

public interface IModelTagRepository
{
    Task<IReadOnlyList<Tag>> GetTagsForModelAsync(string modelId, CancellationToken ct = default);
    Task AddAsync(string modelId, string tagId, CancellationToken ct = default);
    Task RemoveAsync(string modelId, string tagId, CancellationToken ct = default);
    Task<bool> ExistsAsync(string modelId, string tagId, CancellationToken ct = default);
}
'@

# ============ Core/Repositories/IRepositories.cs ============
$Files['src\MiniCodex.Core\Repositories\IRepositories.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Repositories;

public interface ISettingRepository
{
    Task<string?> GetAsync(string key, CancellationToken ct = default);
    Task SetAsync(string key, string value, CancellationToken ct = default);
    Task<IReadOnlyDictionary<string, string>> GetAllAsync(CancellationToken ct = default);
}

public interface IModelRepository
{
    Task<Model?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<Model>> GetAllAsync(CancellationToken ct = default);
    Task<IReadOnlyList<Model>> SearchAsync(string? query, string? tagId, CancellationToken ct = default);
    Task UpsertAsync(Model model, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}

public interface IModelFileRepository
{
    Task<ModelFile?> GetAsync(string id, CancellationToken ct = default);
    Task<ModelFile?> GetByPathAsync(string path, CancellationToken ct = default);
    Task<IReadOnlyList<ModelFile>> GetByModelAsync(string modelId, CancellationToken ct = default);
    Task UpsertAsync(ModelFile file, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}

public interface IAssetRepository
{
    Task<Asset?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<Asset>> GetByModelAsync(string modelId, CancellationToken ct = default);
    Task UpsertAsync(Asset asset, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}

public interface ITagRepository
{
    Task<Tag?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<Tag>> GetAllAsync(CancellationToken ct = default);
    Task<IReadOnlyList<TagWithUsage>> GetAllWithUsageAsync(CancellationToken ct = default);
    Task UpsertAsync(Tag tag, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}

public interface ICollectionRepository
{
    Task<Collection?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<Collection>> GetAllAsync(CancellationToken ct = default);
    Task UpsertAsync(Collection collection, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}
'@

# ============ Core/Services/ITagService.cs ============
$Files['src\MiniCodex.Core\Services\ITagService.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface ITagService
{
    Task<Tag> CreateOrGetAsync(string name, CancellationToken ct = default);
    Task<IReadOnlyList<Tag>> GetTagsForModelAsync(string modelId, CancellationToken ct = default);
    Task AddToModelAsync(string modelId, string tagName, CancellationToken ct = default);
    Task RemoveFromModelAsync(string modelId, string tagId, CancellationToken ct = default);
    Task<IReadOnlyList<TagWithUsage>> GetAllWithUsageAsync(CancellationToken ct = default);
}
'@

# ============ Core/Services/TagService.cs ============
$Files['src\MiniCodex.Core\Services\TagService.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class TagService : ITagService
{
    private readonly ITagRepository _tags;
    private readonly IModelTagRepository _modelTags;

    public TagService(ITagRepository tags, IModelTagRepository modelTags)
    {
        _tags = tags;
        _modelTags = modelTags;
    }

    public async Task<Tag> CreateOrGetAsync(string name, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Tag name is required", nameof(name));

        var trimmed = name.Trim();
        var all = await _tags.GetAllAsync(ct);
        var existing = all.FirstOrDefault(t => string.Equals(t.Name, trimmed, StringComparison.OrdinalIgnoreCase));
        if (existing != null) return existing;

        var tag = new Tag { Name = trimmed };
        await _tags.UpsertAsync(tag, ct);
        return tag;
    }

    public Task<IReadOnlyList<Tag>> GetTagsForModelAsync(string modelId, CancellationToken ct = default)
        => _modelTags.GetTagsForModelAsync(modelId, ct);

    public async Task AddToModelAsync(string modelId, string tagName, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(tagName)) return;
        var tag = await CreateOrGetAsync(tagName, ct);
        await _modelTags.AddAsync(modelId, tag.Id, ct);
    }

    public Task RemoveFromModelAsync(string modelId, string tagId, CancellationToken ct = default)
        => _modelTags.RemoveAsync(modelId, tagId, ct);

    public Task<IReadOnlyList<TagWithUsage>> GetAllWithUsageAsync(CancellationToken ct = default)
        => _tags.GetAllWithUsageAsync(ct);
}
'@

# ============ Data/Repositories/ModelTagRepository.cs ============
$Files['src\MiniCodex.Data\Repositories\ModelTagRepository.cs'] = @'
using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class ModelTagRepository : IModelTagRepository
{
    private readonly SqliteConnectionFactory _factory;

    public ModelTagRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<IReadOnlyList<Tag>> GetTagsForModelAsync(string modelId, CancellationToken ct = default)
    {
        var result = new List<Tag>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"SELECT t.id, t.name, t.parent_id, t.color
                            FROM Tag t
                            JOIN ModelTag mt ON mt.tag_id = t.id
                            WHERE mt.model_id = $m
                            ORDER BY t.name;";
        cmd.Parameters.AddWithValue("$m", modelId);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            result.Add(new Tag
            {
                Id = r.GetString(0),
                Name = r.GetString(1),
                ParentId = r.IsDBNull(2) ? null : r.GetString(2),
                Color = r.IsDBNull(3) ? null : r.GetString(3),
            });
        }
        return result;
    }

    public async Task AddAsync(string modelId, string tagId, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "INSERT OR IGNORE INTO ModelTag(model_id, tag_id) VALUES($m, $t);";
        cmd.Parameters.AddWithValue("$m", modelId);
        cmd.Parameters.AddWithValue("$t", tagId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task RemoveAsync(string modelId, string tagId, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM ModelTag WHERE model_id = $m AND tag_id = $t;";
        cmd.Parameters.AddWithValue("$m", modelId);
        cmd.Parameters.AddWithValue("$t", tagId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<bool> ExistsAsync(string modelId, string tagId, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT 1 FROM ModelTag WHERE model_id = $m AND tag_id = $t LIMIT 1;";
        cmd.Parameters.AddWithValue("$m", modelId);
        cmd.Parameters.AddWithValue("$t", tagId);
        return await cmd.ExecuteScalarAsync(ct) != null;
    }
}
'@

# ============ Data/Repositories/ModelRepository.cs ============
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
INSERT INTO Model(id, title, author, source_url, model_type, primary_model_file_id, status, difficulty, real_height_mm, model_height_mm, scale_ratio, notes, created_at, updated_at)
VALUES($id, $title, $author, $source_url, $model_type, $primary_model_file_id, $status, $difficulty, $real_height_mm, $model_height_mm, $scale_ratio, $notes, $created_at, $updated_at)
ON CONFLICT(id) DO UPDATE SET
    title = excluded.title, author = excluded.author, source_url = excluded.source_url,
    model_type = excluded.model_type, primary_model_file_id = excluded.primary_model_file_id,
    status = excluded.status, difficulty = excluded.difficulty,
    real_height_mm = excluded.real_height_mm, model_height_mm = excluded.model_height_mm,
    scale_ratio = excluded.scale_ratio, notes = excluded.notes, updated_at = excluded.updated_at;";
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
    };
}
'@

# ============ Data/Repositories/TagRepository.cs ============
$Files['src\MiniCodex.Data\Repositories\TagRepository.cs'] = @'
using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class TagRepository : ITagRepository
{
    private readonly SqliteConnectionFactory _factory;

    public TagRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<Tag?> GetAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Tag WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    public async Task<IReadOnlyList<Tag>> GetAllAsync(CancellationToken ct = default)
    {
        var result = new List<Tag>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Tag ORDER BY name;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task<IReadOnlyList<TagWithUsage>> GetAllWithUsageAsync(CancellationToken ct = default)
    {
        var result = new List<TagWithUsage>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"SELECT t.id, t.name, t.parent_id, t.color, COUNT(mt.model_id) AS usage
                            FROM Tag t
                            LEFT JOIN ModelTag mt ON mt.tag_id = t.id
                            GROUP BY t.id, t.name, t.parent_id, t.color
                            ORDER BY t.name;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            result.Add(new TagWithUsage(
                r.GetString(0),
                r.GetString(1),
                r.IsDBNull(2) ? null : r.GetString(2),
                r.IsDBNull(3) ? null : r.GetString(3),
                r.GetInt32(4)));
        }
        return result;
    }

    public async Task UpsertAsync(Tag t, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Tag(id, name, parent_id, color) VALUES($id, $name, $parent_id, $color)
ON CONFLICT(id) DO UPDATE SET name = excluded.name, parent_id = excluded.parent_id, color = excluded.color;";
        cmd.Parameters.AddWithValue("$id", t.Id);
        cmd.Parameters.AddWithValue("$name", t.Name);
        cmd.Parameters.AddWithValue("$parent_id", (object?)t.ParentId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$color", (object?)t.Color ?? DBNull.Value);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task DeleteAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM Tag WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static Tag Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        Name = r.GetString(1),
        ParentId = r.IsDBNull(2) ? null : r.GetString(2),
        Color = r.IsDBNull(3) ? null : r.GetString(3),
    };
}
'@

# ============ App/AppServices.cs ============
$Files['src\MiniCodex.App\AppServices.cs'] = @'
using MiniCodex.App.Services;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using MiniCodex.Render.Loaders;
using MiniCodex.Render.Rendering;

namespace MiniCodex.App;

public static class AppServices
{
    public static SqliteConnectionFactory? Factory { get; private set; }
    public static IModelRepository? Models { get; private set; }
    public static IModelFileRepository? ModelFiles { get; private set; }
    public static IAssetRepository? Assets { get; private set; }
    public static ISettingRepository? Settings { get; private set; }
    public static IModelTagRepository? ModelTags { get; private set; }
    public static ScannerService? Scanner { get; private set; }
    public static PreviewGenerator? PreviewGenerator { get; private set; }
    public static IAssetService? AssetService { get; private set; }
    public static ITagService? TagService { get; private set; }
    public static AppPaths? Paths { get; private set; }

    public static void Init(AppPaths paths)
    {
        Paths = paths;
        Factory = new SqliteConnectionFactory(paths.LibraryDb);
        Models = new ModelRepository(Factory);
        ModelFiles = new ModelFileRepository(Factory);
        Assets = new AssetRepository(Factory);
        Settings = new SettingRepository(Factory);
        ModelTags = new ModelTagRepository(Factory);

        var meshLoader = new AssimpMeshLoader();
        Scanner = new ScannerService(meshLoader, Models, ModelFiles);

        var renderer = new SkiaPreviewRenderer();
        PreviewGenerator = new PreviewGenerator(renderer, meshLoader, paths.CacheDir);

        var thumbs = new SkiaThumbnailGenerator();
        var thumbsRoot = Path.Combine(paths.DataDir, "cache", "asset-thumbs");
        AssetService = new AssetService(Assets, ModelFiles, thumbs, paths.AssetsDir, thumbsRoot);

        TagService = new TagService(new TagRepository(Factory), ModelTags);
    }
}
'@

# ============ App/ViewModels/TagRowViewModel.cs ============
$Files['src\MiniCodex.App\ViewModels\TagRowViewModel.cs'] = @'
using System.Windows.Input;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class TagRowViewModel
{
    public Tag Tag { get; }
    public string Name => Tag.Name;
    public ICommand RemoveCommand { get; }

    public TagRowViewModel(Tag tag, Func<TagRowViewModel, Task> onRemove)
    {
        Tag = tag;
        RemoveCommand = new RelayCommand(async () => await onRemove(this));
    }
}
'@

# ============ App/ViewModels/ModelCardPageViewModel.cs ============
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

    // ---------- 3D render params ----------
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
        ThreeDViewState.Loading => Loc("Card.ThreeD.Loading", "Loading 3D…"),
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
    public string LabelMinLambert => Loc("Card.View.MinLambert", "Shadow softness");
    public string LabelWireframe => Loc("Card.View.Wireframe", "Wireframe");

    public string AddFileButtonText => Loc("Card.Assoc.AddFile", "Add file");
    public string AutoLinkButtonText => Loc("Card.Assoc.AutoLink", "Auto-link");
    public string DropHintText => Loc("Card.Assoc.DropHint", "Drop files here to attach");
    public string RemoveAssetText => Loc("Card.Assoc.Remove", "Remove");
    public string AssetStatusText { get; private set; } = string.Empty;

    public string TagPlaceholderText => Loc("Card.Tags.Placeholder", "Enter tag…");
    public string AddTagButtonText => Loc("Card.Tags.Add", "Add");
    public string EmptyTagsText => Loc("Card.Tags.Empty", "No tags yet");

    // ---------- Associations ----------
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

    // ---------- Tags ----------
    public ObservableCollection<TagRowViewModel> TagRows { get; } = new();

    private string _newTagName = string.Empty;
    public string NewTagName { get => _newTagName; set { _newTagName = value; Raise(); } }

    public ICommand SaveCommand { get; }
    public ICommand GoBackCommand { get; }
    public ICommand SetPrimaryCommand { get; }
    public ICommand AutoLinkCommand { get; }
    public ICommand AddTagCommand { get; }

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
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
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
                try
                {
                    using var stream = File.OpenRead(path);
                    row.SetThumbnail(new Bitmap(stream));
                }
                catch { }
            });
        }
        catch { }
    }

    private void RebuildFilteredAssets()
    {
        FilteredAssets.Clear();
        foreach (var r in AssetRows)
        {
            if (_selectedAssetFilter == "all" || r.Asset.AssetType == _selectedAssetFilter)
                FilteredAssets.Add(r);
        }
    }

    private void SetAssetStatus(string text)
    {
        AssetStatusText = text;
        Raise(nameof(AssetStatusText));
    }

    public async Task ImportAssetsAsync(IEnumerable<string> sourcePaths)
    {
        if (AppServices.AssetService == null) return;
        var count = 0;
        foreach (var p in sourcePaths)
        {
            try
            {
                await AppServices.AssetService.ImportAsync(Model.Id, p, SelectedAssetType);
                count++;
            }
            catch { }
        }
        SetAssetStatus(string.Format(Loc("Card.Assoc.Imported", "Imported: {0}"), count));
        await ReloadAssetsAsync(CancellationToken.None);
    }

    private async Task AutoLinkAsync()
    {
        if (AppServices.AssetService == null) return;
        SetAssetStatus(Loc("Card.Assoc.AutoLinkRunning", "Searching…"));
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
        try
        {
            await AppServices.TagService.RemoveFromModelAsync(Model.Id, row.Tag.Id);
            TagRows.Remove(row);
        }
        catch { }
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
        Raise(nameof(LabelMinLambert));
        Raise(nameof(LabelWireframe));
        Raise(nameof(AddFileButtonText));
        Raise(nameof(AutoLinkButtonText));
        Raise(nameof(DropHintText));
        Raise(nameof(RemoveAssetText));
        Raise(nameof(TagPlaceholderText));
        Raise(nameof(AddTagButtonText));
        Raise(nameof(EmptyTagsText));
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

    private static async Task SaveSettingAsync(string key, string value)
    {
        if (AppServices.Settings == null) return;
        try { await AppServices.Settings.SetAsync(key, value); } catch { }
    }

    private static string? NullIfEmpty(string s) => string.IsNullOrWhiteSpace(s) ? null : s;
    private static string Loc(string key, string fallback) => App.Loc?.Get(key) ?? fallback;
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

    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private readonly IModelRepository? _models;
    private readonly IModelFileRepository? _files;
    private readonly ScannerService? _scanner;
    private readonly PreviewGenerator? _previews;
    private readonly ITagService? _tagService;

    public ObservableCollection<ModelCardViewModel> Cards { get; } = new();
    public ObservableCollection<TagWithUsage> Tags { get; } = new();

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
    public string SearchPlaceholder => App.Loc?.Get("Library.SearchPlaceholder") ?? "Search…";
    public string TagsHeader => App.Loc?.Get("Library.TagsHeader") ?? "Tags";

    private enum StatusState { None, Loading, ModelCount, Scanning }
    private StatusState _statusState = StatusState.None;
    private int _statusCount;
    private string _statusDetail = string.Empty;

    public string StatusText => _statusState switch
    {
        StatusState.Loading => App.Loc?.Get("Library.Loading") ?? "Loading…",
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
        ITagService? tagService)
    {
        _models = models; _files = files; _scanner = scanner; _previews = previews;
        _tagService = tagService;
        RequestFocusSearchCommand = new RelayCommand(() => FocusSearchRequested?.Invoke(this, EventArgs.Empty));
    }

    public void RequestFocusSearch() => FocusSearchRequested?.Invoke(this, EventArgs.Empty);

    public void RefreshLocalized()
    {
        Raise(nameof(ScanButtonText));
        Raise(nameof(EmptyStateText));
        Raise(nameof(SearchPlaceholder));
        Raise(nameof(TagsHeader));
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
            await LoadTagsAsync(ct);
            await ReloadModelsCoreAsync(ct);
        }
        finally { IsBusy = false; }
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
        finally
        {
            _suppressTagReload = false;
        }
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
            var card = new ModelCardViewModel(m, OnOpenRequested);
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
        SetStatus(StatusState.Scanning, 0, App.Loc?.Get("Library.Scanning") ?? "Scanning…");
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

    public ICommand RequestFocusSearchCommand { get; }

    public MainWindowViewModel()
    {
        Library = new LibraryViewModel(
            AppServices.Models,
            AppServices.ModelFiles,
            AppServices.Scanner,
            AppServices.PreviewGenerator,
            AppServices.TagService);
        Library.OpenCardRequested += OnOpenCard;
        CurrentPage = Library;

        RequestFocusSearchCommand = new RelayCommand(() =>
        {
            if (CurrentPage is LibraryViewModel lib) lib.RequestFocusSearch();
        });
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

# ============ App/Views/LibraryView.axaml ============
$Files['src\MiniCodex.App\Views\LibraryView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
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
                        <DataTemplate>
                            <Button Command="{Binding OpenCommand}"
                                    Background="Transparent"
                                    BorderBrush="Transparent"
                                    Padding="0">
                                <Border Width="220" Height="260" Margin="6"
                                        BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
                                        BorderThickness="1" CornerRadius="6" Padding="6">
                                    <Grid RowDefinitions="180,*,Auto">
                                        <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                CornerRadius="4">
                                            <Image Source="{Binding PreviewImage}" Stretch="Uniform" Margin="4"/>
                                        </Border>
                                        <TextBlock Grid.Row="1" Text="{Binding Title}"
                                                   FontWeight="Bold" TextTrimming="CharacterEllipsis"
                                                   Margin="0,6,0,0"/>
                                        <TextBlock Grid.Row="2" FontSize="11"
                                                   Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"
                                                   Text="{Binding StatusText}"/>
                                    </Grid>
                                </Border>
                            </Button>
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

# ============ App/Views/LibraryView.axaml.cs ============
$Files['src\MiniCodex.App\Views\LibraryView.axaml.cs'] = @'
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using MiniCodex.App.ViewModels;

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
        if (DataContext is LibraryViewModel vm)
            await vm.LoadAsync();
    }

    private async void OnScanClick(object? sender, RoutedEventArgs e)
    {
        var topLevel = TopLevel.GetTopLevel(this);
        if (topLevel?.StorageProvider is null) return;

        var folders = await topLevel.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = App.Loc?.Get("Library.ScanFolderTitle") ?? "Select source folder",
            AllowMultiple = true,
        });
        if (folders.Count == 0) return;

        var paths = folders
            .Select(f => f.TryGetLocalPath())
            .Where(p => !string.IsNullOrEmpty(p))
            .Cast<string>()
            .ToList();
        if (paths.Count == 0) return;

        if (DataContext is LibraryViewModel vm)
            await vm.ScanAsync(paths);
    }
}
'@

# ============ App/Views/MainWindow.axaml ============
$Files['src\MiniCodex.App\Views\MainWindow.axaml'] = @'
<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Class="MiniCodex.App.Views.MainWindow"
        Title="{Binding Title}" Icon="/Assets/icon.ico"
        Width="1100" Height="750">
    <Window.KeyBindings>
        <KeyBinding Gesture="Ctrl+F" Command="{Binding RequestFocusSearchCommand}"/>
    </Window.KeyBindings>
    <Grid RowDefinitions="Auto,*">
        <StackPanel Orientation="Horizontal" Spacing="8" Margin="8">
            <ComboBox ItemsSource="{Binding Languages}" SelectedItem="{Binding CurrentLanguage}" Width="120"/>
            <ComboBox ItemsSource="{Binding Themes}" SelectedItem="{Binding CurrentTheme}" Width="120"/>
        </StackPanel>
        <ContentControl Grid.Row="1" Content="{Binding CurrentPage}"/>
    </Grid>
</Window>
'@

# ============ App/Views/ModelCardView.axaml (правка вкладки Теги) ============
# (перезаписываем целиком ради консистентности)
$Files['src\MiniCodex.App\Views\ModelCardView.axaml'] = @'
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:views="clr-namespace:MiniCodex.App.Views"
             xmlns:vm="clr-namespace:MiniCodex.App.ViewModels"
             x:Class="MiniCodex.App.Views.ModelCardView"
             x:DataType="vm:ModelCardPageViewModel">
    <Grid RowDefinitions="Auto,*">
        <StackPanel Orientation="Horizontal" Spacing="8" Margin="8">
            <Button Content="{Binding BackButtonText}" Command="{Binding GoBackCommand}"/>
            <Button Content="{Binding SaveButtonText}" Command="{Binding SaveCommand}"/>
            <TextBlock Text="{Binding SaveStatusText}" VerticalAlignment="Center"
                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
            <TextBlock Text="{Binding LabelMinLambert}" VerticalAlignment="Center" Margin="12,0,4,0"/>
            <Slider Value="{Binding MinLambertValue}" Minimum="0" Maximum="1" Width="120" VerticalAlignment="Center"/>
            <CheckBox Content="{Binding LabelWireframe}" IsChecked="{Binding WireframeMode}" VerticalAlignment="Center"/>
        </StackPanel>

        <Grid Grid.Row="1" ColumnDefinitions="480,*" Margin="8,0,8,8">
            <views:ThreeDViewer Grid.Column="0"
                                MeshFilePath="{Binding MeshFilePath}"
                                MinLambert="{Binding MinLambertValue}"
                                Wireframe="{Binding WireframeMode}"
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
                    <Grid RowDefinitions="Auto,Auto,*">
                        <StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="6" Margin="6">
                            <ComboBox ItemsSource="{Binding AssetTypeChoices}"
                                      SelectedItem="{Binding SelectedAssetType}" Width="110"/>
                            <Button Content="{Binding AddFileButtonText}" Click="OnAddFileClick"/>
                            <Button Content="{Binding AutoLinkButtonText}" Command="{Binding AutoLinkCommand}"/>
                            <ComboBox ItemsSource="{Binding AssetFilterChoices}"
                                      SelectedItem="{Binding SelectedAssetFilter}" Width="110" Margin="12,0,0,0"/>
                            <TextBlock Text="{Binding AssetStatusText}" VerticalAlignment="Center" Margin="8,0,0,0"
                                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                        </StackPanel>

                        <Border Grid.Row="1" Margin="6" Padding="8" MinHeight="60"
                                BorderThickness="1" BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}"
                                CornerRadius="6"
                                Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                Name="DropZone" DragDrop.AllowDrop="True">
                            <TextBlock Text="{Binding DropHintText}" HorizontalAlignment="Center" VerticalAlignment="Center"
                                       Foreground="{DynamicResource SystemControlForegroundBaseMediumBrush}"/>
                        </Border>

                        <ScrollViewer Grid.Row="2">
                            <ItemsControl ItemsSource="{Binding FilteredAssets}" Margin="6">
                                <ItemsControl.ItemsPanel>
                                    <ItemsPanelTemplate>
                                        <WrapPanel Orientation="Horizontal"/>
                                    </ItemsPanelTemplate>
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
                                                    <Button Grid.Column="1" Content="×"
                                                            Command="{Binding RemoveCommand}"
                                                            Padding="6,0" MinWidth="24"
                                                            ToolTip.Tip="{Binding $parent[ItemsControl].((vm:ModelCardPageViewModel)DataContext).RemoveAssetText}"/>
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
                                    <ItemsPanelTemplate>
                                        <WrapPanel Orientation="Horizontal"/>
                                    </ItemsPanelTemplate>
                                </ItemsControl.ItemsPanel>
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <Border Background="{DynamicResource SystemControlBackgroundBaseLowBrush}"
                                                CornerRadius="12" Padding="8,2" Margin="4">
                                            <StackPanel Orientation="Horizontal" Spacing="4">
                                                <TextBlock Text="{Binding Name}" VerticalAlignment="Center"/>
                                                <Button Content="×" Command="{Binding RemoveCommand}"
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

# ============ Tests/Services/TagServiceTests.cs ============
$Files['src\MiniCodex.Tests\Services\TagServiceTests.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using MiniCodex.Core.Repositories;
using Xunit;

namespace MiniCodex.Tests.Services;

public class TagServiceTests : IDisposable
{
    private readonly string _dbPath;
    private readonly SqliteConnectionFactory _factory;
    private readonly ITagRepository _tags;
    private readonly IModelTagRepository _modelTags;
    private readonly TagService _service;
    private readonly IModelRepository _models;

    public TagServiceTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        DatabaseInitializer.InitializeAsync(_dbPath).GetAwaiter().GetResult();
        _factory = new SqliteConnectionFactory(_dbPath);
        _tags = new TagRepository(_factory);
        _modelTags = new ModelTagRepository(_factory);
        _models = new ModelRepository(_factory);
        _service = new TagService(_tags, _modelTags);
    }

    public void Dispose() { try { File.Delete(_dbPath); } catch { } }

    [Fact]
    public async Task CreateOrGet_IsIdempotent_CaseInsensitive()
    {
        var t1 = await _service.CreateOrGetAsync("Goblins");
        var t2 = await _service.CreateOrGetAsync("goblins");
        var t3 = await _service.CreateOrGetAsync("GOBLINS");

        Assert.Equal(t1.Id, t2.Id);
        Assert.Equal(t1.Id, t3.Id);

        var all = await _tags.GetAllAsync();
        Assert.Single(all);
    }

    [Fact]
    public async Task AddToModel_CreatesTag_AndIncrementsUsage()
    {
        var m = new Model { Title = "M" };
        await _models.UpsertAsync(m);

        await _service.AddToModelAsync(m.Id, "Fantasy");
        await _service.AddToModelAsync(m.Id, "fantasy"); // дубликат — не должен создать второй тег

        var tags = await _service.GetTagsForModelAsync(m.Id);
        Assert.Single(tags);

        var usages = await _service.GetAllWithUsageAsync();
        var fantasy = usages.FirstOrDefault(u => u.Name == "Fantasy");
        Assert.NotNull(fantasy);
        Assert.Equal(1, fantasy!.UsageCount);
    }

    [Fact]
    public async Task RemoveFromModel_DecrementsUsage()
    {
        var m = new Model { Title = "M" };
        await _models.UpsertAsync(m);
        await _service.AddToModelAsync(m.Id, "Test");

        var tags = await _service.GetTagsForModelAsync(m.Id);
        await _service.RemoveFromModelAsync(m.Id, tags[0].Id);

        var remaining = await _service.GetTagsForModelAsync(m.Id);
        Assert.Empty(remaining);
    }
}
'@

# ============ Tests/Services/SearchServiceTests.cs ============
$Files['src\MiniCodex.Tests\Services\SearchServiceTests.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Services;

public class SearchServiceTests : IDisposable
{
    private readonly string _dbPath;
    private readonly SqliteConnectionFactory _factory;
    private readonly IModelRepository _models;
    private readonly ITagService _tagService;

    public SearchServiceTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        DatabaseInitializer.InitializeAsync(_dbPath).GetAwaiter().GetResult();
        _factory = new SqliteConnectionFactory(_dbPath);
        _models = new ModelRepository(_factory);
        _tagService = new TagService(new TagRepository(_factory), new ModelTagRepository(_factory));
    }

    public void Dispose() { try { File.Delete(_dbPath); } catch { } }

    [Fact]
    public async Task Search_ByName_FindsModel()
    {
        var g = new Model { Title = "Goblin" };
        var d = new Model { Title = "Dragon" };
        await _models.UpsertAsync(g);
        await _models.UpsertAsync(d);

        var found = await _models.SearchAsync("gob", null);
        Assert.Single(found);
        Assert.Equal("Goblin", found[0].Title);
    }

    [Fact]
    public async Task Search_ByAuthor_FindsModel()
    {
        var m = new Model { Title = "M", Author = "John Doe" };
        await _models.UpsertAsync(m);

        var found = await _models.SearchAsync("john", null);
        Assert.Single(found);
    }

    [Fact]
    public async Task Search_ByTag_FindsModel()
    {
        var m = new Model { Title = "M" };
        await _models.UpsertAsync(m);
        await _tagService.AddToModelAsync(m.Id, "Fantasy");

        var found = await _models.SearchAsync("Fantasy", null);
        Assert.Single(found);
    }

    [Fact]
    public async Task Search_ByTagFilter_OnlyTaggedModels()
    {
        var m1 = new Model { Title = "A" };
        var m2 = new Model { Title = "B" };
        await _models.UpsertAsync(m1);
        await _models.UpsertAsync(m2);
        await _tagService.AddToModelAsync(m1.Id, "Fantasy");

        var tagId = (await _tagService.GetAllWithUsageAsync()).First(u => u.Name == "Fantasy").Id;
        var found = await _models.SearchAsync(null, tagId);

        Assert.Single(found);
        Assert.Equal("A", found[0].Title);
    }

    [Fact]
    public async Task Search_NoMatch_ReturnsEmpty()
    {
        await _models.UpsertAsync(new Model { Title = "Goblin" });
        var found = await _models.SearchAsync("nonexistent_xyz", null);
        Assert.Empty(found);
    }
}
'@

# ============ README ============
$Files['patches\0.3.2\README.md'] = @'
# Патч 0.3.2 — Теги + Поиск

**Итерация:** 0.3 · **Статус:** реализован

## Что делает

### Теги
- `IModelTagRepository` + `ModelTagRepository` — CRUD связи Model↔Tag.
- `ITagRepository.GetAllWithUsageAsync` — теги с usage-count (LEFT JOIN).
- `ITagService` + `TagService`:
  - `CreateOrGetAsync(name)` — идемпотентно (case-insensitive)
  - `AddToModelAsync(modelId, name)` — создаёт тег при необходимости + привязка
  - `RemoveFromModelAsync(modelId, tagId)` — отвязка
- Карточка модели, вкладка «Теги»: TextBox + кнопка «Добавить» + чипы с `×`.

### Поиск
- `IModelRepository.SearchAsync(query, tagId)`:
  - по `title` / `author` / `source_url` (LIKE)
  - по имени тега (EXISTS-подзапрос)
  - фильтр по `tagId`
- Библиотека: SearchBox сверху (debounce 200 мс), сайдбар с тегами + счётчик.
- `Ctrl+F` — фокус на SearchBox.

### Локализация
- `Library.SearchPlaceholder`, `Library.TagsHeader`, `Library.AllModels`
- `Card.Tags.Placeholder`, `Card.Tags.Add`, `Card.Tags.Empty`

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.2\patch_0.3.2.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 36 тестов (28 + 8 новых), все зелёные.
- В карточке: добавили тег «Fantasy» → чип, в БД `Tag`+`ModelTag`. Удаление — запись уходит.
- В библиотеке: поиск «fant» → находит модель по тегу. Клик на тег в сайдбаре → фильтр.
- `Ctrl+F` фокусирует SearchBox.
- Пустой `SearchQuery` + «Все модели» → весь список.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.Core\Repositories\IRepositories.cs',
        'src\MiniCodex.Data\Repositories\ModelRepository.cs',
        'src\MiniCodex.Data\Repositories\TagRepository.cs',
        'src\MiniCodex.App\AppServices.cs',
        'src\MiniCodex.App\ViewModels\ModelCardPageViewModel.cs',
        'src\MiniCodex.App\ViewModels\LibraryViewModel.cs',
        'src\MiniCodex.App\ViewModels\MainWindowViewModel.cs',
        'src\MiniCodex.App\Views\LibraryView.axaml',
        'src\MiniCodex.App\Views\LibraryView.axaml.cs',
        'src\MiniCodex.App\Views\MainWindow.axaml',
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

    # --- lang/*.json: Library.SearchPlaceholder, Library.TagsHeader, Library.AllModels, Card.Tags.* ---
    foreach ($langEntry in @(
        @('lang\en.json', 'Search by name, tag, author…', 'Tags', 'All models', 'Enter tag…', 'Add', 'No tags yet'),
        @('lang\ru.json', 'Поиск по имени, тегу, автору…', 'Теги', 'Все модели', 'Введите тег…', 'Добавить', 'Тегов пока нет')
    )) {
        $langPath = Join-Path $ProjectRoot $langEntry[0]
        if (-not (Test-Path $langPath)) { continue }
        $content = [IO.File]::ReadAllText($langPath, [Text.Encoding]::UTF8)

        # Library.*
        if ($content -notmatch '"TagsHeader"') {
            $content = $content -replace '("ScanFolderTitle"\s*:\s*"[^"]*",)', "`$1`r`n    `"TagsHeader`": `"$($langEntry[2])`",`r`n    `"AllModels`": `"$($langEntry[3])`","
            # Update SearchPlaceholder (уже есть ключ Library.SearchPlaceholder)
            $content = $content -replace '("SearchPlaceholder"\s*:\s*")[^"]*(")', "`$1$($langEntry[1])`$2"
            Write-Log "updated: $($langEntry[0]) (Library.TagsHeader, Library.AllModels, SearchPlaceholder)"
        }

        # Card.Tags.* — вставляем после "Tabs": { ... } (внутри Card)
        if ($content -notmatch '"Tags"\s*:\s*\{\s*"Placeholder"') {
            $tagsBlock = '"Tags": {' + "`r`n" +
                         "      `"Placeholder`": `"$($langEntry[4])`",`r`n" +
                         "      `"Add`": `"$($langEntry[5])`",`r`n" +
                         "      `"Empty`": `"$($langEntry[6])`"`r`n" +
                         "    },"
            $content = $content -replace '("Tabs"\s*:\s*\{[^}]*\},)', "`$1`r`n    $tagsBlock"
            Write-Log "updated: $($langEntry[0]) (Card.Tags.*)"
        }

        [IO.File]::WriteAllText($langPath, $content, [Text.UTF8Encoding]::new($false))
    }

    # CHANGELOG
    $marker = '<!-- patch 0.3.2 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n## [0.3.2] - 2026-11-10`n`n### Added`n- Теги: IModelTagRepository, TagService, вкладка «Теги» в карточке.`n- Поиск: SearchAsync(query, tagId) + сайдбар с тегами + SearchBox.`n- Ctrl+F — фокус на SearchBox.`n- 8 новых тестов (теги + поиск).`n"
            $cl = $cl -replace '(?m)^(## \[0\.3\.1b\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.3.2.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}
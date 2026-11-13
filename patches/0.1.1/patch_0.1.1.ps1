#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.1.1 — SQLite-схема, репозитории, миграции.
.DESCRIPTION
    Создаёт Entities, интерфейсы репозиториев, реализации, миграции, тесты.
    Правит App.axaml.cs (вызов DatabaseInitializer при старте).
    Идемпотентен: повторный запуск не ломает состояние.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.1.1'
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

# ============ Core/Models/Entities.cs ============
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
    Task UpsertAsync(Model model, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}

public interface IModelFileRepository
{
    Task<ModelFile?> GetAsync(string id, CancellationToken ct = default);
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

# ============ Data/SqliteConnectionFactory.cs ============
$Files['src\MiniCodex.Data\SqliteConnectionFactory.cs'] = @'
using Microsoft.Data.Sqlite;

namespace MiniCodex.Data;

public class SqliteConnectionFactory
{
    private readonly string _dbPath;
    private readonly string _connectionString;

    public SqliteConnectionFactory(string dbPath)
    {
        _dbPath = dbPath;
        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = dbPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Shared,
        }.ToString();
    }

    public string DbPath => _dbPath;

    public async Task<SqliteConnection> OpenAsync(CancellationToken ct = default)
    {
        var conn = new SqliteConnection(_connectionString);
        await conn.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "PRAGMA foreign_keys = ON;";
        await cmd.ExecuteNonQueryAsync(ct);
        return conn;
    }
}
'@

# ============ Data/Migrations/IMigration.cs ============
$Files['src\MiniCodex.Data\Migrations\IMigration.cs'] = @'
using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public interface IMigration
{
    int Version { get; }
    string Description { get; }
    Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default);
}
'@

# ============ Data/Migrations/Migration_0001_InitialSchema.cs ============
$Files['src\MiniCodex.Data\Migrations\Migration_0001_InitialSchema.cs'] = @'
using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public class Migration_0001_InitialSchema : IMigration
{
    public int Version => 1;
    public string Description => "Initial schema (Model, ModelFile, Asset, Tag, ModelTag, Collection, Setting)";

    public async Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        var sql = @"
CREATE TABLE IF NOT EXISTS Model (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    author TEXT,
    source_url TEXT,
    model_type TEXT,
    primary_model_file_id TEXT,
    status TEXT,
    difficulty INTEGER,
    real_height_mm REAL,
    model_height_mm REAL,
    scale_ratio TEXT,
    notes TEXT,
    created_at TEXT,
    updated_at TEXT
);

CREATE TABLE IF NOT EXISTS ModelFile (
    id TEXT PRIMARY KEY,
    model_id TEXT NOT NULL,
    path TEXT NOT NULL,
    file_role TEXT,
    part_name TEXT,
    file_size_bytes INTEGER,
    polygon_count INTEGER,
    FOREIGN KEY (model_id) REFERENCES Model(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS Asset (
    id TEXT PRIMARY KEY,
    model_id TEXT NOT NULL,
    asset_type TEXT,
    absolute_path TEXT NOT NULL,
    thumbnail_path TEXT,
    sort_order INTEGER,
    storage_mode TEXT,
    FOREIGN KEY (model_id) REFERENCES Model(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS Tag (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id TEXT,
    color TEXT,
    FOREIGN KEY (parent_id) REFERENCES Tag(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS ModelTag (
    model_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    PRIMARY KEY (model_id, tag_id),
    FOREIGN KEY (model_id) REFERENCES Model(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES Tag(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS Collection (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    filter_query TEXT,
    is_smart INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS Setting (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE INDEX IF NOT EXISTS IX_Model_Title ON Model(title);
CREATE INDEX IF NOT EXISTS IX_ModelFile_ModelId ON ModelFile(model_id);
CREATE INDEX IF NOT EXISTS IX_Asset_ModelId ON Asset(model_id);
CREATE INDEX IF NOT EXISTS IX_Tag_Name ON Tag(name);
";
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
'@

# ============ Data/MigrationRunner.cs ============
$Files['src\MiniCodex.Data\MigrationRunner.cs'] = @'
using Microsoft.Data.Sqlite;
using MiniCodex.Data.Migrations;

namespace MiniCodex.Data;

public class MigrationRunner
{
    private readonly IReadOnlyList<IMigration> _migrations;

    public MigrationRunner(IEnumerable<IMigration> migrations)
    {
        _migrations = migrations.OrderBy(m => m.Version).ToList();
    }

    public async Task RunAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        var current = await GetCurrentVersionAsync(conn, ct);

        foreach (var migration in _migrations)
        {
            if (migration.Version <= current) continue;

            await using (var tx = await conn.BeginTransactionAsync(ct))
            {
                await migration.ApplyAsync(conn, ct);
                await SetVersionAsync(conn, migration.Version, ct);
                await tx.CommitAsync(ct);
            }
        }
    }

    private static async Task<int> GetCurrentVersionAsync(SqliteConnection conn, CancellationToken ct)
    {
        // Убедимся, что Setting существует (миграция 1 создаст его)
        await using var check = conn.CreateCommand();
        check.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='Setting';";
        var exists = await check.ExecuteScalarAsync(ct) is string;

        if (!exists) return 0;

        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT value FROM Setting WHERE key = 'Db.SchemaVersion';";
        var raw = await cmd.ExecuteScalarAsync(ct);
        return raw is string s && int.TryParse(s, out var v) ? v : 0;
    }

    private static async Task SetVersionAsync(SqliteConnection conn, int version, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Setting(key, value) VALUES('Db.SchemaVersion', $v)
ON CONFLICT(key) DO UPDATE SET value = excluded.value;";
        cmd.Parameters.AddWithValue("$v", version.ToString());
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
'@

# ============ Data/DatabaseInitializer.cs ============
$Files['src\MiniCodex.Data\DatabaseInitializer.cs'] = @'
using MiniCodex.Data.Migrations;

namespace MiniCodex.Data;

public static class DatabaseInitializer
{
    public static async Task InitializeAsync(string dbPath, CancellationToken ct = default)
    {
        var dir = Path.GetDirectoryName(dbPath);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        var factory = new SqliteConnectionFactory(dbPath);
        await using var conn = await factory.OpenAsync(ct);

        var runner = new MigrationRunner(new IMigration[]
        {
            new Migration_0001_InitialSchema(),
        });
        await runner.RunAsync(conn, ct);
    }
}
'@

# ============ Data/Repositories/SettingRepository.cs ============
$Files['src\MiniCodex.Data\Repositories\SettingRepository.cs'] = @'
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class SettingRepository : ISettingRepository
{
    private readonly SqliteConnectionFactory _factory;

    public SettingRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<string?> GetAsync(string key, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT value FROM Setting WHERE key = $k;";
        cmd.Parameters.AddWithValue("$k", key);
        return await cmd.ExecuteScalarAsync(ct) as string;
    }

    public async Task SetAsync(string key, string value, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Setting(key, value) VALUES($k, $v)
ON CONFLICT(key) DO UPDATE SET value = excluded.value;";
        cmd.Parameters.AddWithValue("$k", key);
        cmd.Parameters.AddWithValue("$v", value);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<IReadOnlyDictionary<string, string>> GetAllAsync(CancellationToken ct = default)
    {
        var result = new Dictionary<string, string>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT key, value FROM Setting;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
            result[r.GetString(0)] = r.IsDBNull(1) ? string.Empty : r.GetString(1);
        return result;
    }
}
'@

# ============ Data/Repositories/ModelRepository.cs ============
$Files['src\MiniCodex.Data\Repositories\ModelRepository.cs'] = @'
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

# ============ Data/Repositories/ModelFileRepository.cs ============
$Files['src\MiniCodex.Data\Repositories\ModelFileRepository.cs'] = @'
using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class ModelFileRepository : IModelFileRepository
{
    private readonly SqliteConnectionFactory _factory;

    public ModelFileRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<ModelFile?> GetAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM ModelFile WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    public async Task<IReadOnlyList<ModelFile>> GetByModelAsync(string modelId, CancellationToken ct = default)
    {
        var result = new List<ModelFile>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM ModelFile WHERE model_id = $m;";
        cmd.Parameters.AddWithValue("$m", modelId);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task UpsertAsync(ModelFile f, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO ModelFile(id, model_id, path, file_role, part_name, file_size_bytes, polygon_count)
VALUES($id, $model_id, $path, $file_role, $part_name, $file_size_bytes, $polygon_count)
ON CONFLICT(id) DO UPDATE SET
    path = excluded.path, file_role = excluded.file_role, part_name = excluded.part_name,
    file_size_bytes = excluded.file_size_bytes, polygon_count = excluded.polygon_count;";
        cmd.Parameters.AddWithValue("$id", f.Id);
        cmd.Parameters.AddWithValue("$model_id", f.ModelId);
        cmd.Parameters.AddWithValue("$path", f.Path);
        cmd.Parameters.AddWithValue("$file_role", (object?)f.FileRole ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$part_name", (object?)f.PartName ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$file_size_bytes", (object?)f.FileSizeBytes ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$polygon_count", (object?)f.PolygonCount ?? DBNull.Value);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task DeleteAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM ModelFile WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static ModelFile Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        ModelId = r.GetString(1),
        Path = r.GetString(2),
        FileRole = r.IsDBNull(3) ? null : r.GetString(3),
        PartName = r.IsDBNull(4) ? null : r.GetString(4),
        FileSizeBytes = r.IsDBNull(5) ? null : r.GetInt64(5),
        PolygonCount = r.IsDBNull(6) ? null : r.GetInt32(6),
    };
}
'@

# ============ Data/Repositories/AssetRepository.cs ============
$Files['src\MiniCodex.Data\Repositories\AssetRepository.cs'] = @'
using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class AssetRepository : IAssetRepository
{
    private readonly SqliteConnectionFactory _factory;

    public AssetRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<Asset?> GetAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Asset WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    public async Task<IReadOnlyList<Asset>> GetByModelAsync(string modelId, CancellationToken ct = default)
    {
        var result = new List<Asset>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Asset WHERE model_id = $m ORDER BY sort_order;";
        cmd.Parameters.AddWithValue("$m", modelId);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task UpsertAsync(Asset a, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Asset(id, model_id, asset_type, absolute_path, thumbnail_path, sort_order, storage_mode)
VALUES($id, $model_id, $asset_type, $absolute_path, $thumbnail_path, $sort_order, $storage_mode)
ON CONFLICT(id) DO UPDATE SET
    asset_type = excluded.asset_type, absolute_path = excluded.absolute_path,
    thumbnail_path = excluded.thumbnail_path, sort_order = excluded.sort_order,
    storage_mode = excluded.storage_mode;";
        cmd.Parameters.AddWithValue("$id", a.Id);
        cmd.Parameters.AddWithValue("$model_id", a.ModelId);
        cmd.Parameters.AddWithValue("$asset_type", (object?)a.AssetType ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$absolute_path", a.AbsolutePath);
        cmd.Parameters.AddWithValue("$thumbnail_path", (object?)a.ThumbnailPath ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$sort_order", a.SortOrder);
        cmd.Parameters.AddWithValue("$storage_mode", (object?)a.StorageMode ?? DBNull.Value);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task DeleteAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM Asset WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static Asset Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        ModelId = r.GetString(1),
        AssetType = r.IsDBNull(2) ? null : r.GetString(2),
        AbsolutePath = r.GetString(3),
        ThumbnailPath = r.IsDBNull(4) ? null : r.GetString(4),
        SortOrder = r.IsDBNull(5) ? 0 : r.GetInt32(5),
        StorageMode = r.IsDBNull(6) ? null : r.GetString(6),
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

# ============ Data/Repositories/CollectionRepository.cs ============
$Files['src\MiniCodex.Data\Repositories\CollectionRepository.cs'] = @'
using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class CollectionRepository : ICollectionRepository
{
    private readonly SqliteConnectionFactory _factory;

    public CollectionRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<Collection?> GetAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Collection WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    public async Task<IReadOnlyList<Collection>> GetAllAsync(CancellationToken ct = default)
    {
        var result = new List<Collection>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Collection ORDER BY name;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task UpsertAsync(Collection c, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Collection(id, name, filter_query, is_smart) VALUES($id, $name, $filter_query, $is_smart)
ON CONFLICT(id) DO UPDATE SET name = excluded.name, filter_query = excluded.filter_query, is_smart = excluded.is_smart;";
        cmd.Parameters.AddWithValue("$id", c.Id);
        cmd.Parameters.AddWithValue("$name", c.Name);
        cmd.Parameters.AddWithValue("$filter_query", (object?)c.FilterQuery ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$is_smart", c.IsSmart ? 1 : 0);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task DeleteAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM Collection WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static Collection Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        Name = r.GetString(1),
        FilterQuery = r.IsDBNull(2) ? null : r.GetString(2),
        IsSmart = r.GetInt32(3) != 0,
    };
}
'@

# ============ Tests: DatabaseInitializerTests.cs ============
$Files['src\MiniCodex.Tests\DatabaseInitializerTests.cs'] = @'
using Microsoft.Data.Sqlite;
using MiniCodex.Data;
using Xunit;

namespace MiniCodex.Tests;

public class DatabaseInitializerTests
{
    [Fact]
    public async Task Initialize_CreatesAllTables_AndSchemaVersion()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            Assert.True(File.Exists(path));

            await using var conn = new SqliteConnection($"Data Source={path}");
            await conn.OpenAsync();

            var expected = new[] { "Model","ModelFile","Asset","Tag","ModelTag","Collection","Setting" };
            foreach (var table in expected)
            {
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name=$n;";
                cmd.Parameters.AddWithValue("$n", table);
                Assert.Equal(table, await cmd.ExecuteScalarAsync());
            }

            await using var v = conn.CreateCommand();
            v.CommandText = "SELECT value FROM Setting WHERE key='Db.SchemaVersion';";
            Assert.Equal("1", await v.ExecuteScalarAsync());
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task Initialize_IsIdempotent()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            await DatabaseInitializer.InitializeAsync(path);

            await using var conn = new SqliteConnection($"Data Source={path}");
            await conn.OpenAsync();
            await using var v = conn.CreateCommand();
            v.CommandText = "SELECT value FROM Setting WHERE key='Db.SchemaVersion';";
            Assert.Equal("1", await v.ExecuteScalarAsync());
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@

# ============ Tests: Repositories/ModelRepositoryTests.cs ============
$Files['src\MiniCodex.Tests\Repositories\ModelRepositoryTests.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Repositories;

public class ModelRepositoryTests
{
    private static async Task<(SqliteConnectionFactory, string)> NewDbAsync()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        await DatabaseInitializer.InitializeAsync(path);
        return (new SqliteConnectionFactory(path), path);
    }

    [Fact]
    public async Task Crud_RoundTrips()
    {
        var (factory, path) = await NewDbAsync();
        try
        {
            var repo = new ModelRepository(factory);
            var m = new Model { Title = "Goblin", Author = "Alice", Status = "planned", Difficulty = 3 };
            await repo.UpsertAsync(m);

            var got = await repo.GetAsync(m.Id);
            Assert.NotNull(got);
            Assert.Equal("Goblin", got!.Title);
            Assert.Equal(3, got.Difficulty);

            m.Title = "Goblin v2";
            await repo.UpsertAsync(m);
            Assert.Equal("Goblin v2", (await repo.GetAsync(m.Id))!.Title);

            var all = await repo.GetAllAsync();
            Assert.Single(all);

            await repo.DeleteAsync(m.Id);
            Assert.Null(await repo.GetAsync(m.Id));
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@

# ============ Tests: Repositories/ModelFileRepositoryTests.cs ============
$Files['src\MiniCodex.Tests\Repositories\ModelFileRepositoryTests.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Repositories;

public class ModelFileRepositoryTests
{
    [Fact]
    public async Task Crud_RoundTrips_AndFK()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            var factory = new SqliteConnectionFactory(path);
            var models = new ModelRepository(factory);
            var files = new ModelFileRepository(factory);

            var model = new Model { Title = "M" };
            await models.UpsertAsync(model);

            var f = new ModelFile { ModelId = model.Id, Path = @"C:\x.stl", FileRole = "main", PolygonCount = 1000 };
            await files.UpsertAsync(f);

            var got = await files.GetAsync(f.Id);
            Assert.NotNull(got);
            Assert.Equal("main", got!.FileRole);

            var byModel = await files.GetByModelAsync(model.Id);
            Assert.Single(byModel);

            await files.DeleteAsync(f.Id);
            Assert.Null(await files.GetAsync(f.Id));
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@

# ============ Tests: Repositories/AssetRepositoryTests.cs ============
$Files['src\MiniCodex.Tests\Repositories\AssetRepositoryTests.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Repositories;

public class AssetRepositoryTests
{
    [Fact]
    public async Task Crud_RoundTrips()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            var factory = new SqliteConnectionFactory(path);
            var models = new ModelRepository(factory);
            var assets = new AssetRepository(factory);

            var model = new Model { Title = "M" };
            await models.UpsertAsync(model);

            var a = new Asset { ModelId = model.Id, AssetType = "photo", AbsolutePath = @"C:\p.png", StorageMode = "hybrid" };
            await assets.UpsertAsync(a);

            var got = await assets.GetAsync(a.Id);
            Assert.NotNull(got);
            Assert.Equal("photo", got!.AssetType);

            Assert.Single(await assets.GetByModelAsync(model.Id));

            await assets.DeleteAsync(a.Id);
            Assert.Null(await assets.GetAsync(a.Id));
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@

# ============ Tests: Repositories/TagRepositoryTests.cs ============
$Files['src\MiniCodex.Tests\Repositories\TagRepositoryTests.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Repositories;

public class TagRepositoryTests
{
    [Fact]
    public async Task Crud_RoundTrips()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            var repo = new TagRepository(new SqliteConnectionFactory(path));

            var root = new Tag { Name = "Вселенная" };
            await repo.UpsertAsync(root);
            var child = new Tag { Name = "Гоблины", ParentId = root.Id };
            await repo.UpsertAsync(child);

            Assert.Equal(2, (await repo.GetAllAsync()).Count);
            Assert.Equal(root.Id, (await repo.GetAsync(child.Id))!.ParentId);

            await repo.DeleteAsync(root.Id);
            Assert.Null(await repo.GetAsync(root.Id));
            // child survives, parent_id → NULL (ON DELETE SET NULL)
            Assert.Null((await repo.GetAsync(child.Id))!.ParentId);
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@

# ============ Tests: Repositories/CollectionRepositoryTests.cs ============
$Files['src\MiniCodex.Tests\Repositories\CollectionRepositoryTests.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Repositories;

public class CollectionRepositoryTests
{
    [Fact]
    public async Task Crud_RoundTrips()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            var repo = new CollectionRepository(new SqliteConnectionFactory(path));

            var c = new Collection { Name = "Покрашено", FilterQuery = "{\"status\":\"painted\"}", IsSmart = true };
            await repo.UpsertAsync(c);

            var got = await repo.GetAsync(c.Id);
            Assert.NotNull(got);
            Assert.True(got!.IsSmart);

            Assert.Single(await repo.GetAllAsync());

            await repo.DeleteAsync(c.Id);
            Assert.Null(await repo.GetAsync(c.Id));
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@

# ============ Tests: Repositories/SettingRepositoryTests.cs ============
$Files['src\MiniCodex.Tests\Repositories\SettingRepositoryTests.cs'] = @'
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Repositories;

public class SettingRepositoryTests
{
    [Fact]
    public async Task Get_Set_GetAll()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            var repo = new SettingRepository(new SqliteConnectionFactory(path));

            Assert.Null(await repo.GetAsync("Test.Key"));

            await repo.SetAsync("Test.Key", "value1");
            Assert.Equal("value1", await repo.GetAsync("Test.Key"));

            await repo.SetAsync("Test.Key", "value2");
            Assert.Equal("value2", await repo.GetAsync("Test.Key"));

            var all = await repo.GetAllAsync();
            Assert.True(all.ContainsKey("Test.Key"));
            Assert.True(all.ContainsKey("Db.SchemaVersion"));
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@

# ============ README патча ============
$Files['patches\0.1.1\README.md'] = @'
# Патч 0.1.1 — SQLite-схема, репозитории, миграции

**Итерация:** 0.1 (Фундамент) · **Статус:** реализован

## Что делает

- Создаёт Entity-классы (`Model`, `ModelFile`, `Asset`, `Tag`, `Collection`) в Core.
- Создаёт интерфейсы репозиториев в Core.
- Реализует `SqliteConnectionFactory`, `MigrationRunner`, `DatabaseInitializer`, `Migration_0001_InitialSchema`.
- Реализует 6 репозиториев (Setting, Model, ModelFile, Asset, Tag, Collection).
- Правка `App.axaml.cs`: вызов `DatabaseInitializer.InitializeAsync(App.Paths.LibraryDb)` перед показом MainWindow.
- Юнит-тесты: инициализация БД, идемпотентность, CRUD по каждому репозиторию.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.1.1\patch_0.1.1.ps1"

## DoD

- `dotnet build src/MiniCodex.sln` — успешно.
- `dotnet test src/MiniCodex.sln` — все тесты зелёные (≈8 тестов).
- При первом запуске приложения `data/library.db` создаётся с 7 таблицами + `Db.SchemaVersion = 1`.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml.cs')
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # --- Правка App.axaml.cs: вызов DatabaseInitializer ---
    $appCs = Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml.cs'
    $axContent = [IO.File]::ReadAllText($appCs, [Text.Encoding]::UTF8)
    if ($axContent -notmatch 'DatabaseInitializer\.InitializeAsync') {
        # Добавляем using и вызов перед созданием MainWindow
        $axContent = $axContent -replace '(using MiniCodex\.App\.Services;)', "`$1`r`nusing MiniCodex.Data;"
        $axContent = $axContent -replace '(\s*)(desktop\.MainWindow = new MainWindow\(\);)', "`$1DatabaseInitializer.InitializeAsync(Paths.LibraryDb).GetAwaiter().GetResult();`r`n`$1`$2"
        Write-Text -Path $appCs -Content $axContent
        Write-Log 'updated: src\MiniCodex.App\App.axaml.cs (DatabaseInitializer.InitializeAsync)'
    } else {
        Write-Log 'App.axaml.cs: DatabaseInitializer уже подключён, пропускаю.' 'WARN'
    }

    # --- CHANGELOG ---
    $marker = '<!-- patch 0.1.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n## [0.1.1] - 2026-11-10`n`n### Added`n- SQLite-схема (Model, ModelFile, Asset, Tag, ModelTag, Collection, Setting).`n- DatabaseInitializer + MigrationRunner + Migration_0001_InitialSchema.`n- 6 репозиториев с CRUD.`n- Юнит-тесты инициализации, идемпотентности и CRUD.`n"
            $cl = $cl -replace '(?m)^(## \[0\.1\.0a\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.1.1.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
    Write-Log 'Следующий шаг: dotnet build + dotnet test'
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    Write-Log "Восстановление: скопируйте файлы из '$BackupDir' обратно в '$ProjectRoot'." 'ERROR'
    exit 1
}
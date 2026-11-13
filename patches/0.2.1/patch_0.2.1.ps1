#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.2.1 — Фоновое сканирование папок-источников.
.DESCRIPTION
    Переносит IMeshLoader/MeshInfo в Core (исправление ADR).
    Добавляет миграцию 2 (last_write_time_utc), GetByPathAsync, ScannerService.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.2.1'
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

# ============ Core/Models/MeshInfo.cs (новое место) ============
$Files['src\MiniCodex.Core\Models\MeshInfo.cs'] = @'
namespace MiniCodex.Core.Models;

public class MeshInfo
{
    public int PolygonCount { get; set; }
    public long FileSizeBytes { get; set; }
    public float[] BoundingBoxMin { get; set; } = Array.Empty<float>();
    public float[] BoundingBoxMax { get; set; } = Array.Empty<float>();

    public float SizeX => BoundingBoxMax.Length > 0 ? BoundingBoxMax[0] - BoundingBoxMin[0] : 0;
    public float SizeY => BoundingBoxMax.Length > 1 ? BoundingBoxMax[1] - BoundingBoxMin[1] : 0;
    public float SizeZ => BoundingBoxMax.Length > 2 ? BoundingBoxMax[2] - BoundingBoxMin[2] : 0;
}
'@

# ============ Core/Services/IMeshLoader.cs (новое место) ============
$Files['src\MiniCodex.Core\Services\IMeshLoader.cs'] = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IMeshLoader
{
    MeshInfo? Load(string filePath);
    IReadOnlyCollection<string> SupportedExtensions { get; }
}
'@

# ============ Core/Services/ScanProgress.cs ============
$Files['src\MiniCodex.Core\Services\ScanProgress.cs'] = @'
namespace MiniCodex.Core.Services;

public class ScanProgress
{
    public int TotalFiles { get; set; }
    public int ProcessedFiles { get; set; }
    public string? CurrentFile { get; set; }
    public int Added { get; set; }
    public int Updated { get; set; }
    public int Skipped { get; set; }
    public int Errors { get; set; }
    public string? LastError { get; set; }

    public double Percent => TotalFiles > 0 ? (double)ProcessedFiles / TotalFiles * 100 : 0;
}
'@

# ============ Core/Services/IScannerService.cs ============
$Files['src\MiniCodex.Core\Services\IScannerService.cs'] = @'
namespace MiniCodex.Core.Services;

public interface IScannerService
{
    Task ScanAsync(
        IEnumerable<string> rootFolders,
        IProgress<ScanProgress>? progress = null,
        CancellationToken ct = default);
}
'@

# ============ Core/Services/ScannerService.cs ============
$Files['src\MiniCodex.Core\Services\ScannerService.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class ScannerService : IScannerService
{
    private readonly IMeshLoader _meshLoader;
    private readonly IModelRepository _modelRepo;
    private readonly IModelFileRepository _fileRepo;

    public ScannerService(IMeshLoader meshLoader, IModelRepository modelRepo, IModelFileRepository fileRepo)
    {
        _meshLoader = meshLoader;
        _modelRepo = modelRepo;
        _fileRepo = fileRepo;
    }

    public async Task ScanAsync(
        IEnumerable<string> rootFolders,
        IProgress<ScanProgress>? progress = null,
        CancellationToken ct = default)
    {
        var report = progress ?? new Progress<ScanProgress>();
        var state = new ScanProgress();

        var files = new List<FileInfo>();
        foreach (var root in rootFolders)
        {
            if (!Directory.Exists(root))
            {
                state.Errors++;
                state.LastError = $"Folder not found: {root}";
                report.Report(state);
                continue;
            }

            try
            {
                foreach (var file in Directory.EnumerateFiles(root, "*.*", SearchOption.AllDirectories))
                {
                    var ext = Path.GetExtension(file).TrimStart('.').ToLowerInvariant();
                    if (_meshLoader.SupportedExtensions.Contains(ext))
                    {
                        files.Add(new FileInfo(file));
                        if (ct.IsCancellationRequested) return;
                    }
                }
            }
            catch (Exception ex)
            {
                state.Errors++;
                state.LastError = ex.Message;
                report.Report(state);
            }
        }

        state.TotalFiles = files.Count;
        report.Report(state);

        foreach (var fi in files)
        {
            if (ct.IsCancellationRequested) return;

            state.CurrentFile = fi.FullName;
            try
            {
                var existing = await _fileRepo.GetByPathAsync(fi.FullName, ct);
                if (existing != null &&
                    existing.FileSizeBytes == fi.Length &&
                    existing.LastWriteTimeUtc == fi.LastWriteTimeUtc)
                {
                    state.Skipped++;
                }
                else
                {
                    var info = _meshLoader.Load(fi.FullName);
                    if (info == null)
                    {
                        state.Errors++;
                        state.LastError = $"Parse failed: {fi.FullName}";
                    }
                    else if (existing != null)
                    {
                        existing.FileSizeBytes = info.FileSizeBytes;
                        existing.LastWriteTimeUtc = fi.LastWriteTimeUtc;
                        existing.PolygonCount = info.PolygonCount;
                        await _fileRepo.UpsertAsync(existing, ct);

                        var model = await _modelRepo.GetAsync(existing.ModelId, ct);
                        if (model != null)
                        {
                            model.UpdatedAt = DateTime.UtcNow;
                            await _modelRepo.UpsertAsync(model, ct);
                        }
                        state.Updated++;
                    }
                    else
                    {
                        var model = new Model
                        {
                            Title = Path.GetFileNameWithoutExtension(fi.Name),
                            CreatedAt = DateTime.UtcNow,
                            UpdatedAt = DateTime.UtcNow,
                        };
                        await _modelRepo.UpsertAsync(model, ct);

                        var newFile = new ModelFile
                        {
                            ModelId = model.Id,
                            Path = fi.FullName,
                            FileRole = "main",
                            FileSizeBytes = info.FileSizeBytes,
                            PolygonCount = info.PolygonCount,
                            LastWriteTimeUtc = fi.LastWriteTimeUtc,
                        };
                        await _fileRepo.UpsertAsync(newFile, ct);

                        model.PrimaryModelFileId = newFile.Id;
                        await _modelRepo.UpsertAsync(model, ct);

                        state.Added++;
                    }
                }
            }
            catch (Exception ex)
            {
                state.Errors++;
                state.LastError = $"{fi.Name}: {ex.Message}";
            }

            state.ProcessedFiles++;
            report.Report(state);
        }
    }
}
'@

# ============ Core/Models/Entities.cs (обновление) ============
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

# ============ Core/Repositories/IRepositories.cs (обновление) ============
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

# ============ Data/Migrations/Migration_0002_ModelFile_LastWriteTime.cs ============
$Files['src\MiniCodex.Data\Migrations\Migration_0002_ModelFile_LastWriteTime.cs'] = @'
using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public class Migration_0002_ModelFile_LastWriteTime : IMigration
{
    public int Version => 2;
    public string Description => "Add last_write_time_utc to ModelFile";

    public async Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "ALTER TABLE ModelFile ADD COLUMN last_write_time_utc TEXT;";
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
'@

# ============ Data/DatabaseInitializer.cs (обновление) ============
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
            new Migration_0002_ModelFile_LastWriteTime(),
        });
        await runner.RunAsync(conn, ct);
    }
}
'@

# ============ Data/Repositories/ModelFileRepository.cs (обновление) ============
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

    public async Task<ModelFile?> GetByPathAsync(string path, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM ModelFile WHERE path = $path;";
        cmd.Parameters.AddWithValue("$path", path);
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
INSERT INTO ModelFile(id, model_id, path, file_role, part_name, file_size_bytes, polygon_count, last_write_time_utc)
VALUES($id, $model_id, $path, $file_role, $part_name, $file_size_bytes, $polygon_count, $last_write_time_utc)
ON CONFLICT(id) DO UPDATE SET
    path = excluded.path, file_role = excluded.file_role, part_name = excluded.part_name,
    file_size_bytes = excluded.file_size_bytes, polygon_count = excluded.polygon_count,
    last_write_time_utc = excluded.last_write_time_utc;";
        cmd.Parameters.AddWithValue("$id", f.Id);
        cmd.Parameters.AddWithValue("$model_id", f.ModelId);
        cmd.Parameters.AddWithValue("$path", f.Path);
        cmd.Parameters.AddWithValue("$file_role", (object?)f.FileRole ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$part_name", (object?)f.PartName ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$file_size_bytes", (object?)f.FileSizeBytes ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$polygon_count", (object?)f.PolygonCount ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$last_write_time_utc", f.LastWriteTimeUtc.HasValue ? f.LastWriteTimeUtc.Value.ToString("o") : DBNull.Value);
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
        LastWriteTimeUtc = r.IsDBNull(7) ? null : DateTime.Parse(r.GetString(7), null, System.Globalization.DateTimeStyles.RoundtripKind),
    };
}
'@

# ============ Render/Loaders/AssimpMeshLoader.cs (обновление namespace) ============
$Files['src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs'] = @'
using Assimp;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;

namespace MiniCodex.Render.Loaders;

public class AssimpMeshLoader : IMeshLoader
{
    private static readonly HashSet<string> _extensions = new(StringComparer.OrdinalIgnoreCase)
    {
        "stl", "obj", "3mf", "ply"
    };

    public IReadOnlyCollection<string> SupportedExtensions => _extensions;

    public MeshInfo? Load(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath)) return null;

        try
        {
            using var context = new AssimpContext();
            var scene = context.ImportFile(filePath,
                PostProcessSteps.Triangulate | PostProcessSteps.JoinIdenticalVertices);

            if (scene == null || !scene.HasMeshes) return null;

            var polygonCount = 0;
            var min = new Vector3D(float.MaxValue, float.MaxValue, float.MaxValue);
            var max = new Vector3D(float.MinValue, float.MinValue, float.MinValue);
            var hasVertices = false;

            foreach (var mesh in scene.Meshes)
            {
                polygonCount += mesh.FaceCount;
                foreach (var v in mesh.Vertices)
                {
                    hasVertices = true;
                    if (v.X < min.X) min.X = v.X;
                    if (v.Y < min.Y) min.Y = v.Y;
                    if (v.Z < min.Z) min.Z = v.Z;
                    if (v.X > max.X) max.X = v.X;
                    if (v.Y > max.Y) max.Y = v.Y;
                    if (v.Z > max.Z) max.Z = v.Z;
                }
            }

            if (!hasVertices) return null;

            return new MeshInfo
            {
                PolygonCount = polygonCount,
                FileSizeBytes = new FileInfo(filePath).Length,
                BoundingBoxMin = new[] { min.X, min.Y, min.Z },
                BoundingBoxMax = new[] { max.X, max.Y, max.Z },
            };
        }
        catch { return null; }
    }
}
'@

# ============ Tests/Render/MeshLoaderTests.cs (обновление namespace) ============
$Files['src\MiniCodex.Tests\Render\MeshLoaderTests.cs'] = @'
using MiniCodex.Render.Loaders;
using Xunit;

namespace MiniCodex.Tests.Render;

public class MeshLoaderTests
{
    private const string AsciiStl = @"solid test
  facet normal 0 0 1
    outer loop
      vertex 0 0 0
      vertex 1 0 0
      vertex 0 1 0
    endloop
  endfacet
endsolid test
";

    private const string SimpleObj = @"v 0 0 0
v 1 0 0
v 0 1 0
f 1 2 3
";

    [Fact]
    public void Load_AsciiStl_ReturnsOnePolygonAndBox()
    {
        var path = Path.GetTempFileName() + ".stl";
        try
        {
            File.WriteAllText(path, AsciiStl);
            var loader = new AssimpMeshLoader();
            var info = loader.Load(path);

            Assert.NotNull(info);
            Assert.Equal(1, info!.PolygonCount);
            Assert.Equal(0, info.BoundingBoxMin[0], 3);
            Assert.Equal(1, info.BoundingBoxMax[0], 3);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public void Load_SimpleObj_ReturnsOnePolygon()
    {
        var path = Path.GetTempFileName() + ".obj";
        try
        {
            File.WriteAllText(path, SimpleObj);
            var loader = new AssimpMeshLoader();
            var info = loader.Load(path);
            Assert.NotNull(info);
            Assert.Equal(1, info!.PolygonCount);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public void Load_Nonexistent_ReturnsNull()
    {
        var loader = new AssimpMeshLoader();
        Assert.Null(loader.Load(@"C:\definitely\not\here\missing.stl"));
    }

    [Fact]
    public void Load_CorruptFile_ReturnsNull()
    {
        var path = Path.GetTempFileName() + ".stl";
        try
        {
            File.WriteAllText(path, "not a mesh at all");
            var loader = new AssimpMeshLoader();
            Assert.Null(loader.Load(path));
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@

# ============ Tests/Services/ScannerServiceTests.cs ============
$Files['src\MiniCodex.Tests\Services\ScannerServiceTests.cs'] = @'
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Services;

public class FakeMeshLoader : IMeshLoader
{
    public IReadOnlyCollection<string> SupportedExtensions => new[] { "stl", "obj" };
    public MeshInfo? Load(string filePath) => new()
    {
        PolygonCount = 1,
        FileSizeBytes = new FileInfo(filePath).Length,
        BoundingBoxMin = new[] { 0f, 0f, 0f },
        BoundingBoxMax = new[] { 1f, 1f, 1f },
    };
}

public class ScannerServiceTests : IDisposable
{
    private readonly string _dbPath;
    private readonly string _tempDir;
    private readonly SqliteConnectionFactory _factory;
    private readonly ScannerService _scanner;
    private readonly IModelRepository _models;
    private readonly IModelFileRepository _files;

    public ScannerServiceTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        _tempDir = Path.Combine(Path.GetTempPath(), $"minicodex_scan_{Guid.NewGuid()}");
        Directory.CreateDirectory(_tempDir);
        DatabaseInitializer.InitializeAsync(_dbPath).GetAwaiter().GetResult();
        _factory = new SqliteConnectionFactory(_dbPath);
        _models = new ModelRepository(_factory);
        _files = new ModelFileRepository(_factory);
        _scanner = new ScannerService(new FakeMeshLoader(), _models, _files);
    }

    public void Dispose()
    {
        try { File.Delete(_dbPath); } catch { }
        try { Directory.Delete(_tempDir, true); } catch { }
    }

    [Fact]
    public async Task Scan_AddsNewModels()
    {
        File.WriteAllText(Path.Combine(_tempDir, "a.stl"), "x");
        File.WriteAllText(Path.Combine(_tempDir, "b.obj"), "x");

        await _scanner.ScanAsync(new[] { _tempDir });

        var all = await _models.GetAllAsync();
        Assert.Equal(2, all.Count);
    }

    [Fact]
    public async Task Scan_IsIncremental()
    {
        File.WriteAllText(Path.Combine(_tempDir, "a.stl"), "x");
        await _scanner.ScanAsync(new[] { _tempDir });

        var progress = new Progress<ScanProgress>();
        await _scanner.ScanAsync(new[] { _tempDir }, progress);

        var all = await _models.GetAllAsync();
        Assert.Single(all);
    }

    [Fact]
    public async Task Scan_UpdatesOnFileChange()
    {
        var path = Path.Combine(_tempDir, "a.stl");
        File.WriteAllText(path, "x");
        await _scanner.ScanAsync(new[] { _tempDir });

        await Task.Delay(50);
        File.WriteAllText(path, "longer content");
        File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddSeconds(5));

        await _scanner.ScanAsync(new[] { _tempDir });

        var all = await _models.GetAllAsync();
        Assert.Single(all);
    }

    [Fact]
    public async Task Scan_HandlesMissingFolder()
    {
        var progress = new Progress<ScanProgress>();
        await _scanner.ScanAsync(new[] { @"C:\nonexistent\folder\xyz" }, progress);
        var all = await _models.GetAllAsync();
        Assert.Empty(all);
    }

    [Fact]
    public async Task Scan_IgnoresUnsupportedExtensions()
    {
        File.WriteAllText(Path.Combine(_tempDir, "a.txt"), "x");
        File.WriteAllText(Path.Combine(_tempDir, "b.stl"), "x");
        await _scanner.ScanAsync(new[] { _tempDir });
        var all = await _models.GetAllAsync();
        Assert.Single(all);
    }
}
'@

# ============ README патча ============
$Files['patches\0.2.1\README.md'] = @'
# Патч 0.2.1 — Фоновое сканирование

**Итерация:** 0.2 · **Статус:** реализован

## Что делает

- **Исправление ADR:** перенос `MeshInfo` и `IMeshLoader` в `MiniCodex.Core` (Core больше не зависит от Render).
- Миграция 2: колонка `last_write_time_utc` в `ModelFile`.
- `IModelFileRepository.GetByPathAsync` — поиск существующего файла.
- `ScannerService`: рекурсивный поиск по папкам, инкрементальность (пропуск неизменённых), обновление при изменении, обработка недоступных папок, отмена через `CancellationToken`, прогресс `ScanProgress`.
- Тесты: 5 (добавление, инкрементальность, обновление, отсутствующая папка, игнорирование неподдерживаемых).

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.1\patch_0.2.1.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 17 тестов (12 старых + 5 новых), все зелёные.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    $toBackup = @(
        'src\MiniCodex.Core\Models\Entities.cs',
        'src\MiniCodex.Core\Repositories\IRepositories.cs',
        'src\MiniCodex.Data\DatabaseInitializer.cs',
        'src\MiniCodex.Data\Repositories\ModelFileRepository.cs',
        'src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs',
        'src\MiniCodex.Tests\Render\MeshLoaderTests.cs',
        'CHANGELOG.md'
    )
    foreach ($rel in $toBackup) { Backup-File (Join-Path $ProjectRoot $rel) }

    # Удаление старых файлов (переехали в Core)
    $toDelete = @(
        'src\MiniCodex.Render\Models\MeshInfo.cs',
        'src\MiniCodex.Render\Loaders\IMeshLoader.cs'
    )
    foreach ($rel in $toDelete) {
        $full = Join-Path $ProjectRoot $rel
        if (Test-Path -LiteralPath $full) {
            Remove-Item -LiteralPath $full -Force
            Write-Log "deleted: $rel (переехал в Core)"
        }
    }

    # Создание/обновление файлов
    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # CHANGELOG
    $marker = '<!-- patch 0.2.1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n## [0.2.1] - 2026-11-10`n`n### Added`n- ScannerService с инкрементальным сканированием.`n- ScanProgress для UI.`n- Миграция 2 (last_write_time_utc).`n- GetByPathAsync в ModelFileRepository.`n- 5 тестов сканера.`n`n### Changed`n- MeshInfo и IMeshLoader перенесены в Core (ADR fix).`n"
            $cl = $cl -replace '(?m)^(## \[0\.2\.0\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.2.1.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}
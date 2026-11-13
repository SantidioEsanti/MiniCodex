using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Core.Repositories;
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
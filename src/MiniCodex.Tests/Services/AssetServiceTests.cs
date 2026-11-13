using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Core.Repositories;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Services;

public class StubThumbnailGenerator : IAssetThumbnailGenerator
{
    public byte[] Generate(string sourcePath, string assetType, int maxSize)
        => new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
}

public class AssetServiceTests : IDisposable
{
    private readonly string _dbPath;
    private readonly string _tempRoot;
    private readonly string _assetsRoot;
    private readonly string _thumbsRoot;
    private readonly SqliteConnectionFactory _factory;
    private readonly AssetService _service;
    private readonly IModelRepository _models;
    private readonly IModelFileRepository _files;
    private readonly IAssetRepository _assets;

    public AssetServiceTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        _tempRoot = Path.Combine(Path.GetTempPath(), $"minicodex_assoc_{Guid.NewGuid()}");
        _assetsRoot = Path.Combine(_tempRoot, "assets");
        _thumbsRoot = Path.Combine(_tempRoot, "thumbs");
        Directory.CreateDirectory(_tempRoot);
        Directory.CreateDirectory(_assetsRoot);
        Directory.CreateDirectory(_thumbsRoot);
        DatabaseInitializer.InitializeAsync(_dbPath).GetAwaiter().GetResult();
        _factory = new SqliteConnectionFactory(_dbPath);
        _models = new ModelRepository(_factory);
        _files = new ModelFileRepository(_factory);
        _assets = new AssetRepository(_factory);
        _service = new AssetService(_assets, _files, new StubThumbnailGenerator(), _assetsRoot, _thumbsRoot);
    }

    public void Dispose()
    {
        try { File.Delete(_dbPath); } catch { }
        try { Directory.Delete(_tempRoot, true); } catch { }
    }

    [Fact]
    public async Task Import_CopiesFileAndCreatesRecord()
    {
        var model = new Model { Title = "M" };
        await _models.UpsertAsync(model);

        var src = Path.Combine(_tempRoot, "photo.png");
        File.WriteAllBytes(src, new byte[] { 1, 2, 3 });

        var asset = await _service.ImportAsync(model.Id, src, "photo");

        Assert.NotNull(asset);
        Assert.True(File.Exists(asset.AbsolutePath));
        Assert.StartsWith(Path.Combine(_assetsRoot, model.Id), asset.AbsolutePath);
        Assert.Equal("photo", asset.AssetType);
        Assert.Equal("hybrid", asset.StorageMode);

        var fromDb = await _assets.GetAsync(asset.Id);
        Assert.NotNull(fromDb);
    }

    [Fact]
    public async Task RemoveFromCard_DeletesRecordButKeepsFile()
    {
        var model = new Model { Title = "M" };
        await _models.UpsertAsync(model);

        var src = Path.Combine(_tempRoot, "photo.png");
        File.WriteAllBytes(src, new byte[] { 1, 2, 3 });
        var asset = await _service.ImportAsync(model.Id, src, "photo");

        var fileOnDisk = asset.AbsolutePath;
        Assert.True(File.Exists(fileOnDisk));

        await _service.RemoveFromCardAsync(asset.Id);

        Assert.Null(await _assets.GetAsync(asset.Id));
        Assert.True(File.Exists(fileOnDisk)); // ключевое: файл остаётся на диске
    }

    [Fact]
    public async Task AutoLink_FindsSiblingFiles_AndImports()
    {
        var modelDir = Path.Combine(_tempRoot, "model_dir");
        Directory.CreateDirectory(modelDir);
        var stl = Path.Combine(modelDir, "hero_001.stl");
        File.WriteAllBytes(stl, new byte[] { 0 });

        var model = new Model { Title = "hero_001" };
        await _models.UpsertAsync(model);
        var modelFile = new ModelFile
        {
            ModelId = model.Id,
            Path = stl,
            FileRole = "main",
            FileSizeBytes = 1,
        };
        await _files.UpsertAsync(modelFile);
        model.PrimaryModelFileId = modelFile.Id;
        await _models.UpsertAsync(model);

        File.WriteAllBytes(Path.Combine(modelDir, "hero_001_ref.png"), new byte[] { 1 });
        File.WriteAllBytes(Path.Combine(modelDir, "hero_001_render.jpg"), new byte[] { 2 });
        File.WriteAllBytes(Path.Combine(modelDir, "other_thing.png"), new byte[] { 3 });

        var found = await _service.AutoLinkAsync(model.Id);

        Assert.Equal(2, found.Count);
        var all = await _assets.GetByModelAsync(model.Id);
        Assert.Equal(2, all.Count);
        Assert.All(all, a => Assert.Equal("reference", a.AssetType));
        Assert.All(all, a => Assert.True(File.Exists(a.AbsolutePath)));
    }

    [Fact]
    public async Task EnsureThumbnail_CreatesPngFile()
    {
        var model = new Model { Title = "M" };
        await _models.UpsertAsync(model);

        var src = Path.Combine(_tempRoot, "photo.png");
        File.WriteAllBytes(src, new byte[] { 0x89, 0x50, 0x4E, 0x47 });
        var asset = await _service.ImportAsync(model.Id, src, "photo");

        var thumbPath = await _service.EnsureThumbnailAsync(asset);

        Assert.NotNull(thumbPath);
        Assert.True(File.Exists(thumbPath));
        Assert.EndsWith(".png", thumbPath);
    }
}
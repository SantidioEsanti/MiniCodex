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
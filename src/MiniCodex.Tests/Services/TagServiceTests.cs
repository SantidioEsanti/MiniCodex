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
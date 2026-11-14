using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests;

public class CollectionServiceTests
{
    private static async Task<(string path, CollectionService svc)> CreateServiceAsync()
    {
        var path = Path.Combine(Path.GetTempPath(), "minicodex_coll_" + Guid.NewGuid().ToString("N") + ".db");
        await DatabaseInitializer.InitializeAsync(path);
        var factory = new SqliteConnectionFactory(path);
        var repo    = new CollectionRepository(factory);
        return (path, new CollectionService(repo));
    }

    [Fact]
    public async Task SaveSmart_RoundTripsFilter()
    {
        var (path, svc) = await CreateServiceAsync();
        try
        {
            var filter = new SmartCollectionFilter("dragon", "tag-1", "Orcs");
            var saved  = await svc.SaveSmartAsync("My Dragons", filter);
            Assert.False(string.IsNullOrEmpty(saved.Id));

            var all = await svc.GetSmartAsync();
            Assert.Single(all);
            var loaded = CollectionService.DeserializeFilter(all[0].FilterQuery);
            Assert.Equal("dragon", loaded.Search);
            Assert.Equal("tag-1",  loaded.TagId);
            Assert.Equal("Orcs",   loaded.TagName);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task SaveSmart_UpdatesExistingByName()
    {
        var (path, svc) = await CreateServiceAsync();
        try
        {
            var a = await svc.SaveSmartAsync("Filter A", new SmartCollectionFilter("a", null, null));
            var b = await svc.SaveSmartAsync("Filter A", new SmartCollectionFilter("b", "tag-2", "Elves"));
            Assert.Equal(a.Id, b.Id);

            var all = await svc.GetSmartAsync();
            Assert.Single(all);
            var loaded = CollectionService.DeserializeFilter(all[0].FilterQuery);
            Assert.Equal("b",     loaded.Search);
            Assert.Equal("tag-2", loaded.TagId);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task Delete_RemovesCollection()
    {
        var (path, svc) = await CreateServiceAsync();
        try
        {
            var c = await svc.SaveSmartAsync("ToDelete", new SmartCollectionFilter("x", null, null));
            await svc.DeleteAsync(c.Id);
            var all = await svc.GetSmartAsync();
            Assert.Empty(all);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public void DeserializeFilter_HandlesNullAndEmpty()
    {
        var a = CollectionService.DeserializeFilter(null);
        var b = CollectionService.DeserializeFilter("");
        Assert.True(a.IsEmpty);
        Assert.True(b.IsEmpty);
    }

    [Fact]
    public void SmartCollectionFilter_IsEmpty_Works()
    {
        Assert.True(SmartCollectionFilter.Empty.IsEmpty);
        Assert.False(new SmartCollectionFilter("x", null, null).IsEmpty);
        Assert.False(new SmartCollectionFilter(null, "id", null).IsEmpty);
    }
}
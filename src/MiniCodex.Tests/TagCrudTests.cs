using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests;

public class TagCrudTests
{
    private static async Task<(string path, TagRepository tags, ModelTagRepository modelTags, TagService svc)> CreateEnvAsync()
    {
        var path = Path.Combine(Path.GetTempPath(), "minicodex_tag_" + Guid.NewGuid().ToString("N") + ".db");
        await DatabaseInitializer.InitializeAsync(path);
        var factory   = new SqliteConnectionFactory(path);
        var tags      = new TagRepository(factory);
        var modelTags = new ModelTagRepository(factory);
        var svc       = new TagService(tags, modelTags);
        return (path, tags, modelTags, svc);
    }

    [Fact]
    public async Task RenameAsync_UpdatesName()
    {
        var (path, tags, _, svc) = await CreateEnvAsync();
        try
        {
            var t = await svc.CreateOrGetAsync("Old");
            await svc.RenameAsync(t.Id, "New");
            var all = await tags.GetAllAsync();
            Assert.Single(all);
            Assert.Equal("New", all[0].Name);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task RenameAsync_EmptyName_NoOp()
    {
        var (path, tags, _, svc) = await CreateEnvAsync();
        try
        {
            var t = await svc.CreateOrGetAsync("Keep");
            await svc.RenameAsync(t.Id, "");
            await svc.RenameAsync(t.Id, "   ");
            var reloaded = await tags.GetAsync(t.Id);
            Assert.NotNull(reloaded);
            Assert.Equal("Keep", reloaded!.Name);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task RenameAsync_EmptyId_NoOp()
    {
        var (path, _, _, svc) = await CreateEnvAsync();
        try
        {
            await svc.RenameAsync("", "New");
            await svc.RenameAsync("   ", "New");
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task DeleteAsync_RemovesTagAndAssociations()
    {
        var (path, tags, modelTags, svc) = await CreateEnvAsync();
        try
        {
            var t = await svc.CreateOrGetAsync("ToDelete");
            var models = new ModelRepository(new SqliteConnectionFactory(path));
            await models.UpsertAsync(new MiniCodex.Core.Models.Model { Id = "fake-model-1", Title = "Fake 1" });
            await models.UpsertAsync(new MiniCodex.Core.Models.Model { Id = "fake-model-2", Title = "Fake 2" });
            await modelTags.AddAsync("fake-model-1", t.Id);
            await modelTags.AddAsync("fake-model-2", t.Id);
            Assert.True(await modelTags.ExistsAsync("fake-model-1", t.Id));
            Assert.True(await modelTags.ExistsAsync("fake-model-2", t.Id));

            await svc.DeleteAsync(t.Id);

            Assert.Empty(await tags.GetAllAsync());
            Assert.False(await modelTags.ExistsAsync("fake-model-1", t.Id));
            Assert.False(await modelTags.ExistsAsync("fake-model-2", t.Id));
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task DeleteAsync_EmptyId_NoOp()
    {
        var (path, tags, _, svc) = await CreateEnvAsync();
        try
        {
            var t = await svc.CreateOrGetAsync("Survivor");
            await svc.DeleteAsync("");
            await svc.DeleteAsync("   ");
            Assert.Single(await tags.GetAllAsync());
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
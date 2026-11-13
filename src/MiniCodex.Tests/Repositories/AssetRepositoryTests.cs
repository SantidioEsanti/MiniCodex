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
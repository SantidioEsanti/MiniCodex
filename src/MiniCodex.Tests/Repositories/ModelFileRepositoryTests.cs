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
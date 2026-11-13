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
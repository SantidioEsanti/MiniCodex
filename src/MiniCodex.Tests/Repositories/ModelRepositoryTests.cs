using MiniCodex.Core.Models;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Repositories;

public class ModelRepositoryTests
{
    private static async Task<(SqliteConnectionFactory, string)> NewDbAsync()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        await DatabaseInitializer.InitializeAsync(path);
        return (new SqliteConnectionFactory(path), path);
    }

    [Fact]
    public async Task Crud_RoundTrips()
    {
        var (factory, path) = await NewDbAsync();
        try
        {
            var repo = new ModelRepository(factory);
            var m = new Model { Title = "Goblin", Author = "Alice", Status = "planned", Difficulty = 3 };
            await repo.UpsertAsync(m);

            var got = await repo.GetAsync(m.Id);
            Assert.NotNull(got);
            Assert.Equal("Goblin", got!.Title);
            Assert.Equal(3, got.Difficulty);

            m.Title = "Goblin v2";
            await repo.UpsertAsync(m);
            Assert.Equal("Goblin v2", (await repo.GetAsync(m.Id))!.Title);

            var all = await repo.GetAllAsync();
            Assert.Single(all);

            await repo.DeleteAsync(m.Id);
            Assert.Null(await repo.GetAsync(m.Id));
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
using MiniCodex.Core.Models;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Repositories;

public class TagRepositoryTests
{
    [Fact]
    public async Task Crud_RoundTrips()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            var repo = new TagRepository(new SqliteConnectionFactory(path));

            var root = new Tag { Name = "Вселенная" };
            await repo.UpsertAsync(root);
            var child = new Tag { Name = "Гоблины", ParentId = root.Id };
            await repo.UpsertAsync(child);

            Assert.Equal(2, (await repo.GetAllAsync()).Count);
            Assert.Equal(root.Id, (await repo.GetAsync(child.Id))!.ParentId);

            await repo.DeleteAsync(root.Id);
            Assert.Null(await repo.GetAsync(root.Id));
            // child survives, parent_id → NULL (ON DELETE SET NULL)
            Assert.Null((await repo.GetAsync(child.Id))!.ParentId);
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Repositories;

public class SettingRepositoryTests
{
    [Fact]
    public async Task Get_Set_GetAll()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            var repo = new SettingRepository(new SqliteConnectionFactory(path));

            Assert.Null(await repo.GetAsync("Test.Key"));

            await repo.SetAsync("Test.Key", "value1");
            Assert.Equal("value1", await repo.GetAsync("Test.Key"));

            await repo.SetAsync("Test.Key", "value2");
            Assert.Equal("value2", await repo.GetAsync("Test.Key"));

            var all = await repo.GetAllAsync();
            Assert.True(all.ContainsKey("Test.Key"));
            Assert.True(all.ContainsKey("Db.SchemaVersion"));
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
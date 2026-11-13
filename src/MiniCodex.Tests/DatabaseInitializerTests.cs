using Microsoft.Data.Sqlite;
using MiniCodex.Data;
using Xunit;

namespace MiniCodex.Tests;

public class DatabaseInitializerTests
{
    [Fact]
    public async Task Initialize_CreatesAllTables_AndSchemaVersion()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            Assert.True(File.Exists(path));

            await using var conn = new SqliteConnection($"Data Source={path}");
            await conn.OpenAsync();

            var expected = new[] { "Model","ModelFile","Asset","Tag","ModelTag","Collection","Setting" };
            foreach (var table in expected)
            {
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name=$n;";
                cmd.Parameters.AddWithValue("$n", table);
                Assert.Equal(table, await cmd.ExecuteScalarAsync());
            }

            await using var v = conn.CreateCommand();
            v.CommandText = "SELECT value FROM Setting WHERE key='Db.SchemaVersion';";
            Assert.Equal(DatabaseInitializer.LatestSchemaVersion.ToString(), await v.ExecuteScalarAsync());
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task Initialize_IsIdempotent()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            await DatabaseInitializer.InitializeAsync(path);

            await using var conn = new SqliteConnection($"Data Source={path}");
            await conn.OpenAsync();
            await using var v = conn.CreateCommand();
            v.CommandText = "SELECT value FROM Setting WHERE key='Db.SchemaVersion';";
            Assert.Equal(DatabaseInitializer.LatestSchemaVersion.ToString(), await v.ExecuteScalarAsync());
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task ModelFile_HasLastWriteTimeColumn()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            await using var conn = new SqliteConnection($"Data Source={path}");
            await conn.OpenAsync();

            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "PRAGMA table_info(ModelFile);";
            await using var r = await cmd.ExecuteReaderAsync();

            var hasColumn = false;
            while (await r.ReadAsync())
            {
                if (string.Equals(r.GetString(1), "last_write_time_utc", StringComparison.OrdinalIgnoreCase))
                {
                    hasColumn = true;
                    break;
                }
            }
            Assert.True(hasColumn, "ModelFile должна содержать колонку last_write_time_utc (миграция 2).");
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
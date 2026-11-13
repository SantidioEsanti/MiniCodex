using Microsoft.Data.Sqlite;
using MiniCodex.Data.Migrations;

namespace MiniCodex.Data;

public class MigrationRunner
{
    private readonly IReadOnlyList<IMigration> _migrations;

    public MigrationRunner(IEnumerable<IMigration> migrations)
    {
        _migrations = migrations.OrderBy(m => m.Version).ToList();
    }

    public async Task RunAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        var current = await GetCurrentVersionAsync(conn, ct);

        foreach (var migration in _migrations)
        {
            if (migration.Version <= current) continue;

            await using (var tx = await conn.BeginTransactionAsync(ct))
            {
                await migration.ApplyAsync(conn, ct);
                await SetVersionAsync(conn, migration.Version, ct);
                await tx.CommitAsync(ct);
            }
        }
    }

    private static async Task<int> GetCurrentVersionAsync(SqliteConnection conn, CancellationToken ct)
    {
        // Убедимся, что Setting существует (миграция 1 создаст его)
        await using var check = conn.CreateCommand();
        check.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='Setting';";
        var exists = await check.ExecuteScalarAsync(ct) is string;

        if (!exists) return 0;

        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT value FROM Setting WHERE key = 'Db.SchemaVersion';";
        var raw = await cmd.ExecuteScalarAsync(ct);
        return raw is string s && int.TryParse(s, out var v) ? v : 0;
    }

    private static async Task SetVersionAsync(SqliteConnection conn, int version, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Setting(key, value) VALUES('Db.SchemaVersion', $v)
ON CONFLICT(key) DO UPDATE SET value = excluded.value;";
        cmd.Parameters.AddWithValue("$v", version.ToString());
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
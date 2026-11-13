using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public class Migration_0002_ModelFile_LastWriteTime : IMigration
{
    public int Version => 2;
    public string Description => "Add last_write_time_utc to ModelFile";

    public async Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "ALTER TABLE ModelFile ADD COLUMN last_write_time_utc TEXT;";
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
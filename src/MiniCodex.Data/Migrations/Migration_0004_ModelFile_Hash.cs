using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public class Migration_0004_ModelFile_Hash : IMigration
{
    public int Version => 4;
    public string Description => "Add file_hash to ModelFile";

    public async Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "ALTER TABLE ModelFile ADD COLUMN file_hash TEXT;";
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
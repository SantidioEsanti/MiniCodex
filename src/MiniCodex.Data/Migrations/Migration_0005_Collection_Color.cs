using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public class Migration_0005_Collection_Color : IMigration
{
    public int Version => 5;
    public string Description => "Add color to Collection";

    public async Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "ALTER TABLE Collection ADD COLUMN color TEXT;";
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
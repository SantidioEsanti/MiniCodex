using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public class Migration_0003_ModelOrientation : IMigration
{
    public int Version => 3;
    public string Description => "Add orientation_json to Model";

    public async Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "ALTER TABLE Model ADD COLUMN orientation_json TEXT;";
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
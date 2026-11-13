using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public interface IMigration
{
    int Version { get; }
    string Description { get; }
    Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default);
}
using Microsoft.Data.Sqlite;

namespace MiniCodex.Data;

public class SqliteConnectionFactory
{
    private readonly string _dbPath;
    private readonly string _connectionString;

    public SqliteConnectionFactory(string dbPath)
    {
        _dbPath = dbPath;
        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = dbPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Shared,
        }.ToString();
    }

    public string DbPath => _dbPath;

    public async Task<SqliteConnection> OpenAsync(CancellationToken ct = default)
    {
        var conn = new SqliteConnection(_connectionString);
        await conn.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "PRAGMA foreign_keys = ON;";
        await cmd.ExecuteNonQueryAsync(ct);
        return conn;
    }
}
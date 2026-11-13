using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class CollectionRepository : ICollectionRepository
{
    private readonly SqliteConnectionFactory _factory;

    public CollectionRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<Collection?> GetAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Collection WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    public async Task<IReadOnlyList<Collection>> GetAllAsync(CancellationToken ct = default)
    {
        var result = new List<Collection>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Collection ORDER BY name;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task UpsertAsync(Collection c, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Collection(id, name, filter_query, is_smart) VALUES($id, $name, $filter_query, $is_smart)
ON CONFLICT(id) DO UPDATE SET name = excluded.name, filter_query = excluded.filter_query, is_smart = excluded.is_smart;";
        cmd.Parameters.AddWithValue("$id", c.Id);
        cmd.Parameters.AddWithValue("$name", c.Name);
        cmd.Parameters.AddWithValue("$filter_query", (object?)c.FilterQuery ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$is_smart", c.IsSmart ? 1 : 0);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task DeleteAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM Collection WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static Collection Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        Name = r.GetString(1),
        FilterQuery = r.IsDBNull(2) ? null : r.GetString(2),
        IsSmart = r.GetInt32(3) != 0,
    };
}
using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class TagRepository : ITagRepository
{
    private readonly SqliteConnectionFactory _factory;

    public TagRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<Tag?> GetAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Tag WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    public async Task<IReadOnlyList<Tag>> GetAllAsync(CancellationToken ct = default)
    {
        var result = new List<Tag>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Tag ORDER BY name;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task<IReadOnlyList<TagWithUsage>> GetAllWithUsageAsync(CancellationToken ct = default)
    {
        var result = new List<TagWithUsage>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"SELECT t.id, t.name, t.parent_id, t.color, COUNT(mt.model_id) AS usage
                            FROM Tag t
                            LEFT JOIN ModelTag mt ON mt.tag_id = t.id
                            GROUP BY t.id, t.name, t.parent_id, t.color
                            ORDER BY t.name;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            result.Add(new TagWithUsage(
                r.GetString(0),
                r.GetString(1),
                r.IsDBNull(2) ? null : r.GetString(2),
                r.IsDBNull(3) ? null : r.GetString(3),
                r.GetInt32(4)));
        }
        return result;
    }

    public async Task UpsertAsync(Tag t, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Tag(id, name, parent_id, color) VALUES($id, $name, $parent_id, $color)
ON CONFLICT(id) DO UPDATE SET name = excluded.name, parent_id = excluded.parent_id, color = excluded.color;";
        cmd.Parameters.AddWithValue("$id", t.Id);
        cmd.Parameters.AddWithValue("$name", t.Name);
        cmd.Parameters.AddWithValue("$parent_id", (object?)t.ParentId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$color", (object?)t.Color ?? DBNull.Value);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task DeleteAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM Tag WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static Tag Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        Name = r.GetString(1),
        ParentId = r.IsDBNull(2) ? null : r.GetString(2),
        Color = r.IsDBNull(3) ? null : r.GetString(3),
    };
}
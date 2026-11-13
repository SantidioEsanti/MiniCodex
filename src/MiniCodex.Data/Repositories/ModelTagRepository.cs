using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class ModelTagRepository : IModelTagRepository
{
    private readonly SqliteConnectionFactory _factory;

    public ModelTagRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<IReadOnlyList<Tag>> GetTagsForModelAsync(string modelId, CancellationToken ct = default)
    {
        var result = new List<Tag>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"SELECT t.id, t.name, t.parent_id, t.color
                            FROM Tag t
                            JOIN ModelTag mt ON mt.tag_id = t.id
                            WHERE mt.model_id = $m
                            ORDER BY t.name;";
        cmd.Parameters.AddWithValue("$m", modelId);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            result.Add(new Tag
            {
                Id = r.GetString(0),
                Name = r.GetString(1),
                ParentId = r.IsDBNull(2) ? null : r.GetString(2),
                Color = r.IsDBNull(3) ? null : r.GetString(3),
            });
        }
        return result;
    }

    public async Task AddAsync(string modelId, string tagId, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "INSERT OR IGNORE INTO ModelTag(model_id, tag_id) VALUES($m, $t);";
        cmd.Parameters.AddWithValue("$m", modelId);
        cmd.Parameters.AddWithValue("$t", tagId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task RemoveAsync(string modelId, string tagId, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM ModelTag WHERE model_id = $m AND tag_id = $t;";
        cmd.Parameters.AddWithValue("$m", modelId);
        cmd.Parameters.AddWithValue("$t", tagId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<bool> ExistsAsync(string modelId, string tagId, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT 1 FROM ModelTag WHERE model_id = $m AND tag_id = $t LIMIT 1;";
        cmd.Parameters.AddWithValue("$m", modelId);
        cmd.Parameters.AddWithValue("$t", tagId);
        return await cmd.ExecuteScalarAsync(ct) != null;
    }
}
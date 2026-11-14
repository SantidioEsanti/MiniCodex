using System.Text;
using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class ModelRepository : IModelRepository
{
    private readonly SqliteConnectionFactory _factory;

    public ModelRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<Model?> GetAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        return await ReadOneAsync(conn, "SELECT * FROM Model WHERE id = $id;", id, ct);
    }

    public async Task<IReadOnlyList<Model>> GetAllAsync(CancellationToken ct = default)
    {
        var result = new List<Model>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Model ORDER BY created_at DESC;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task<IReadOnlyList<Model>> SearchAsync(string? query, string? tagId, CancellationToken ct = default)
    {
        var result = new List<Model>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        var sb = new StringBuilder();
        sb.Append("SELECT DISTINCT m.* FROM Model m ");
        if (!string.IsNullOrEmpty(tagId))
            sb.Append("JOIN ModelTag mt ON mt.model_id = m.id ");
        sb.Append("WHERE 1=1 ");
        if (!string.IsNullOrEmpty(tagId))
        {
            var tags = tagId.Split(',', StringSplitOptions.RemoveEmptyEntries);
            if (tags.Length > 0)
            {
                sb.Append("AND mt.tag_id IN (");
                for (int i = 0; i < tags.Length; i++)
                {
                    var p = $"$tag{i}";
                    if (i > 0) sb.Append(", ");
                    sb.Append(p);
                    cmd.Parameters.AddWithValue(p, tags[i]);
                }
                sb.Append(") ");
            }
        }
        if (!string.IsNullOrWhiteSpace(query))
        {
            sb.Append(@"AND (m.title LIKE $q
                        OR COALESCE(m.author, '') LIKE $q
                        OR COALESCE(m.source_url, '') LIKE $q
                        OR EXISTS(SELECT 1 FROM ModelTag mt2
                                  JOIN Tag t2 ON t2.id = mt2.tag_id
                                  WHERE mt2.model_id = m.id AND t2.name LIKE $q)) ");
            cmd.Parameters.AddWithValue("$q", "%" + query.Trim() + "%");
        }
        sb.Append("ORDER BY m.created_at DESC;");
        cmd.CommandText = sb.ToString();
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task<IReadOnlyList<string>> GetDuplicateModelIdsAsync(CancellationToken ct = default)
    {
        var result = new List<string>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            SELECT m.id 
            FROM Model m 
            JOIN ModelFile mf ON mf.model_id = m.id 
            WHERE mf.file_hash IN (
                SELECT file_hash 
                FROM ModelFile 
                WHERE file_hash IS NOT NULL AND file_hash != ''
                GROUP BY file_hash 
                HAVING COUNT(*) > 1
            )
            GROUP BY m.id;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(r.GetString(0));
        return result;
    }

    public async Task UpdateStatusDifficultyAsync(string id, string? status, int? difficulty, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "UPDATE Model SET status = $s, difficulty = $d WHERE id = $id;";
        cmd.Parameters.AddWithValue("$s", (object?)status ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$d", (object?)difficulty ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }
    public async Task UpsertAsync(Model m, CancellationToken ct = default)
    {
        m.UpdatedAt = DateTime.UtcNow;
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Model(id, title, author, source_url, model_type, primary_model_file_id, status, difficulty, real_height_mm, model_height_mm, scale_ratio, notes, orientation_json, created_at, updated_at)
VALUES($id, $title, $author, $source_url, $model_type, $primary_model_file_id, $status, $difficulty, $real_height_mm, $model_height_mm, $scale_ratio, $notes, $orientation_json, $created_at, $updated_at)
ON CONFLICT(id) DO UPDATE SET
    title = excluded.title, author = excluded.author, source_url = excluded.source_url,
    model_type = excluded.model_type, primary_model_file_id = excluded.primary_model_file_id,
    status = excluded.status, difficulty = excluded.difficulty,
    real_height_mm = excluded.real_height_mm, model_height_mm = excluded.model_height_mm,
    scale_ratio = excluded.scale_ratio, notes = excluded.notes,
    orientation_json = excluded.orientation_json,
    updated_at = excluded.updated_at;";
        cmd.Parameters.AddWithValue("$id", m.Id);
        cmd.Parameters.AddWithValue("$title", m.Title);
        cmd.Parameters.AddWithValue("$author", (object?)m.Author ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$source_url", (object?)m.SourceUrl ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$model_type", (object?)m.ModelType ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$primary_model_file_id", (object?)m.PrimaryModelFileId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$status", (object?)m.Status ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$difficulty", (object?)m.Difficulty ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$real_height_mm", (object?)m.RealHeightMm ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$model_height_mm", (object?)m.ModelHeightMm ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$scale_ratio", (object?)m.ScaleRatio ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$notes", (object?)m.Notes ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$orientation_json", (object?)m.OrientationJson ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$created_at", m.CreatedAt.ToString("o"));
        cmd.Parameters.AddWithValue("$updated_at", m.UpdatedAt.ToString("o"));
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task DeleteAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM Model WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task<Model?> ReadOneAsync(SqliteConnection conn, string sql, string id, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        cmd.Parameters.AddWithValue("$id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    private static Model Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        Title = r.GetString(1),
        Author = r.IsDBNull(2) ? null : r.GetString(2),
        SourceUrl = r.IsDBNull(3) ? null : r.GetString(3),
        ModelType = r.IsDBNull(4) ? null : r.GetString(4),
        PrimaryModelFileId = r.IsDBNull(5) ? null : r.GetString(5),
        Status = r.IsDBNull(6) ? null : r.GetString(6),
        Difficulty = r.IsDBNull(7) ? null : r.GetInt32(7),
        RealHeightMm = r.IsDBNull(8) ? null : r.GetDouble(8),
        ModelHeightMm = r.IsDBNull(9) ? null : r.GetDouble(9),
        ScaleRatio = r.IsDBNull(10) ? null : r.GetString(10),
        Notes = r.IsDBNull(11) ? null : r.GetString(11),
        CreatedAt = r.IsDBNull(12) ? DateTime.UtcNow : DateTime.Parse(r.GetString(12), null, System.Globalization.DateTimeStyles.RoundtripKind),
        UpdatedAt = r.IsDBNull(13) ? DateTime.UtcNow : DateTime.Parse(r.GetString(13), null, System.Globalization.DateTimeStyles.RoundtripKind),
        OrientationJson = r.IsDBNull(14) ? null : r.GetString(14),
    };
}
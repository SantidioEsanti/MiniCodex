using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class ModelFileRepository : IModelFileRepository
{
    private readonly SqliteConnectionFactory _factory;

    public ModelFileRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<ModelFile?> GetAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM ModelFile WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    public async Task<ModelFile?> GetByPathAsync(string path, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM ModelFile WHERE path = $path;";
        cmd.Parameters.AddWithValue("$path", path);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    public async Task<IReadOnlyList<ModelFile>> GetByModelAsync(string modelId, CancellationToken ct = default)
    {
        var result = new List<ModelFile>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM ModelFile WHERE model_id = $m;";
        cmd.Parameters.AddWithValue("$m", modelId);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task UpsertAsync(ModelFile f, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO ModelFile(id, model_id, path, file_role, part_name, file_size_bytes, polygon_count, last_write_time_utc)
VALUES($id, $model_id, $path, $file_role, $part_name, $file_size_bytes, $polygon_count, $last_write_time_utc)
ON CONFLICT(id) DO UPDATE SET
    path = excluded.path, file_role = excluded.file_role, part_name = excluded.part_name,
    file_size_bytes = excluded.file_size_bytes, polygon_count = excluded.polygon_count,
    last_write_time_utc = excluded.last_write_time_utc;";
        cmd.Parameters.AddWithValue("$id", f.Id);
        cmd.Parameters.AddWithValue("$model_id", f.ModelId);
        cmd.Parameters.AddWithValue("$path", f.Path);
        cmd.Parameters.AddWithValue("$file_role", (object?)f.FileRole ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$part_name", (object?)f.PartName ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$file_size_bytes", (object?)f.FileSizeBytes ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$polygon_count", (object?)f.PolygonCount ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$last_write_time_utc", f.LastWriteTimeUtc.HasValue ? f.LastWriteTimeUtc.Value.ToString("o") : DBNull.Value);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task DeleteAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM ModelFile WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static ModelFile Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        ModelId = r.GetString(1),
        Path = r.GetString(2),
        FileRole = r.IsDBNull(3) ? null : r.GetString(3),
        PartName = r.IsDBNull(4) ? null : r.GetString(4),
        FileSizeBytes = r.IsDBNull(5) ? null : r.GetInt64(5),
        PolygonCount = r.IsDBNull(6) ? null : r.GetInt32(6),
        LastWriteTimeUtc = r.IsDBNull(7) ? null : DateTime.Parse(r.GetString(7), null, System.Globalization.DateTimeStyles.RoundtripKind),
    };
}
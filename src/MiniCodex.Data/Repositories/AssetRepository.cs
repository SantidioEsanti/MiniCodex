using Microsoft.Data.Sqlite;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class AssetRepository : IAssetRepository
{
    private readonly SqliteConnectionFactory _factory;

    public AssetRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<Asset?> GetAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Asset WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        return await r.ReadAsync(ct) ? Map(r) : null;
    }

    public async Task<IReadOnlyList<Asset>> GetByModelAsync(string modelId, CancellationToken ct = default)
    {
        var result = new List<Asset>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM Asset WHERE model_id = $m ORDER BY sort_order;";
        cmd.Parameters.AddWithValue("$m", modelId);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(Map(r));
        return result;
    }

    public async Task UpsertAsync(Asset a, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Asset(id, model_id, asset_type, absolute_path, thumbnail_path, sort_order, storage_mode)
VALUES($id, $model_id, $asset_type, $absolute_path, $thumbnail_path, $sort_order, $storage_mode)
ON CONFLICT(id) DO UPDATE SET
    asset_type = excluded.asset_type, absolute_path = excluded.absolute_path,
    thumbnail_path = excluded.thumbnail_path, sort_order = excluded.sort_order,
    storage_mode = excluded.storage_mode;";
        cmd.Parameters.AddWithValue("$id", a.Id);
        cmd.Parameters.AddWithValue("$model_id", a.ModelId);
        cmd.Parameters.AddWithValue("$asset_type", (object?)a.AssetType ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$absolute_path", a.AbsolutePath);
        cmd.Parameters.AddWithValue("$thumbnail_path", (object?)a.ThumbnailPath ?? DBNull.Value);
        cmd.Parameters.AddWithValue("$sort_order", a.SortOrder);
        cmd.Parameters.AddWithValue("$storage_mode", (object?)a.StorageMode ?? DBNull.Value);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task DeleteAsync(string id, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM Asset WHERE id = $id;";
        cmd.Parameters.AddWithValue("$id", id);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static Asset Map(SqliteDataReader r) => new()
    {
        Id = r.GetString(0),
        ModelId = r.GetString(1),
        AssetType = r.IsDBNull(2) ? null : r.GetString(2),
        AbsolutePath = r.GetString(3),
        ThumbnailPath = r.IsDBNull(4) ? null : r.GetString(4),
        SortOrder = r.IsDBNull(5) ? 0 : r.GetInt32(5),
        StorageMode = r.IsDBNull(6) ? null : r.GetString(6),
    };
}
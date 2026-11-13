using MiniCodex.Core.Repositories;

namespace MiniCodex.Data.Repositories;

public class SettingRepository : ISettingRepository
{
    private readonly SqliteConnectionFactory _factory;

    public SettingRepository(SqliteConnectionFactory factory) => _factory = factory;

    public async Task<string?> GetAsync(string key, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT value FROM Setting WHERE key = $k;";
        cmd.Parameters.AddWithValue("$k", key);
        return await cmd.ExecuteScalarAsync(ct) as string;
    }

    public async Task SetAsync(string key, string value, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
INSERT INTO Setting(key, value) VALUES($k, $v)
ON CONFLICT(key) DO UPDATE SET value = excluded.value;";
        cmd.Parameters.AddWithValue("$k", key);
        cmd.Parameters.AddWithValue("$v", value);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<IReadOnlyDictionary<string, string>> GetAllAsync(CancellationToken ct = default)
    {
        var result = new Dictionary<string, string>();
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT key, value FROM Setting;";
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
            result[r.GetString(0)] = r.IsDBNull(1) ? string.Empty : r.GetString(1);
        return result;
    }
}
using System.Text.Json;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class CollectionService : ICollectionService
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly ICollectionRepository _repo;

    public CollectionService(ICollectionRepository repo) => _repo = repo;

    public async Task<IReadOnlyList<Collection>> GetSmartAsync(CancellationToken ct = default)
    {
        var all = await _repo.GetAllAsync(ct);
        return all.Where(c => c.IsSmart).ToList();
    }

    public async Task<Collection> SaveSmartAsync(string name, SmartCollectionFilter filter, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Collection name is required", nameof(name));

        var trimmed = name.Trim();
        var existing = (await _repo.GetAllAsync(ct))
            .FirstOrDefault(c => c.IsSmart && string.Equals(c.Name, trimmed, StringComparison.OrdinalIgnoreCase));

        var collection = existing ?? new Collection
        {
            Id = Guid.NewGuid().ToString("N"),
            IsSmart = true,
        };
        collection.Name        = trimmed;
        collection.FilterQuery = SerializeFilter(filter);
        collection.IsSmart     = true;

        await _repo.UpsertAsync(collection, ct);
        return collection;
    }

    public Task DeleteAsync(string id, CancellationToken ct = default) => _repo.DeleteAsync(id, ct);

    public static string SerializeFilter(SmartCollectionFilter filter)
        => JsonSerializer.Serialize(filter ?? SmartCollectionFilter.Empty, JsonOpts);

    public static SmartCollectionFilter DeserializeFilter(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return SmartCollectionFilter.Empty;
        try
        {
            return JsonSerializer.Deserialize<SmartCollectionFilter>(json, JsonOpts) ?? SmartCollectionFilter.Empty;
        }
        catch (JsonException)
        {
            return SmartCollectionFilter.Empty;
        }
    }
}
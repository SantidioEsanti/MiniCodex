using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface ICollectionService
{
    Task<IReadOnlyList<Collection>> GetSmartAsync(CancellationToken ct = default);
    Task<Collection> SaveSmartAsync(string name, SmartCollectionFilter filter, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
    Task SetColorAsync(string id, string? color, CancellationToken ct = default);
}
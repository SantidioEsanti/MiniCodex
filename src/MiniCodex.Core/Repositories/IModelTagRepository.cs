using MiniCodex.Core.Models;

namespace MiniCodex.Core.Repositories;

public interface IModelTagRepository
{
    Task<IReadOnlyList<Tag>> GetTagsForModelAsync(string modelId, CancellationToken ct = default);
    Task AddAsync(string modelId, string tagId, CancellationToken ct = default);
    Task RemoveAsync(string modelId, string tagId, CancellationToken ct = default);
    Task<bool> ExistsAsync(string modelId, string tagId, CancellationToken ct = default);
    Task RemoveAllForTagAsync(string tagId, CancellationToken ct = default);
}
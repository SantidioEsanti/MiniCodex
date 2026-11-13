using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface ITagService
{
    Task<Tag> CreateOrGetAsync(string name, CancellationToken ct = default);
    Task<IReadOnlyList<Tag>> GetTagsForModelAsync(string modelId, CancellationToken ct = default);
    Task AddToModelAsync(string modelId, string tagName, CancellationToken ct = default);
    Task RemoveFromModelAsync(string modelId, string tagId, CancellationToken ct = default);
    Task<IReadOnlyList<TagWithUsage>> GetAllWithUsageAsync(CancellationToken ct = default);
}
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class TagService : ITagService
{
    private readonly ITagRepository _tags;
    private readonly IModelTagRepository _modelTags;

    public TagService(ITagRepository tags, IModelTagRepository modelTags)
    {
        _tags = tags;
        _modelTags = modelTags;
    }

    public async Task<Tag> CreateOrGetAsync(string name, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Tag name is required", nameof(name));

        var trimmed = name.Trim();
        var all = await _tags.GetAllAsync(ct);
        var existing = all.FirstOrDefault(t => string.Equals(t.Name, trimmed, StringComparison.OrdinalIgnoreCase));
        if (existing != null) return existing;

        var tag = new Tag { Name = trimmed };
        await _tags.UpsertAsync(tag, ct);
        return tag;
    }

    public Task<IReadOnlyList<Tag>> GetTagsForModelAsync(string modelId, CancellationToken ct = default)
        => _modelTags.GetTagsForModelAsync(modelId, ct);

    public async Task AddToModelAsync(string modelId, string tagName, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(tagName)) return;
        var tag = await CreateOrGetAsync(tagName, ct);
        await _modelTags.AddAsync(modelId, tag.Id, ct);
    }

    public Task RemoveFromModelAsync(string modelId, string tagId, CancellationToken ct = default)
        => _modelTags.RemoveAsync(modelId, tagId, ct);

    public Task<IReadOnlyList<TagWithUsage>> GetAllWithUsageAsync(CancellationToken ct = default)
        => _tags.GetAllWithUsageAsync(ct);
}
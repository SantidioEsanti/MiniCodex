using MiniCodex.Core.Models;

namespace MiniCodex.Core.Repositories;

public interface ISettingRepository
{
    Task<string?> GetAsync(string key, CancellationToken ct = default);
    Task SetAsync(string key, string value, CancellationToken ct = default);
    Task<IReadOnlyDictionary<string, string>> GetAllAsync(CancellationToken ct = default);
}

public interface IModelRepository
{
    Task<Model?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<Model>> GetAllAsync(CancellationToken ct = default);
    Task<IReadOnlyList<Model>> SearchAsync(string? query, string? tagId, CancellationToken ct = default);
    Task UpdateStatusDifficultyAsync(string id, string? status, int? difficulty, CancellationToken ct = default);
    Task UpsertAsync(Model model, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}

public interface IModelFileRepository
{
    Task<ModelFile?> GetAsync(string id, CancellationToken ct = default);
    Task<ModelFile?> GetByPathAsync(string path, CancellationToken ct = default);
    Task<IReadOnlyList<ModelFile>> GetByModelAsync(string modelId, CancellationToken ct = default);
    Task UpsertAsync(ModelFile file, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}

public interface IAssetRepository
{
    Task<Asset?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<Asset>> GetByModelAsync(string modelId, CancellationToken ct = default);
    Task UpsertAsync(Asset asset, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}

public interface ITagRepository
{
    Task<Tag?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<Tag>> GetAllAsync(CancellationToken ct = default);
    Task<IReadOnlyList<TagWithUsage>> GetAllWithUsageAsync(CancellationToken ct = default);
    Task UpsertAsync(Tag tag, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}

public interface ICollectionRepository
{
    Task<Collection?> GetAsync(string id, CancellationToken ct = default);
    Task<IReadOnlyList<Collection>> GetAllAsync(CancellationToken ct = default);
    Task UpsertAsync(Collection collection, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IIntegrationService
{
    Task<IReadOnlyList<IntegrationApp>> GetAppsAsync(CancellationToken ct = default);
    Task SetPathAsync(string appId, string? path, CancellationToken ct = default);
    Task<bool> LaunchAsync(string appId, string modelFilePath, CancellationToken ct = default);
}
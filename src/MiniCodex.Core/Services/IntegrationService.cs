using System.Diagnostics;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class IntegrationService : IIntegrationService
{
    private readonly IIntegrationProbe _probe;
    private readonly ISettingRepository _settings;

    public IntegrationService(IIntegrationProbe probe, ISettingRepository settings)
    {
        _probe = probe;
        _settings = settings;
    }

    public async Task<IReadOnlyList<IntegrationApp>> GetAppsAsync(CancellationToken ct = default)
    {
        var detected = await _probe.ProbeAsync(ct);
        var allSettings = await _settings.GetAllAsync(ct);

        var result = new List<IntegrationApp>();
        foreach (var def in IntegrationCatalog.All)
        {
            var userKey = IntegrationCatalog.SettingKey(def.Id);
            var userPath = allSettings.TryGetValue(userKey, out var raw) ? raw : null;

            if (!string.IsNullOrWhiteSpace(userPath))
            {
                result.Add(new IntegrationApp
                {
                    Id = def.Id,
                    DisplayName = def.DisplayName,
                    Kind = def.Kind,
                    Path = userPath,
                    IsDetected = false,
                    IsUserOverride = true,
                });
            }
            else if (detected.TryGetValue(def.Id, out var detectedPath))
            {
                result.Add(new IntegrationApp
                {
                    Id = def.Id,
                    DisplayName = def.DisplayName,
                    Kind = def.Kind,
                    Path = detectedPath,
                    IsDetected = true,
                    IsUserOverride = false,
                });
            }
            else
            {
                result.Add(new IntegrationApp
                {
                    Id = def.Id,
                    DisplayName = def.DisplayName,
                    Kind = def.Kind,
                    Path = null,
                    IsDetected = false,
                    IsUserOverride = false,
                });
            }
        }
        return result;
    }

    public async Task SetPathAsync(string appId, string? path, CancellationToken ct = default)
    {
        var key = IntegrationCatalog.SettingKey(appId);
        if (string.IsNullOrWhiteSpace(path))
        {
            await _settings.SetAsync(key, string.Empty, ct);
        }
        else
        {
            await _settings.SetAsync(key, path.Trim(), ct);
        }
    }

    public async Task<bool> LaunchAsync(string appId, string modelFilePath, CancellationToken ct = default)
    {
        var apps = await GetAppsAsync(ct);
        var app = apps.FirstOrDefault(a => a.Id == appId);
        if (app == null || string.IsNullOrEmpty(app.Path) || !File.Exists(app.Path)) return false;
        if (string.IsNullOrEmpty(modelFilePath) || !File.Exists(modelFilePath)) return false;

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = app.Path,
                Arguments = $"\"{modelFilePath}\"",
                UseShellExecute = false,
            };
            Process.Start(psi);
            return true;
        }
        catch
        {
            return false;
        }
    }
}
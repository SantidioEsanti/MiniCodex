using System.Runtime.Versioning;
using Microsoft.Win32;
using MiniCodex.Core.Services;

namespace MiniCodex.App.Services;

[SupportedOSPlatform("windows")]
public class WindowsRegistryProbe : IIntegrationProbe
{
    private static readonly string[] UninstallRoots =
    {
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    };

    public Task<IReadOnlyDictionary<string, string>> ProbeAsync(CancellationToken ct = default)
    {
        var found = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var def in IntegrationCatalog.All)
        {
            if (ct.IsCancellationRequested) break;

            var path = TryCommonPaths(def) ?? TryRegistry(def);
            if (path != null) found[def.Id] = path;
        }
        return Task.FromResult<IReadOnlyDictionary<string, string>>(found);
    }

    private static string? TryCommonPaths(IntegrationAppDefinition def)
    {
        foreach (var raw in def.CommonPaths)
        {
            var expanded = Environment.ExpandEnvironmentVariables(raw);
            if (File.Exists(expanded)) return expanded;
        }
        return null;
    }

    private static string? TryRegistry(IntegrationAppDefinition def)
    {
        foreach (var hive in new[] { Registry.LocalMachine, Registry.CurrentUser })
        {
            foreach (var rootPath in UninstallRoots)
            {
                try
                {
                    using var root = hive.OpenSubKey(rootPath);
                    if (root == null) continue;
                    foreach (var subKeyName in root.GetSubKeyNames())
                    {
                        using var subKey = root.OpenSubKey(subKeyName);
                        if (subKey == null) continue;
                        var displayName = subKey.GetValue("DisplayName") as string;
                        if (string.IsNullOrEmpty(displayName)) continue;
                        if (!def.RegistryNameHints.Any(h => displayName.Contains(h, StringComparison.OrdinalIgnoreCase)))
                            continue;

                        var installLoc = subKey.GetValue("InstallLocation") as string;
                        if (!string.IsNullOrEmpty(installLoc))
                        {
                            var candidate = Path.Combine(installLoc, def.ExeName);
                            if (File.Exists(candidate)) return candidate;
                        }

                        var icon = subKey.GetValue("DisplayIcon") as string;
                        if (!string.IsNullOrEmpty(icon))
                        {
                            var cleaned = icon.Split(',')[0].Trim().Trim('"');
                            if (cleaned.EndsWith(def.ExeName, StringComparison.OrdinalIgnoreCase) && File.Exists(cleaned))
                                return cleaned;
                        }
                    }
                }
                catch { /* access denied — пропускаем */ }
            }
        }
        return null;
    }
}
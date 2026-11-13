using System.Diagnostics;
using System.Runtime.Versioning;

namespace MiniCodex.App.Services;

[SupportedOSPlatform("windows")]
public static class FileSystemHelper
{
    public static void ShowInExplorer(string path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"/select,\"{path}\"",
                UseShellExecute = true,
            });
        }
        catch { }
    }
}
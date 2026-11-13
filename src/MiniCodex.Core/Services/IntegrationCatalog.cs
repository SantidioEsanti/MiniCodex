using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public record IntegrationAppDefinition(
    string Id,
    string DisplayName,
    IntegrationAppKind Kind,
    string[] CommonPaths,
    string ExeName,
    string[] RegistryNameHints);

public static class IntegrationCatalog
{
    public static IReadOnlyList<IntegrationAppDefinition> All { get; } = new[]
    {
        // ---------- Slicers ----------
        new IntegrationAppDefinition(
            "bambustudio", "Bambu Studio", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\Bambu Studio\bambu-studio.exe",
                @"C:\Program Files (x86)\Bambu Studio\bambu-studio.exe",
                @"%LOCALAPPDATA%\Programs\Bambu Studio\bambu-studio.exe",
            },
            "bambu-studio.exe",
            new[] { "Bambu Studio" }),

        new IntegrationAppDefinition(
            "prusaslicer", "PrusaSlicer", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\Prusa3D\PrusaSlicer\prusa-slicer.exe",
                @"C:\Program Files\Prusa3D\PrusaSlicer\prusa-slicer-console.exe",
            },
            "prusa-slicer.exe",
            new[] { "PrusaSlicer" }),

        new IntegrationAppDefinition(
            "orcaslicer", "OrcaSlicer", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\OrcaSlicer\orca-slicer.exe",
                @"%LOCALAPPDATA%\Programs\OrcaSlicer\orca-slicer.exe",
            },
            "orca-slicer.exe",
            new[] { "OrcaSlicer" }),

        new IntegrationAppDefinition(
            "cura", "UltiMaker Cura", IntegrationAppKind.Slicer,
            new[] { @"C:\Program Files\UltiMaker Cura\UltiMaker-Cura.exe" },
            "UltiMaker-Cura.exe",
            new[] { "UltiMaker Cura", "Ultimaker Cura" }),

        new IntegrationAppDefinition(
            "lychee", "Lychee Slicer", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\Lychee Slicer\Lychee Slicer.exe",
                @"%LOCALAPPDATA%\Programs\Lychee Slicer\Lychee Slicer.exe",
            },
            "Lychee Slicer.exe",
            new[] { "Lychee Slicer" }),

        new IntegrationAppDefinition(
            "chitubox", "CHITUBOX", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\CBD-Tech\Chitubox\CHITUBOX.exe",
                @"%LOCALAPPDATA%\Programs\Chitubox\CHITUBOX.exe",
            },
            "CHITUBOX.exe",
            new[] { "CHITUBOX" }),

        // ---------- Anycubic ----------
        new IntegrationAppDefinition(
            "anycubic-slicer", "Anycubic Slicer", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\AnycubicSlicer\Anycubic-Slicer.exe",
                @"C:\Program Files\Anycubic\Anycubic-Slicer.exe",
                @"%LOCALAPPDATA%\Programs\AnycubicSlicer\Anycubic-Slicer.exe",
            },
            "Anycubic-Slicer.exe",
            new[] { "Anycubic Slicer" }),

        new IntegrationAppDefinition(
            "anycubic-slicer-next", "Anycubic Slicer Next", IntegrationAppKind.Slicer,
            new[]
            {
                @"C:\Program Files\AnycubicSlicerNext\AnycubicSlicerNext.exe",
                @"%LOCALAPPDATA%\Programs\AnycubicSlicerNext\AnycubicSlicerNext.exe",
            },
            "AnycubicSlicerNext.exe",
            new[] { "Anycubic Slicer Next", "AnycubicSlicerNext" }),

        // ---------- Editors ----------
        new IntegrationAppDefinition(
            "blender", "Blender", IntegrationAppKind.Editor,
            new[]
            {
                @"C:\Program Files\Blender Foundation\Blender\blender.exe",
            },
            "blender.exe",
            new[] { "Blender" }),

        new IntegrationAppDefinition(
            "zbrush", "ZBrush", IntegrationAppKind.Editor,
            new[]
            {
                @"C:\Program Files\Maxon ZBrush\ZBrush.exe",
                @"C:\Program Files\Pixologic\ZBrush\ZBrush.exe",
            },
            "ZBrush.exe",
            new[] { "ZBrush" }),

        new IntegrationAppDefinition(
            "3dcoat", "3D-Coat", IntegrationAppKind.Editor,
            new[] { @"C:\Program Files\3D-Coat\3D-Coat.exe" },
            "3D-Coat.exe",
            new[] { "3D-Coat" }),

        new IntegrationAppDefinition(
            "meshmixer", "Meshmixer", IntegrationAppKind.Editor,
            new[] { @"C:\Program Files\Autodesk\Meshmixer\meshmixer.exe" },
            "meshmixer.exe",
            new[] { "Meshmixer" }),
    };

    public static IntegrationAppDefinition? Find(string id) => All.FirstOrDefault(a => a.Id == id);

    public static string SettingKey(string appId) => $"Integration.{appId}.Path";
}
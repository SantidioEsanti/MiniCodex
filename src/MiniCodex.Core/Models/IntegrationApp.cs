namespace MiniCodex.Core.Models;

public enum IntegrationAppKind { Slicer, Editor }

public class IntegrationApp
{
    public string Id { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public IntegrationAppKind Kind { get; set; }
    public string? Path { get; set; }
    public bool IsDetected { get; set; }
    public bool IsUserOverride { get; set; }
    public bool IsAvailable => !string.IsNullOrEmpty(Path) && System.IO.File.Exists(Path);
}
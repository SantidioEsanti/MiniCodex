using System.ComponentModel;
using System.Runtime.CompilerServices;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class ModelFileRowViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public ModelFile File { get; }

    public string DisplayName => Path.GetFileName(File.Path);
    public string RoleText => string.IsNullOrEmpty(File.FileRole) ? "-" : File.FileRole!;
    public string SizeText => File.FileSizeBytes.HasValue ? FormatSize(File.FileSizeBytes.Value) : "-";
    public string PolygonsText => File.PolygonCount?.ToString("N0") ?? "-";

    private bool _isPrimary;
    public bool IsPrimary
    {
        get => _isPrimary;
        set { if (_isPrimary != value) { _isPrimary = value; Raise(); } }
    }

    public ModelFileRowViewModel(ModelFile file, bool isPrimary)
    {
        File = file;
        _isPrimary = isPrimary;
    }

    private static string FormatSize(long bytes)
    {
        string[] units = { "B", "KB", "MB", "GB" };
        double v = bytes; int u = 0;
        while (v >= 1024 && u < units.Length - 1) { v /= 1024; u++; }
        return $"{v:F1} {units[u]}";
    }
}
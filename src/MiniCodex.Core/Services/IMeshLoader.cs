using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IMeshLoader
{
    MeshInfo? Load(string filePath);
    IReadOnlyCollection<string> SupportedExtensions { get; }
}
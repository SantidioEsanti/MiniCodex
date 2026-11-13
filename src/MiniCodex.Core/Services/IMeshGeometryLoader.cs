using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IMeshGeometryLoader
{
    MeshGeometry? LoadGeometry(string filePath);
}
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public class CollectionRow
{
    public string Id { get; init; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public SmartCollectionFilter Filter { get; set; } = SmartCollectionFilter.Empty;
    public bool IsSmart { get; set; } = true;

    public static CollectionRow From(Collection c) => new()
    {
        Id = c.Id,
        Name = c.Name,
        Filter = CollectionService.DeserializeFilter(c.FilterQuery),
        IsSmart = c.IsSmart,
    };
}
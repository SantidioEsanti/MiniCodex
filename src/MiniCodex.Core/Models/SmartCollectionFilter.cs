namespace MiniCodex.Core.Models;

/// <summary>
/// Serializable filter payload for a Smart Collection (search + tag).
/// </summary>
public sealed record SmartCollectionFilter(string? Search, string? TagId, string? TagName)
{
    public static SmartCollectionFilter Empty { get; } = new(null, null, null);

    public bool IsEmpty => string.IsNullOrWhiteSpace(Search) && string.IsNullOrWhiteSpace(TagId);
}
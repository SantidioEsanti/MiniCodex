namespace MiniCodex.Core.Models;

public record TagWithUsage(string Id, string Name, string? ParentId, string? Color, int UsageCount);
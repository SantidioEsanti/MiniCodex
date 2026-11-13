namespace MiniCodex.Core.Services;

public interface IIntegrationProbe
{
    /// <summary>
    /// Возвращает словарь appId → абсолютный путь к exe.
    /// Отсутствующие приложения просто не попадают в словарь.
    /// </summary>
    Task<IReadOnlyDictionary<string, string>> ProbeAsync(CancellationToken ct = default);
}
using Avalonia;
using Avalonia.Styling;

namespace MiniCodex.App.Services;

public class ThemeService
{
    private readonly Application _app;

    public ThemeService(Application app) => _app = app;

    public void Apply(string theme)
    {
        _app.RequestedThemeVariant = theme?.ToLowerInvariant() switch
        {
            "light" => ThemeVariant.Light,
            "dark" => ThemeVariant.Dark,
            _ => ThemeVariant.Default,
        };
    }
}
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class IntegrationAppRowViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public IntegrationApp App { get; }

    public string DisplayName => App.DisplayName;
    public string CurrentPath => App.Path ?? string.Empty;

    public string StatusText
    {
        get
        {
            if (App.IsUserOverride) return Loc("Settings.Integrations.StatusManual", "Manual");
            if (App.IsDetected) return Loc("Settings.Integrations.StatusAuto", "Auto");
            return Loc("Settings.Integrations.StatusMissing", "Not found");
        }
    }

    public string BrowseText => Loc("Settings.Integrations.Browse", "Browse…");
    public string ClearText => Loc("Settings.Integrations.Clear", "Clear");

    public ICommand BrowseCommand { get; }
    public ICommand ClearCommand { get; }

    public IntegrationAppRowViewModel(
        IntegrationApp app,
        Func<IntegrationAppRowViewModel, Task> onBrowse,
        Func<IntegrationAppRowViewModel, Task> onClear)
    {
        App = app;
        BrowseCommand = new RelayCommand(async () => await onBrowse(this));
        ClearCommand = new RelayCommand(async () => await onClear(this));
    }

    public void RefreshLocalized()
    {
        Raise(nameof(StatusText));
        Raise(nameof(BrowseText));
        Raise(nameof(ClearText));
    }

    // Полностью квалифицированное обращение, чтобы не конфликтовать со свойством App.
    private static string Loc(string key, string fallback)
        => MiniCodex.App.App.Loc?.Get(key) ?? fallback;
}
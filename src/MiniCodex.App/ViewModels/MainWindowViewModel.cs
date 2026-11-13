using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class MainWindowViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public ObservableCollection<string> Languages { get; } = new() { "en", "ru" };

    private string _lang = App.Loc?.Current ?? "en";
    public string CurrentLanguage
    {
        get => _lang;
        set
        {
            if (!Set(ref _lang, value)) return;
            App.Loc.SetLanguage(value);
            Raise(nameof(Title));
            Raise(nameof(LibraryButtonText));
            Raise(nameof(SettingsButtonText));
            Raise(nameof(AboutButtonText));
            Library.RefreshLocalized();
            (CurrentPage as ModelCardPageViewModel)?.RefreshLocalized();
            (CurrentPage as SettingsViewModel)?.RefreshLocalized();
            (CurrentPage as AboutViewModel)?.RefreshLocalized();
        }
    }

    private string _theme = "auto";
    public string CurrentTheme
    {
        get => _theme;
        set
        {
            if (!Set(ref _theme, value)) return;
            App.Theme.Apply(value);
            Raise(nameof(ThemeIconGlyph));
            Raise(nameof(ThemeTooltip));
        }
    }

    public string ThemeIconGlyph => _theme switch
    {
        "light" => "\uE706",
        "dark" => "\uE708",
        _ => "\uE7F4",
    };

    public string ThemeTooltip => _theme switch
    {
        "light" => App.Loc?.Get("Settings.Theme.Light") ?? "Light",
        "dark" => App.Loc?.Get("Settings.Theme.Dark") ?? "Dark",
        _ => App.Loc?.Get("Settings.Theme.Auto") ?? "Auto",
    };

    public ICommand CycleThemeCommand { get; }

    public string Title => App.Loc.Get("App.Name");
    public string LibraryButtonText => App.Loc.Get("Menu.Library");
    public string SettingsButtonText => App.Loc.Get("Menu.Settings");
    public string AboutButtonText => App.Loc.Get("Menu.About");

    public LibraryViewModel Library { get; }

    private object? _currentPage;
    public object? CurrentPage
    {
        get => _currentPage;
        private set { _currentPage = value; Raise(); }
    }

    public ICommand RequestFocusSearchCommand { get; }
    public ICommand ShowLibraryCommand { get; }
    public ICommand ShowSettingsCommand { get; }
    public ICommand ShowAboutCommand { get; }

    public MainWindowViewModel()
    {
        // Load saved theme (sync, one-time at startup, ~1ms)
        string initialTheme = "auto";
        try
        {
            if (AppServices.Settings != null)
            {
                var saved = AppServices.Settings.GetAsync("UI.Theme").GetAwaiter().GetResult();
                if (!string.IsNullOrEmpty(saved) && (saved == "light" || saved == "dark" || saved == "auto"))
                {
                    initialTheme = saved;
                }
            }
        }
        catch { }
        _theme = initialTheme;
        App.Theme?.Apply(initialTheme);

        Library = new LibraryViewModel(
            AppServices.Models,
            AppServices.ModelFiles,
            AppServices.Scanner,
            AppServices.PreviewGenerator,
            AppServices.TagService,
            AppServices.IntegrationService);
        Library.OpenCardRequested += OnOpenCard;
        Library.OpenCardWithTabRequested += OnOpenCardWithTab;
        CurrentPage = Library;

        CycleThemeCommand = new RelayCommand(() =>
        {
            CurrentTheme = _theme switch
            {
                "auto" => "light",
                "light" => "dark",
                _ => "auto",
            };
        });
        RequestFocusSearchCommand = new RelayCommand(() =>
        {
            if (CurrentPage is LibraryViewModel lib) lib.RequestFocusSearch();
        });
        ShowLibraryCommand = new RelayCommand(() => CurrentPage = Library);
        ShowSettingsCommand = new RelayCommand(() =>
        {
            var vm = new SettingsViewModel();
            CurrentPage = vm;
            _ = vm.LoadAsync();
        });
        ShowAboutCommand = new RelayCommand(() =>
        {
            CurrentPage = new AboutViewModel();
        });
    }

    private void OnOpenCard(object? sender, Model model) => OpenCardInternal(model, 0);
    private void OnOpenCardWithTab(object? sender, (Model model, int tabIndex) args) => OpenCardInternal(args.model, args.tabIndex);

    private void OpenCardInternal(Model model, int tabIndex)
    {
        if (AppServices.Models == null || AppServices.ModelFiles == null) return;
        var page = new ModelCardPageViewModel(model, AppServices.Models, AppServices.ModelFiles,
            onBack: () => CurrentPage = Library)
        {
            SelectedTabIndex = tabIndex
        };
        page.PreviewsRegenerated += OnPreviewsRegenerated;
        CurrentPage = page;
        _ = page.LoadAsync();
    }

    private async void OnPreviewsRegenerated(object? sender, string modelId)
    {
        await Library.OnPreviewsRegeneratedAsync(modelId);
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (Equals(field, value)) return false;
        field = value;
        Raise(name);
        return true;
    }
}
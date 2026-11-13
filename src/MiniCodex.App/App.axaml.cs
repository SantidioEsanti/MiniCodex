using System;
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using MiniCodex.App.Services;
using MiniCodex.App.Views;
using MiniCodex.Core.Logging;
using MiniCodex.Data;

namespace MiniCodex.App;

public partial class App : Application
{
    public static AppPaths Paths { get; private set; } = null!;
    public static LocalizationService Loc { get; private set; } = null!;
    public static ThemeService Theme { get; private set; } = null!;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            Dispatcher.UIThread.UnhandledException += (s, e) =>
            {
                Log.Exception("[Dispatcher.UIThread.UnhandledException]", e.Exception);
                e.Handled = false;
            };

            Paths = new AppPaths();
            Paths.EnsureCreated();
            Log.Info("[App] Paths.Root=" + Paths.Root + " LibraryDb=" + Paths.LibraryDb);

            try
            {
                Log.Info("[App] DatabaseInitializer.InitializeAsync begin");
                DatabaseInitializer.InitializeAsync(Paths.LibraryDb).GetAwaiter().GetResult();
                Log.Info("[App] DatabaseInitializer.InitializeAsync ok");
            }
            catch (Exception ex)
            {
                Log.Exception("[App] DatabaseInitializer failed", ex);
                throw;
            }

            try
            {
                Log.Info("[App] AppServices.Init begin");
                AppServices.Init(Paths);
                Log.Info("[App] AppServices.Init ok: Models=" + (AppServices.Models != null) +
                         " ModelFiles=" + (AppServices.ModelFiles != null) +
                         " Scanner=" + (AppServices.Scanner != null) +
                         " Preview=" + (AppServices.PreviewGenerator != null) +
                         " Settings=" + (AppServices.Settings != null) +
                         " AssetService=" + (AppServices.AssetService != null) +
                         " TagService=" + (AppServices.TagService != null) +
                         " Integration=" + (AppServices.IntegrationService != null));
            }
            catch (Exception ex)
            {
                Log.Exception("[App] AppServices.Init failed", ex);
                throw;
            }

            Loc = new LocalizationService(Paths, "en");
            Loc.LoadInitial();
            Log.Info("[App] language=" + Loc.Current);

            Theme = new ThemeService(this);

            desktop.MainWindow = new MainWindow();
        }
        base.OnFrameworkInitializationCompleted();
    }
}
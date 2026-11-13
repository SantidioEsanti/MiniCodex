using System.ComponentModel;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Windows.Input;

namespace MiniCodex.App.ViewModels;

public class AboutViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public string AppName => App.Loc?.Get("App.Name") ?? "MiniCodex";
    public string Tagline => App.Loc?.Get("About.Tagline") ?? "Portable 3D model library";
    public string VersionString
    {
        get
        {
            try
            {
                var asm = Assembly.GetEntryAssembly();
                return asm?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
                       ?? "0.1.0-alpha";
            }
            catch { return "0.1.0-alpha"; }
        }
    }

    public string AboutHeader => App.Loc?.Get("About.Title") ?? "About";
    public string AuthorLabel => App.Loc?.Get("About.Author") ?? "Author";
    public string AuthorValue => "Santidio Esanti";
    public string LicenseLabel => App.Loc?.Get("About.License") ?? "Licensed under MIT";
    public string GitHubLabel => App.Loc?.Get("About.GitHub") ?? "GitHub repository";
    public string BoostyLabel => App.Loc?.Get("About.SupportAuthor") ?? "Support the author";
    public string CopyrightLabel => App.Loc?.Get("About.Copyright") ?? "Copyright (c) 2026 Santidio Esanti";

    public ICommand OpenGitHubCommand { get; }
    public ICommand OpenBoostyCommand { get; }

    public AboutViewModel()
    {
        OpenGitHubCommand = new RelayCommand(() => OpenUrl("https://github.com/SantidioEsanti"));
        OpenBoostyCommand = new RelayCommand(() => OpenUrl("https://boosty.to/santidioesanti"));
    }

    public void RefreshLocalized()
    {
        Raise(nameof(AppName));
        Raise(nameof(Tagline));
        Raise(nameof(AboutHeader));
        Raise(nameof(AuthorLabel));
        Raise(nameof(LicenseLabel));
        Raise(nameof(GitHubLabel));
        Raise(nameof(BoostyLabel));
        Raise(nameof(CopyrightLabel));
    }

    private static void OpenUrl(string url)
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = url,
                UseShellExecute = true,
            });
        }
        catch { }
    }
}
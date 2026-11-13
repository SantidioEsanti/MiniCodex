using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class SettingsViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public ObservableCollection<IntegrationAppRowViewModel> SlicerRows { get; } = new();
    public ObservableCollection<IntegrationAppRowViewModel> EditorRows { get; } = new();

    private bool _isBusy;
    public bool IsBusy
    {
        get => _isBusy;
        private set { _isBusy = value; Raise(); }
    }

    public string HeaderText => App.Loc?.Get("Settings.Title") ?? "Settings";
    public string IntegrationsHeader => App.Loc?.Get("Settings.Integrations.SectionHeader") ?? "Integrations";
    public string HintText => App.Loc?.Get("Settings.Integrations.Hint") ?? "Auto-detect or set paths manually";
    public string DetectButtonText => App.Loc?.Get("Settings.Integrations.Detect") ?? "Re-detect";
    public string SlicersHeader => App.Loc?.Get("Settings.Integrations.KindSlicer") ?? "Slicers";
    public string EditorsHeader => App.Loc?.Get("Settings.Integrations.KindEditor") ?? "Editors";
    public string ColumnNameText => App.Loc?.Get("Settings.Integrations.ColumnName") ?? "Application";
    public string ColumnPathText => App.Loc?.Get("Settings.Integrations.ColumnPath") ?? "Path";
    public string ColumnStatusText => App.Loc?.Get("Settings.Integrations.ColumnStatus") ?? "Status";

    public ICommand DetectCommand { get; }

    public SettingsViewModel()
    {
        DetectCommand = new RelayCommand(async () => await ReloadAsync());
    }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        await ReloadAsync(ct);
    }

    private async Task ReloadAsync(CancellationToken ct = default)
    {
        if (AppServices.IntegrationService == null) return;
        IsBusy = true;
        try
        {
            var apps = await AppServices.IntegrationService.GetAppsAsync(ct);
            SlicerRows.Clear();
            EditorRows.Clear();
            foreach (var app in apps)
            {
                var row = new IntegrationAppRowViewModel(app, OnBrowseAsync, OnClearAsync);
                if (app.Kind == IntegrationAppKind.Slicer) SlicerRows.Add(row);
                else EditorRows.Add(row);
            }
        }
        finally { IsBusy = false; }
    }

    private async Task OnBrowseAsync(IntegrationAppRowViewModel row)
    {
        // Диалог выбора файла — вызывается из View через событие;
        // ViewModel делегирует View через событие BrowseRequested.
        var handler = BrowseRequested;
        if (handler == null) return;
        var path = await handler(row);
        if (string.IsNullOrEmpty(path) || AppServices.IntegrationService == null) return;
        await AppServices.IntegrationService.SetPathAsync(row.App.Id, path);
        await ReloadAsync();
    }

    private async Task OnClearAsync(IntegrationAppRowViewModel row)
    {
        if (AppServices.IntegrationService == null) return;
        await AppServices.IntegrationService.SetPathAsync(row.App.Id, null);
        await ReloadAsync();
    }

    public delegate Task<string?> BrowseHandler(IntegrationAppRowViewModel row);
    public event BrowseHandler? BrowseRequested;

    public void RefreshLocalized()
    {
        Raise(nameof(HeaderText));
        Raise(nameof(IntegrationsHeader));
        Raise(nameof(HintText));
        Raise(nameof(DetectButtonText));
        Raise(nameof(SlicersHeader));
        Raise(nameof(EditorsHeader));
        Raise(nameof(ColumnNameText));
        Raise(nameof(ColumnPathText));
        Raise(nameof(ColumnStatusText));
        foreach (var r in SlicerRows) r.RefreshLocalized();
        foreach (var r in EditorRows) r.RefreshLocalized();
    }
}
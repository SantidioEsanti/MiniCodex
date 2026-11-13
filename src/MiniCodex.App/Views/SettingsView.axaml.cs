using Avalonia.Controls;
using Avalonia.Platform.Storage;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
    }

    protected override async void OnAttachedToVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        if (DataContext is SettingsViewModel vm)
        {
            vm.BrowseRequested += OnBrowseRequested;
            await vm.LoadAsync();
        }
    }

    protected override void OnDetachedFromVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        if (DataContext is SettingsViewModel vm)
            vm.BrowseRequested -= OnBrowseRequested;
        base.OnDetachedFromVisualTree(e);
    }

    private async Task<string?> OnBrowseRequested(IntegrationAppRowViewModel row)
    {
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is null) return null;

        var files = await top.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Select executable",
            AllowMultiple = false,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("Executable") { Patterns = new[] { "*.exe" } },
            }
        });
        if (files.Count == 0) return null;
        return files[0].TryGetLocalPath();
    }
}
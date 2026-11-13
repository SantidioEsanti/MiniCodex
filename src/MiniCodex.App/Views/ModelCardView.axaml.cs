using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class ModelCardView : UserControl
{
    public ModelCardView()
    {
        InitializeComponent();
        DragDrop.SetAllowDrop(this, true);
    }

    private void OnDragOver(object? sender, DragEventArgs e)
    {
        e.DragEffects = e.Data.Contains(DataFormats.Files)
            ? DragDropEffects.Copy
            : DragDropEffects.None;
    }

    private async void OnDropReference(object? sender, DragEventArgs e)
    {
        await HandleDropAsync(e, "reference");
    }

    private async void OnDropPhoto(object? sender, DragEventArgs e)
    {
        await HandleDropAsync(e, "photo");
    }

    private async Task HandleDropAsync(DragEventArgs e, string assetType)
    {
        if (DataContext is not ModelCardPageViewModel vm) return;
        if (!e.Data.Contains(DataFormats.Files)) return;

        var files = e.Data.GetFiles();
        if (files == null) return;

        var paths = files
            .Select(f => f.TryGetLocalPath())
            .Where(p => !string.IsNullOrEmpty(p))
            .Cast<string>()
            .ToList();
        if (paths.Count == 0) return;

        await vm.ImportAssetsAsync(paths, assetType);
        e.Handled = true;
    }

    private async void OnAddReferenceClick(object? sender, RoutedEventArgs e)
    {
        await AddFromPickerAsync("reference");
    }

    private async void OnAddPhotoClick(object? sender, RoutedEventArgs e)
    {
        await AddFromPickerAsync("photo");
    }

    private async Task AddFromPickerAsync(string assetType)
    {
        if (DataContext is not ModelCardPageViewModel vm) return;
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is null) return;

        var files = await top.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Add associations",
            AllowMultiple = true,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("Images") { Patterns = new[] { "*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp" } },
                new FilePickerFileType("Documents") { Patterns = new[] { "*.pdf" } },
                new FilePickerFileType("All files") { Patterns = new[] { "*" } },
            }
        });
        if (files.Count == 0) return;

        var paths = files
            .Select(f => f.TryGetLocalPath())
            .Where(p => !string.IsNullOrEmpty(p))
            .Cast<string>()
            .ToList();
        if (paths.Count == 0) return;

        await vm.ImportAssetsAsync(paths, assetType);
    }
}
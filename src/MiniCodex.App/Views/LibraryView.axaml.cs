using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using MiniCodex.App.ViewModels;
using MiniCodex.Core.Logging;

namespace MiniCodex.App.Views;

public partial class LibraryView : UserControl
{
    public LibraryView()
    {
        InitializeComponent();
    }

    protected override void OnAttachedToVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        if (DataContext is LibraryViewModel vm)
            vm.FocusSearchRequested += OnFocusSearchRequested;
    }

    protected override async void OnDetachedFromVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        if (DataContext is LibraryViewModel vm)
        {
            vm.FocusSearchRequested -= OnFocusSearchRequested;
            try
            {
                await vm.DisposeAsync();
            }
            catch (Exception ex)
            {
                Log.Exception("[LibraryView] dispose failed", ex);
            }
        }
        base.OnDetachedFromVisualTree(e);
    }

    private void OnFocusSearchRequested(object? sender, EventArgs e)
    {
        SearchBox?.Focus();
    }

    protected override async void OnLoaded(RoutedEventArgs e)
    {
        base.OnLoaded(e);
        try
        {
            if (DataContext is LibraryViewModel vm)
            {
                Log.Info("[LibraryView] OnLoaded -> vm.LoadAsync");
                await vm.LoadAsync();
            }
        }
        catch (Exception ex) { Log.Exception("[LibraryView] OnLoaded failed", ex); }
    }

    private async void OnScanClick(object? sender, RoutedEventArgs e)
    {
        try
        {
            Log.Info("[LibraryView] OnScanClick begin");
            if (DataContext is not LibraryViewModel vm) return;
            var topLevel = TopLevel.GetTopLevel(this);
            if (topLevel?.StorageProvider is null) return;

            var folders = await topLevel.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
            {
                Title = App.Loc?.Get("Library.ScanFolderTitle") ?? "Select source folder",
                AllowMultiple = true,
            });
            Log.Info("[LibraryView] OnScanClick folders=" + folders.Count);
            if (folders.Count == 0) return;

            var paths = folders
                .Select(f => f.TryGetLocalPath())
                .Where(p => !string.IsNullOrEmpty(p))
                .Cast<string>()
                .ToList();
            if (paths.Count == 0) return;

            await vm.ScanAsync(paths);
        }
        catch (Exception ex) { Log.Exception("[LibraryView] OnScanClick failed", ex); }
    }

    private void OnTagSelectionChanged(object? sender, Avalonia.Controls.SelectionChangedEventArgs e)
    {
        if (sender is Avalonia.Controls.TreeView tv && tv.SelectedItem is MiniCodex.App.ViewModels.TagNodeViewModel node)
        {
            if (DataContext is MiniCodex.App.ViewModels.LibraryViewModel vm && vm.SelectedTag != node)
            {
                vm.SelectedTag = node;
            }
        }
    }
}
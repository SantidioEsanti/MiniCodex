using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class ModelCardView : UserControl
{
    private ModelCardPageViewModel? _vm;

    public ModelCardView()
    {
        InitializeComponent();
        DragDrop.SetAllowDrop(this, true);
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object? sender, EventArgs e)
    {
        if (_vm != null)
        {
            _vm.PropertyChanged -= OnVmPropertyChanged;
            _vm.ReplaceRequested -= OnReplaceRequested;
        }
        _vm = DataContext as ModelCardPageViewModel;
        if (_vm != null)
        {
            _vm.PropertyChanged += OnVmPropertyChanged;
            _vm.ReplaceRequested += OnReplaceRequested;
        }
    }

    private void OnVmPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ModelCardPageViewModel.IsFullScreenOpen))
        {
            if (_vm != null && _vm.IsFullScreenOpen)
            {
                Dispatcher.UIThread.Post(() =>
                {
                    if (FullScreenGrid != null) FullScreenGrid.Focus();
                }, DispatcherPriority.Input);
            }
        }
        else if (e.PropertyName == nameof(ModelCardPageViewModel.ShowRemoveAssetConfirm))
        {
            if (_vm != null && _vm.ShowRemoveAssetConfirm)
            {
                Dispatcher.UIThread.Post(() =>
                {
                    if (RemoveConfirmGrid != null) RemoveConfirmGrid.Focus();
                }, DispatcherPriority.Input);
            }
        }
    }

    private async void OnReplaceRequested(object? sender, AssetRowViewModel row)
    {
        if (_vm == null) return;
        var top = TopLevel.GetTopLevel(this);
        if (top?.StorageProvider is null) return;

        var files = await top.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Replace asset",
            AllowMultiple = false,
            FileTypeFilter = new[]
            {
                new FilePickerFileType("All files") { Patterns = new[] { "*" } },
            }
        });
        if (files.Count == 0) return;
        var path = files[0].TryGetLocalPath();
        if (string.IsNullOrEmpty(path)) return;
        await _vm.ReplaceAssetAsync(row, path);
    }

    private void OnThumbnailPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        // Let the small X Button win: it marks the event Handled.
        if (e.Handled) return;
        var point = e.GetCurrentPoint(this);
        if (!point.Properties.IsLeftButtonPressed) return;
        if (e.ClickCount != 2) return;  // double-click opens fullscreen
        if (sender is Control c && c.DataContext is AssetRowViewModel row)
        {
            if (row.IsImage && row.OpenFullScreenCommand.CanExecute(null))
            {
                row.OpenFullScreenCommand.Execute(null);
                e.Handled = true;
            }
        }
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
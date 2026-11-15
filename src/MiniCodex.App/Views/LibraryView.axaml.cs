using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Presenters;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Avalonia.VisualTree;
using MiniCodex.App.ViewModels;
using MiniCodex.Core.Logging;

namespace MiniCodex.App.Views;

public partial class LibraryView : UserControl
{
    // --- rubber-band state ---
    private bool _rubberActive;
    private Point _rubberStart;
    private Point _rubberCurrent;
    private bool _rubberWasDragged;
    private bool _rubberAdditive;
    private HashSet<ModelCardViewModel> _rubberOriginalSelection = new();

    // --- double-click detection ---
    private DateTime _lastClickTime = DateTime.MinValue;
    private ModelCardViewModel? _lastClickedCard;

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

    // ============================================================
    // Multi-select (0.5.6b.2)
    // ============================================================

    private void OnCardsPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (e.Handled) return;
        if (DataContext is not LibraryViewModel vm) return;
        if (CardsHost == null) return;

        var point = e.GetCurrentPoint(CardsHost);
        var tile = FindAncestor<ModelCardTile>(e.Source as Visual);

        // Right-click: sync selection to the clicked card if not selected.
        if (point.Properties.IsRightButtonPressed)
        {
            if (tile != null && tile.DataContext is ModelCardViewModel rc && !rc.IsSelected)
            {
                vm.ClearSelection();
                rc.IsSelected = true;
                vm.RefreshSelectionCollections();
            }
            return; // let context menu open
        }

        if (!point.Properties.IsLeftButtonPressed) return;

        // Card click (single / Ctrl / Shift / double for open)
        if (tile != null && tile.DataContext is ModelCardViewModel card)
        {
            var isCtrl = (e.KeyModifiers & KeyModifiers.Control) != 0;
            var isShift = (e.KeyModifiers & KeyModifiers.Shift) != 0;

            var now = DateTime.UtcNow;
            if (!isCtrl && !isShift
                && ReferenceEquals(card, _lastClickedCard)
                && (now - _lastClickTime).TotalMilliseconds < 400)
            {
                _lastClickedCard = null;
                _lastClickTime = DateTime.MinValue;
                if (card.OpenCommand.CanExecute(null)) card.OpenCommand.Execute(null);
                e.Handled = true;
                return;
            }
            _lastClickedCard = card;
            _lastClickTime = now;

            vm.OnCardClicked(card, isCtrl, isShift);
            e.Handled = true;
            return;
        }

        // Empty space: start rubber band
        _rubberActive = true;
        _rubberStart = point.Position;
        _rubberCurrent = _rubberStart;
        _rubberWasDragged = false;
        _rubberAdditive = (e.KeyModifiers & KeyModifiers.Control) != 0;
        _rubberOriginalSelection = new HashSet<ModelCardViewModel>(vm.SelectedCards);

        if (!_rubberAdditive)
        {
            foreach (var c in vm.Cards) c.IsSelected = false;
            vm.RefreshSelectionCollections();
        }

        e.Pointer.Capture(CardsHost);
        e.Handled = true;
    }

    private void OnCardsPointerMoved(object? sender, PointerEventArgs e)
    {
        if (!_rubberActive) return;
        if (DataContext is not LibraryViewModel vm) return;
        if (CardsHost == null || SelectionRect == null) return;

        _rubberCurrent = e.GetPosition(CardsHost);
        var dx = Math.Abs(_rubberCurrent.X - _rubberStart.X);
        var dy = Math.Abs(_rubberCurrent.Y - _rubberStart.Y);
        if (dx > 3 || dy > 3) _rubberWasDragged = true;
        if (!_rubberWasDragged) return;

        var rect = new Rect(
            Math.Min(_rubberStart.X, _rubberCurrent.X),
            Math.Min(_rubberStart.Y, _rubberCurrent.Y),
            dx, dy);

        Canvas.SetLeft(SelectionRect, rect.X);
        Canvas.SetTop(SelectionRect, rect.Y);
        SelectionRect.Width = rect.Width;
        SelectionRect.Height = rect.Height;
        SelectionRect.IsVisible = true;

        UpdateRubberSelection(vm, rect);
    }

    private void UpdateRubberSelection(LibraryViewModel vm, Rect rubberRect)
    {
        if (CardsItemsControl == null || CardsHost == null) return;
        var wrapPanel = FindVisualChild<WrapPanel>(CardsItemsControl);
        if (wrapPanel == null) return;

        var intersecting = new HashSet<ModelCardViewModel>();
        foreach (var child in wrapPanel.Children)
        {
            if (child is ContentPresenter cp && cp.Child is ModelCardTile tile
                && tile.DataContext is ModelCardViewModel card)
            {
                var topLeft = tile.TranslatePoint(new Point(0, 0), CardsHost);
                if (topLeft == null) continue;
                var tileRect = new Rect(topLeft.Value, tile.Bounds.Size);
                if (tileRect.Intersects(rubberRect))
                    intersecting.Add(card);
            }
        }

        foreach (var card in vm.Cards)
        {
            card.IsSelected = _rubberAdditive
                ? _rubberOriginalSelection.Contains(card) || intersecting.Contains(card)
                : intersecting.Contains(card);
        }
        vm.RefreshSelectionCollections();
    }

    private void OnCardsPointerReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (!_rubberActive) return;
        _rubberActive = false;
        e.Pointer.Capture(null);

        if (SelectionRect != null)
        {
            SelectionRect.IsVisible = false;
            SelectionRect.Width = 0;
            SelectionRect.Height = 0;
        }

        if (DataContext is LibraryViewModel vm)
        {
            if (!_rubberWasDragged && !_rubberAdditive)
            {
                vm.ClearSelection();
            }
            else
            {
                vm.RefreshSelectionCollections();
            }
        }
        e.Handled = true;
    }

    private static T? FindAncestor<T>(Visual? visual) where T : Visual
    {
        var current = visual;
        while (current != null)
        {
            if (current is T t) return t;
            current = current.GetVisualParent();
        }
        return null;
    }

    private static T? FindVisualChild<T>(Visual? parent) where T : Visual
    {
        if (parent == null) return null;
        foreach (var child in parent.GetVisualChildren())
        {
            if (child is T t) return t;
            var res = FindVisualChild<T>(child);
            if (res != null) return res;
        }
        return null;
    }
}
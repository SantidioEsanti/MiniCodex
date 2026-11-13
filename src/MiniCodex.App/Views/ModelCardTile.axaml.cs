using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class ModelCardTile : UserControl
{
    public ModelCardTile()
    {
        InitializeComponent();
        DoubleTapped += OnDoubleTapped;
    }

    private void OnDoubleTapped(object? sender, TappedEventArgs e)
    {
        if (DataContext is ModelCardViewModel vm)
        {
            if (vm.OpenCommand.CanExecute(null))
                vm.OpenCommand.Execute(null);
            e.Handled = true;
        }
    }

    protected override void OnPointerEntered(PointerEventArgs e)
    {
        base.OnPointerEntered(e);
        if (DataContext is ModelCardViewModel vm)
            vm.IsHovered = true;
    }

    protected override void OnPointerExited(PointerEventArgs e)
    {
        base.OnPointerExited(e);
        if (DataContext is ModelCardViewModel vm)
            vm.IsHovered = false;
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        if (DataContext is not ModelCardViewModel vm) return;
        if (!vm.IsHovered || !vm.HasRotation) return;

        var pos = e.GetPosition(this);
        var width = Bounds.Width;
        if (width <= 0) return;

        var relative = Math.Clamp(pos.X / width, 0.0, 0.9999);
        var index = (int)(relative * 4);
        vm.RotateTo(index);
    }
}
using Avalonia.Controls;
using MiniCodex.App.ViewModels;

namespace MiniCodex.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainWindowViewModel();
    }
}
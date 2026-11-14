using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Media;

namespace MiniCodex.App.ViewModels;

public class TagNodeViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? ParentId { get; set; }

    private int _usageCount;
    public int UsageCount
    {
        get => _usageCount;
        set { _usageCount = value; Raise(); }
    }

    private string? _color;
    public string? Color
    {
        get => _color;
        set
        {
            if (_color == value) return;
            _color = value;
            Raise();
            Raise(nameof(HasColor));
            Raise(nameof(ColorBrush));
        }
    }

    public bool HasColor => !string.IsNullOrWhiteSpace(_color);

    public IBrush? ColorBrush
    {
        get
        {
            if (string.IsNullOrWhiteSpace(_color)) return null;
            if (Avalonia.Media.Color.TryParse(_color, out var c))
                return new SolidColorBrush(c);
            return null;
        }
    }

    public Action<TagNodeViewModel, string?>? OnColorChange { get; set; }

    public ICommand SetColorCommand { get; }
    public ICommand ClearColorCommand { get; }
    public ICommand RenameCommand { get; }
    public ICommand DeleteCommand { get; }
    public ICommand CustomColorCommand { get; }
    public string ClearColorLabel => App.Loc?.Get("Library.ClearColor") ?? "Clear color";
    public string RenameLabel => App.Loc?.Get("Library.TagContextMenu.Rename") ?? "Rename...";
    public string DeleteLabel => App.Loc?.Get("Library.TagContextMenu.Delete") ?? "Delete";
    public string CustomColorLabel => App.Loc?.Get("Library.TagContextMenu.CustomColor") ?? "Custom color...";

    public Action<TagNodeViewModel>? OnRename { get; set; }
    public Action<TagNodeViewModel>? OnDelete { get; set; }
    public Action<TagNodeViewModel>? OnCustomColor { get; set; }

    public void RefreshLocalized()
    {
        Raise(nameof(ClearColorLabel));
        Raise(nameof(RenameLabel));
        Raise(nameof(DeleteLabel));
        Raise(nameof(CustomColorLabel));
        foreach (var c in Children) c.RefreshLocalized();
    }

    public static IReadOnlyList<string> Palette { get; } = new[]
    {
        "#E67E22",
        "#E74C3C",
        "#F39C12",
        "#2ECC71",
        "#3498DB",
        "#9B59B6",
        "#95A5A6",
        "#34495E",
    };

    public ObservableCollection<TagNodeViewModel> Children { get; } = new();

    private bool _isExpanded = true;
    public bool IsExpanded
    {
        get => _isExpanded;
        set { _isExpanded = value; Raise(); }
    }

    public TagNodeViewModel()
    {
        SetColorCommand = new RelayCommand(
            p =>
            {
                if (p is string s && !string.IsNullOrWhiteSpace(s))
                    OnColorChange?.Invoke(this, s);
            },
            _ => !string.IsNullOrEmpty(Id));
        ClearColorCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnColorChange?.Invoke(this, null); },
            () => !string.IsNullOrEmpty(Id));
        RenameCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnRename?.Invoke(this); },
            () => !string.IsNullOrEmpty(Id));
        DeleteCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnDelete?.Invoke(this); },
            () => !string.IsNullOrEmpty(Id));
        CustomColorCommand = new RelayCommand(
            () => { if (!string.IsNullOrEmpty(Id)) OnCustomColor?.Invoke(this); },
            () => !string.IsNullOrEmpty(Id));
    }

    public override bool Equals(object? obj) => obj is TagNodeViewModel other && Id == other.Id;
    public override int GetHashCode() => Id.GetHashCode();
}
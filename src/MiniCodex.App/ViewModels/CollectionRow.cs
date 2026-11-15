using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Media;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;

namespace MiniCodex.App.ViewModels;

public class CollectionRow : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public string Id { get; init; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public SmartCollectionFilter Filter { get; set; } = SmartCollectionFilter.Empty;
    public bool IsSmart { get; set; } = true;

    private string? _color;
    public string? Color
    {
        get => _color;
        set
        {
            if (_color == value) return;
            _color = value;
            Raise();
            Raise(nameof(ColorBrush));
            Raise(nameof(HasColor));
        }
    }

    public IBrush? ColorBrush => string.IsNullOrWhiteSpace(_color)
        ? null
        : (Avalonia.Media.Color.TryParse(_color, out var c) ? new SolidColorBrush(c) : null);

    public bool HasColor => ColorBrush != null;

    public static readonly IReadOnlyList<string> Palette = new[]
    {
        "#E67E22", "#E74C3C", "#F39C12", "#2ECC71",
        "#3498DB", "#9B59B6", "#95A5A6", "#34495E"
    };

    public Action<CollectionRow, string?>? OnColorChange { get; set; }

    public ICommand SetColorCommand { get; }
    public ICommand ClearColorCommand { get; }

    public string ClearColorLabel => App.Loc?.Get("Library.ClearColor") ?? "Clear color";

    public CollectionRow()
    {
        SetColorCommand = new RelayCommand(p =>
        {
            if (p is string s) OnColorChange?.Invoke(this, s);
        });
        ClearColorCommand = new RelayCommand(() => OnColorChange?.Invoke(this, null));
    }

    public static CollectionRow From(Collection c) => new()
    {
        Id = c.Id,
        Name = c.Name,
        Filter = CollectionService.DeserializeFilter(c.FilterQuery),
        IsSmart = c.IsSmart,
        Color = c.Color,
    };
}
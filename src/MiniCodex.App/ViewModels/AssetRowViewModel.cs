using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Avalonia.Media.Imaging;
using MiniCodex.Core.Models;

namespace MiniCodex.App.ViewModels;

public class AssetRowViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public Asset Asset { get; }
    public string DisplayName => Path.GetFileName(Asset.AbsolutePath);
    public string AssetTypeText => Asset.AssetType ?? "-";

    private Bitmap? _thumbnail;
    public Bitmap? Thumbnail
    {
        get => _thumbnail;
        private set { _thumbnail = value; Raise(); }
    }

    public ICommand RemoveCommand { get; }

    public AssetRowViewModel(Asset asset, Func<AssetRowViewModel, Task> onRemove)
    {
        Asset = asset;
        RemoveCommand = new RelayCommand(async () => await onRemove(this));
    }

    public void SetThumbnail(Bitmap? bitmap) => Thumbnail = bitmap;
}
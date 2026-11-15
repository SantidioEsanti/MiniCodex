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
    public string PathText => Asset.AbsolutePath;

    public bool IsImage
    {
        get
        {
            var ext = (Path.GetExtension(Asset.AbsolutePath) ?? string.Empty).ToLowerInvariant();
            return ext == ".png" || ext == ".jpg" || ext == ".jpeg"
                || ext == ".webp" || ext == ".gif" || ext == ".bmp";
        }
    }

    public bool IsDocument
    {
        get
        {
            var ext = (Path.GetExtension(Asset.AbsolutePath) ?? string.Empty).ToLowerInvariant();
            return ext == ".pdf" || ext == ".doc" || ext == ".docx" || ext == ".txt";
        }
    }

    public bool IsProfile
    {
        get
        {
            var ext = (Path.GetExtension(Asset.AbsolutePath) ?? string.Empty).ToLowerInvariant();
            return ext == ".json" || ext == ".ini" || ext == ".xml" || ext == ".cfg";
        }
    }

    public string AssetIconGlyph
    {
        get
        {
            if (IsImage) return "\uD83D\uDDBC";      // framed picture
            if (IsDocument) return "\uD83D\uDCC4";  // page
            if (IsProfile) return "\u2699";         // gear
            return "\uD83D\uDCC1";                  // folder
        }
    }

    public string FileSizeText
    {
        get
        {
            try
            {
                var fi = new FileInfo(Asset.AbsolutePath);
                if (!fi.Exists) return "-";
                var bytes = fi.Length;
                if (bytes < 1024) return bytes + " B";
                if (bytes < 1024L * 1024L) return (bytes / 1024.0).ToString("F1") + " KB";
                if (bytes < 1024L * 1024L * 1024L) return (bytes / (1024.0 * 1024.0)).ToString("F1") + " MB";
                return (bytes / (1024.0 * 1024.0 * 1024.0)).ToString("F2") + " GB";
            }
            catch { return "-"; }
        }
    }

    private Bitmap? _thumbnail;
    public Bitmap? Thumbnail
    {
        get => _thumbnail;
        private set { _thumbnail = value; Raise(); }
    }

    private Bitmap? _fullBitmap;
    public Bitmap? FullBitmap
    {
        get => _fullBitmap;
        private set { _fullBitmap = value; Raise(); }
    }

    private bool _isFullBitmapLoading;
    public bool IsFullBitmapLoading
    {
        get => _isFullBitmapLoading;
        private set { _isFullBitmapLoading = value; Raise(); }
    }

    public ICommand RemoveCommand { get; }
    public ICommand OpenFullScreenCommand { get; }
    public ICommand OpenExternalCommand { get; }
    public ICommand OpenInExplorerCommand { get; }
    public ICommand CopyPathCommand { get; }
    public ICommand ReplaceCommand { get; }

    private readonly Func<AssetRowViewModel, Task> _onRemove;
    private readonly Func<AssetRowViewModel, Task> _onOpenFullScreen;
    private readonly Func<AssetRowViewModel, Task> _onOpenExternal;
    private readonly Func<AssetRowViewModel, Task> _onOpenInExplorer;
    private readonly Func<AssetRowViewModel, Task> _onCopyPath;
    private readonly Func<AssetRowViewModel, Task> _onReplace;

    public AssetRowViewModel(
        Asset asset,
        Func<AssetRowViewModel, Task> onRemove,
        Func<AssetRowViewModel, Task>? onOpenFullScreen = null,
        Func<AssetRowViewModel, Task>? onOpenExternal = null,
        Func<AssetRowViewModel, Task>? onOpenInExplorer = null,
        Func<AssetRowViewModel, Task>? onCopyPath = null,
        Func<AssetRowViewModel, Task>? onReplace = null)
    {
        Asset = asset;
        _onRemove = onRemove;
        _onOpenFullScreen = onOpenFullScreen ?? (_ => Task.CompletedTask);
        _onOpenExternal = onOpenExternal ?? (_ => Task.CompletedTask);
        _onOpenInExplorer = onOpenInExplorer ?? (_ => Task.CompletedTask);
        _onCopyPath = onCopyPath ?? (_ => Task.CompletedTask);
        _onReplace = onReplace ?? (_ => Task.CompletedTask);

        RemoveCommand = new RelayCommand(async () => await _onRemove(this));
        OpenFullScreenCommand = new RelayCommand(async () => await _onOpenFullScreen(this));
        OpenExternalCommand = new RelayCommand(async () => await _onOpenExternal(this));
        OpenInExplorerCommand = new RelayCommand(async () => await _onOpenInExplorer(this));
        CopyPathCommand = new RelayCommand(async () => await _onCopyPath(this));
        ReplaceCommand = new RelayCommand(async () => await _onReplace(this));
    }

    // ---------- Asset context menu labels (bound from ContextMenu items) ----------
    public string ContextOpenText => Loc("Card.Asset.Context.Open", "Open (full screen)");
    public string ContextOpenExternalText => Loc("Card.Asset.Context.OpenExternal", "Open with default viewer");
    public string ContextOpenInExplorerText => Loc("Card.Asset.Context.OpenInExplorer", "Open in Explorer");
    public string ContextCopyPathText => Loc("Card.Asset.Context.CopyPath", "Copy path");
    public string ContextReplaceText => Loc("Card.Asset.Context.Replace", "Replace...");
    public string ContextRemoveText => Loc("Card.Asset.Context.Remove", "Remove");

    private static string Loc(string key, string fallback) => App.Loc?.Get(key) ?? fallback;

    public void SetThumbnail(Bitmap? bitmap) => Thumbnail = bitmap;

    public async Task LoadFullBitmapAsync(int maxWidth, CancellationToken ct = default)
    {
        if (FullBitmap != null) return;
        if (!IsImage) return;
        if (!File.Exists(Asset.AbsolutePath)) return;
        if (IsFullBitmapLoading) return;
        try
        {
            IsFullBitmapLoading = true;
            var bmp = await Task.Run(() =>
            {
                using var stream = File.OpenRead(Asset.AbsolutePath);
                return Bitmap.DecodeToWidth(stream, maxWidth);
            }, ct);
            await Avalonia.Threading.Dispatcher.UIThread.InvokeAsync(() => FullBitmap = bmp);
        }
        catch
        {
            // ignore - caller will show fallback if needed
        }
        finally
        {
            IsFullBitmapLoading = false;
        }
    }

    public void ClearFullBitmap()
    {
        FullBitmap = null;
    }
}
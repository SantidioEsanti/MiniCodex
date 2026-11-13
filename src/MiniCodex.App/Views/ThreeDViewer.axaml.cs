using Avalonia;
using Avalonia.Controls;
using Avalonia.Data;
using Avalonia.Input;
using Avalonia.Media.Imaging;
using Avalonia.Styling;
using Avalonia.Threading;
using MiniCodex.App.ViewModels;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Render.Loaders;
using MiniCodex.Render.Rendering;

namespace MiniCodex.App.Views;

public partial class ThreeDViewer : UserControl
{
    private readonly SkiaPreviewRenderer _renderer = new();
    private readonly AssimpMeshLoader _loader = new();
    private MeshGeometry? _geometry;

    private float _yaw = 180f;
    private float _pitch = 15f;
    private float _zoom = 1.0f;
    private Point? _lastPointer;
    private bool _isDragging;
    private bool _renderInProgress;
    private bool _renderPending;
    private int _renderWidth = 480;
    private int _renderHeight = 480;

    public static readonly StyledProperty<string?> MeshFilePathProperty =
        AvaloniaProperty.Register<ThreeDViewer, string?>(nameof(MeshFilePath));

    public static readonly StyledProperty<float> MinLambertProperty =
        AvaloniaProperty.Register<ThreeDViewer, float>(nameof(MinLambert), 0.4f);

    public static readonly StyledProperty<bool> WireframeProperty =
        AvaloniaProperty.Register<ThreeDViewer, bool>(nameof(Wireframe));

    public static readonly StyledProperty<float> YawProperty =
        AvaloniaProperty.Register<ThreeDViewer, float>(nameof(Yaw), 180f, defaultBindingMode: BindingMode.TwoWay);

    public static readonly StyledProperty<float> PitchProperty =
        AvaloniaProperty.Register<ThreeDViewer, float>(nameof(Pitch), 15f, defaultBindingMode: BindingMode.TwoWay);

    public string? MeshFilePath
    {
        get => GetValue(MeshFilePathProperty);
        set => SetValue(MeshFilePathProperty, value);
    }

    public float MinLambert
    {
        get => GetValue(MinLambertProperty);
        set => SetValue(MinLambertProperty, value);
    }

    public bool Wireframe
    {
        get => GetValue(WireframeProperty);
        set => SetValue(WireframeProperty, value);
    }

    public float Yaw
    {
        get => GetValue(YawProperty);
        set => SetValue(YawProperty, value);
    }

    public float Pitch
    {
        get => GetValue(PitchProperty);
        set => SetValue(PitchProperty, value);
    }

    public ThreeDViewer()
    {
        InitializeComponent();
        SizeChanged += (_, e) =>
        {
            _renderWidth = Math.Max(128, (int)e.NewSize.Width);
            _renderHeight = Math.Max(128, (int)e.NewSize.Height);
            RequestRender();
        };
        if (Application.Current != null)
            Application.Current.ActualThemeVariantChanged += OnThemeChanged;
    }

    private void OnThemeChanged(object? sender, EventArgs e) => RequestRender();

    protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
    {
        base.OnPropertyChanged(change);
        if (change.Property == MeshFilePathProperty)
            _ = LoadGeometryAsync(change.GetNewValue<string?>());
        else if (change.Property == YawProperty)
        {
            _yaw = change.GetNewValue<float>();
            RequestRender();
        }
        else if (change.Property == PitchProperty)
        {
            _pitch = change.GetNewValue<float>();
            RequestRender();
        }
        else if (change.Property == MinLambertProperty || change.Property == WireframeProperty)
            RequestRender();
    }

    private RenderStyle BuildStyle()
    {
        var isDark = Application.Current?.ActualThemeVariant == ThemeVariant.Dark;
        uint bg = isDark ? 0xFF2D2D2D : 0xFFE0E0E0;
        return new RenderStyle
        {
            BackgroundArgb = bg,
            ModelArgb = 0xFFFFFFFF,
            MinLambert = Math.Clamp(MinLambert, 0f, 1f),
            Wireframe = Wireframe,
        };
    }

    private void SetViewState(ThreeDViewState state, string? error = null)
    {
        if (DataContext is ModelCardPageViewModel vm)
        {
            vm.ThreeDViewState = state;
            vm.ThreeDErrorMessage = error;
        }
    }

    private async Task LoadGeometryAsync(string? path)
    {
        _geometry = null;
        PreviewHost.Source = null;

        if (string.IsNullOrEmpty(path))
        {
            SetViewState(ThreeDViewState.FileNotChosen);
            return;
        }

        SetViewState(ThreeDViewState.Loading);
        try
        {
            var geo = await Task.Run(() => _loader.LoadGeometry(path));
            if (geo == null)
            {
                SetViewState(ThreeDViewState.ParseFailed);
                return;
            }
            _geometry = geo;
            SetViewState(ThreeDViewState.Loaded);
            RequestRender();
        }
        catch (Exception ex)
        {
            SetViewState(ThreeDViewState.Error, ex.Message);
        }
    }

    private void RequestRender()
    {
        if (_geometry == null) return;
        if (_renderInProgress) { _renderPending = true; return; }
        _renderInProgress = true;
        _ = RenderLoop();
    }

    private async Task RenderLoop()
    {
        try
        {
            while (true)
            {
                _renderPending = false;
                var yaw = _yaw; var pitch = _pitch; var zoom = _zoom;
                var geo = _geometry;
                var style = BuildStyle();
                if (geo == null) break;

                // Internal drag optimization (not exposed to user): during drag render at
                // half resolution + SS=1 (4x faster), after release render at full res + SS=2.
                int w = _renderWidth, h = _renderHeight, ss = 2;
                if (_isDragging)
                {
                    w = Math.Max(96, _renderWidth / 2);
                    h = Math.Max(96, _renderHeight / 2);
                    ss = 1;
                }

                byte[]? png = null;
                try
                {
                    png = await Task.Run(() => _renderer.Render(geo, w, h, yaw, pitch, zoom, style, ss));
                }
                catch { }

                if (png != null)
                {
                    await Dispatcher.UIThread.InvokeAsync(() =>
                    {
                        try
                        {
                            using var ms = new MemoryStream(png);
                            PreviewHost.Source = new Bitmap(ms);
                        }
                        catch { }
                    });
                }
                if (!_renderPending) break;
            }
        }
        finally
        {
            _renderInProgress = false;
            if (_renderPending) RequestRender();
        }
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        _lastPointer = e.GetPosition(this);
        e.Pointer.Capture(this);
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        _lastPointer = null;
        e.Pointer.Capture(null);

        if (_isDragging)
        {
            _isDragging = false;
            RequestRender();
        }
    }

    protected override void OnPointerMoved(PointerEventArgs e)
    {
        base.OnPointerMoved(e);
        if (_lastPointer == null || _geometry == null) return;
        var pos = e.GetPosition(this);
        var dx = (float)(pos.X - _lastPointer.Value.X);
        var dy = (float)(pos.Y - _lastPointer.Value.Y);
        _lastPointer = pos;

        if (Math.Abs(dx) + Math.Abs(dy) < 0.5f) return;

        _isDragging = true;
        _yaw += dx * 0.5f;
        _pitch = Math.Clamp(_pitch + dy * 0.5f, -89f, 89f);

        SetCurrentValue(YawProperty, _yaw);
        SetCurrentValue(PitchProperty, _pitch);

        RequestRender();
    }

    protected override void OnPointerWheelChanged(PointerWheelEventArgs e)
    {
        base.OnPointerWheelChanged(e);
        if (_geometry == null) return;
        _zoom = Math.Clamp(_zoom * (1f + (float)e.Delta.Y * 0.1f), 0.2f, 5f);
        RequestRender();
        e.Handled = true;
    }
}
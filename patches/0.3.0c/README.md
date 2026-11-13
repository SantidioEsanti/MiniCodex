# Патч 0.3.0c — тема-зависимый фон 3D-вьюера + MinLambert + wireframe

**Итерация:** 0.3 · **Статус:** реализован

## Что делает

### Тема-зависимый фон (основное)
- `RenderStyle` (Core) — record с `BackgroundArgb`, `ModelArgb`, `MinLambert`, `Wireframe`.
- `IPreviewRenderer.Render` — параметр `RenderStyle? style = null` (null = дефолт = светлый фон, белая модель, MinLambert=0.4).
- `SkiaPreviewRenderer` — использует стиль: фон и цвет модели из ARGB, `MinLambert` из стиля.
- `ThreeDViewer` подписан на `Application.Current.ActualThemeVariantChanged`; при смене темы строит style с `BackgroundArgb` = `#2D2D2D` (dark) или `#E0E0E0` (light) и перерисовывает.
- `ThreeDViewer.axaml` — Border под Image тоже `DynamicResource`, чтобы не было белых краёв.

### MinLambert
- Слайдер `0..1` в верхней панели карточки.
- Сохраняется в `Setting` (ключ `Render.MinLambert`), восстанавливается при открытии любой карточки.
- Влияет только на **живой** 3D-вьюер, кэш превью библиотеки не трогает (там всегда `0.4`).

### Wireframe
- Чекбокс `Wireframe`.
- `SkiaPreviewRenderer`: `DrawLine` (Bresenham с z-buffer) вместо заливки треугольников.
- Цвет рёбер адаптивный: `#282828` на светлом фоне, `#DCDCDC` на тёмном.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.0c\patch_0.3.0c.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24/24.
- Смена темы (auto→dark→light) при открытой карточке → фон 3D-вьюера меняется.
- Слайдер «Мягкость теней»: при 0 — контрастные тени, при 1 — плоский белый силуэт.
- Чекбокс «Каркас» → модель показана рёбрами.
- Значение слайдера сохраняется между перезапусками.
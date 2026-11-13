# Патч 0.3.1a — фикс сборки Render

**Итерация:** 0.3 · **Статус:** реализован

## Причина

`SkiaThumbnailGenerator.Placeholder` использовал `SKAlphaPremul` — но в SkiaSharp
это `SKAlphaType.Premul` (член перечисления), а не константа. Ошибка CS0103.

## Что делает

- Заменяет `SKAlphaPremul` → `SKAlphaType.Premul` в `src/MiniCodex.Render/Rendering/SkiaThumbnailGenerator.cs`.
- Логика не меняется.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.1a\patch_0.3.1a.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 28/28.
# Патч 0.3.0a — фикс stub-рендерера в тестах

**Итерация:** 0.3 · **Статус:** реализован

## Причина

`IPreviewRenderer.Render` получил 6-й параметр `float zoom = 1.0f` в патче 0.3.0.
Stub-реализация в `PreviewGeneratorTests.cs` осталась с 5 аргументами → CS0535.

## Что делает

- `StubRenderer.Render` теперь `(MeshGeometry, int, int, float, float, float zoom = 1.0f)`.
- Логика stub не меняется (по-прежнему возвращает PNG-сигнатуру + счётчик).

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.0a\patch_0.3.0a.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24/24.
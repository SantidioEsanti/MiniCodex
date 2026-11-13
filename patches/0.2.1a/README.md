# Патч 0.2.1a — фикс сборки тестов

**Итерация:** 0.2 · **Статус:** реализован

## Что делает

- Добавляет `using MiniCodex.Core.Repositories;` в `src\MiniCodex.Tests\Services\ScannerServiceTests.cs`.
- Причина: поля теста используют `IModelRepository` и `IModelFileRepository` из `MiniCodex.Core.Repositories`, но в файле отсутствовала соответствующая директива `using`.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.1a\patch_0.2.1a.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 17 тестов, все зелёные.
# Патч 0.3.1b — фикс сборки тестов

**Итерация:** 0.3 · **Статус:** реализован

## Причина

`AssetServiceTests.cs` объявляет поля через интерфейсы из `MiniCodex.Core.Repositories`
(`IModelRepository`, `IModelFileRepository`, `IAssetRepository`), но не подключает
соответствующий namespace. Тот же паттерн, что в 0.2.1a со `ScannerServiceTests.cs`.

## Что делает

- Добавляет `using MiniCodex.Core.Repositories;` в `src/MiniCodex.Tests/Services/AssetServiceTests.cs`.
- Логика не меняется.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.1b\patch_0.3.1b.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 28/28.
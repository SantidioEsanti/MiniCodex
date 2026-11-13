# Патч 0.1.0 — Инициализация репозитория и скелет решения

**Итерация:** 0.1 (Фундамент)
**Статус:** реализован
**Задачи:** см. `docs/ROADMAP.md`, раздел 2.1.

## Что делает

- Создаёт `src/MiniCodex.sln` и четыре `.csproj` (Core, Data, Render, Tests).
- Обновляет `src/MiniCodex.App/MiniCodex.App.csproj`: Avalonia 11, копирование `lang/*.json` в выход.
- Наполняет `src/MiniCodex.App` скелетом: `Program.cs`, `App.axaml`, `MainWindow.axaml`, ViewModel, сервисы (`AppPaths`, `LocalizationService`, `ThemeService`).
- При старте приложения создаются portable-каталоги `data/`, `data/cache/previews/`, `data/assets/`.
- Обновляет `CHANGELOG.md`.

## Затрагиваемые файлы

- `src/MiniCodex.sln` — новый.
- `src/MiniCodex.Core/MiniCodex.Core.csproj` — новый.
- `src/MiniCodex.Data/MiniCodex.Data.csproj` — новый.
- `src/MiniCodex.Render/MiniCodex.Render.csproj` — новый.
- `src/MiniCodex.Tests/MiniCodex.Tests.csproj` — новый.
- `src/MiniCodex.App/MiniCodex.App.csproj` — заменён.
- `src/MiniCodex.App/Program.cs`, `App.axaml`, `App.axaml.cs` — новые.
- `src/MiniCodex.App/Views/MainWindow.axaml`, `MainWindow.axaml.cs` — новые.
- `src/MiniCodex.App/ViewModels/MainWindowViewModel.cs` — новый.
- `src/MiniCodex.App/Services/AppPaths.cs`, `LocalizationService.cs`, `ThemeService.cs` — новые.
- `CHANGELOG.md` — обновлён.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.1.0\patch_0.1.0.ps1"

## DoD

- `dotnet build src/MiniCodex.sln` — успешно.
- Приложение запускается, переключает тему (light/dark/auto) и язык (RU/EN).
- При первом запуске создаются `data/library.db` (пустой файл), `data/cache/previews/`, `data/assets/`.

## Откат

Скопировать файлы из `backups\0.1.0_{timestamp}\` обратно в `D:\AI\MiniCodex\`.
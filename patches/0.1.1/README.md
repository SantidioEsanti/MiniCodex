# Патч 0.1.1 — SQLite-схема, репозитории, миграции

**Итерация:** 0.1 (Фундамент) · **Статус:** реализован

## Что делает

- Создаёт Entity-классы (`Model`, `ModelFile`, `Asset`, `Tag`, `Collection`) в Core.
- Создаёт интерфейсы репозиториев в Core.
- Реализует `SqliteConnectionFactory`, `MigrationRunner`, `DatabaseInitializer`, `Migration_0001_InitialSchema`.
- Реализует 6 репозиториев (Setting, Model, ModelFile, Asset, Tag, Collection).
- Правка `App.axaml.cs`: вызов `DatabaseInitializer.InitializeAsync(App.Paths.LibraryDb)` перед показом MainWindow.
- Юнит-тесты: инициализация БД, идемпотентность, CRUD по каждому репозиторию.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.1.1\patch_0.1.1.ps1"

## DoD

- `dotnet build src/MiniCodex.sln` — успешно.
- `dotnet test src/MiniCodex.sln` — все тесты зелёные (≈8 тестов).
- При первом запуске приложения `data/library.db` создаётся с 7 таблицами + `Db.SchemaVersion = 1`.
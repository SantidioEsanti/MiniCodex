# Патч 0.2.1 — Фоновое сканирование

**Итерация:** 0.2 · **Статус:** реализован

## Что делает

- **Исправление ADR:** перенос `MeshInfo` и `IMeshLoader` в `MiniCodex.Core` (Core больше не зависит от Render).
- Миграция 2: колонка `last_write_time_utc` в `ModelFile`.
- `IModelFileRepository.GetByPathAsync` — поиск существующего файла.
- `ScannerService`: рекурсивный поиск по папкам, инкрементальность (пропуск неизменённых), обновление при изменении, обработка недоступных папок, отмена через `CancellationToken`, прогресс `ScanProgress`.
- Тесты: 5 (добавление, инкрементальность, обновление, отсутствующая папка, игнорирование неподдерживаемых).

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.1\patch_0.2.1.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 17 тестов (12 старых + 5 новых), все зелёные.
# Патч 0.2.1b — устойчивые к миграциям тесты

**Итерация:** 0.2 · **Статус:** реализован

## Причина

После добавления миграции №2 в патче 0.2.1 (`ModelFile.last_write_time_utc`) тесты `DatabaseInitializerTests` (написаны в 0.1.1) хардкодили `Db.SchemaVersion = "1"` и падали с `Expected: 1, Actual: 2`.

## Что делает

- Экспортирует `DatabaseInitializer.Migrations` (публичный список) и `LatestSchemaVersion`.
- Тесты используют `DatabaseInitializer.LatestSchemaVersion.ToString()` вместо хардкода `"1"` — при любой новой миграции в будущем тесты останутся зелёными.
- Добавляет тест `ModelFile_HasLastWriteTimeColumn` — проверка, что миграция 2 применилась (PRAGMA table_info).

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.1b\patch_0.2.1b.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 18 тестов (17 + 1 новый), все зелёные.
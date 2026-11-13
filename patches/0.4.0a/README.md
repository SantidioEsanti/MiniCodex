# Патч 0.4.0a — фикс сборки App

**Итерация:** 0.4 · **Статус:** реализован

## Причины

1. **CS1061 (`IntegrationApp.Loc`)** — `IntegrationAppRowViewModel` имеет свойство
   `public IntegrationApp App { get; }`, которое shadow'ит класс `MiniCodex.App.App`.
   Вызов `App.Loc?.Get(...)` компилятор трактует как «Loc на IntegrationApp».
2. **CA1416 (8 предупреждений)** — `Microsoft.Win32.Registry` — Windows-only.
   Приложение по контракту Windows-only (HANDOFF), анализатор требует
   `[SupportedOSPlatform("windows")]`.

## Что делает

- `IntegrationAppRowViewModel`: добавлен хелпер `Loc(key, fallback)` через
  `MiniCodex.App.App.Loc` (полная квалификация). Логика не меняется.
- `WindowsRegistryProbe`: `[SupportedOSPlatform("windows")]` на классе +
  `using System.Runtime.Versioning;`. Анализатор доволен, поведение то же.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.4.0a\patch_0.4.0a.ps1"

## DoD

- `dotnet build` — 0 ошибок, 0 предупреждений.
- `dotnet test` — 40/40.
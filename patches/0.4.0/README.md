# Патч 0.4.0 — Интеграции со слайсерами/редакторами + автодетект

**Итерация:** 0.4 · **Статус:** реализован

## Что делает

- `IntegrationCatalog` (Core) — 10 приложений: 6 слайсеров + 4 редактора.
- `IIntegrationProbe` (Core) + `WindowsRegistryProbe` (App) — стандартные пути + Uninstall-ключи.
- `IIntegrationService` + `IntegrationService` (Core) — Get/Set/Launch, override в `Setting`.
- Экран «Настройки» (`SettingsViewModel` + `SettingsView`): списки слайсеров/редакторов, статусы (Auto/Manual/Not found), Browse/Clear, Re-detect.
- Навигация `Library | Settings` в верхней панели.
- Карточка модели: второй ряд с dropdown + кнопки Open in slicer/editor. Скрыт, если интеграций нет.
- Локализация: полная перезапись `lang/en.json` + `lang/ru.json` (200+ строк, с новыми ключами Settings.Integrations.* и Card.Launch.*).
- `Microsoft.Win32.Registry 5.0.0` в App.csproj.
- 4 новых теста (fake probe).

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.4.0\patch_0.4.0.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 40/40 (36 + 4 новых).
- Settings: секция «Интеграции», список 10 приложений. Если Bambu установлен — статус Auto, путь заполнен. «Re-detect» перепроверяет.
- Browse: file picker → override, статус Manual.
- Clear: override снят → снова Auto (если установлен).
- Карточка: второй ряд с dropdown выбранного слайсера/редактора, кнопки запускают процесс с primary-файлом.
- Смена языка → все строки переключаются.
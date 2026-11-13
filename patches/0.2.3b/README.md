# Патч 0.2.3b — разворот моделей, тема карточек, локализация UI библиотеки

**Итерация:** 0.2 · **Статус:** реализован

## Причины

1. **Модели показывались сзади.** После Z-up→Y-up 3D-печатная модель (перед в −Y)
   проецировалась «затылком». Решение — сдвинуть набор ракурсов на 180°.
2. **Рамка карточек не менялась при смене темы.** В `LibraryView.axaml` были
   захардкожены `Background`, `BorderBrush`, `Foreground`. Заменено на
   `{DynamicResource SystemControl*Brush}` из Fluent-темы Avalonia.
3. **Язык не менял текст.** Строки «Сканировать папку», «Загрузка библиотеки…»,
   «Моделей: N», «Сканирование…» были захардкожены по-русски. Добавлены ключи
   `Library.ScanButton`, `Library.Loading`, `Library.ModelsCount`,
   `Library.Scanning`, `Library.ScanningProgress`, `Library.ServicesNotInitialized`,
   `Library.ScanFolderTitle` в `lang/en.json` и `lang/ru.json`.

## Что делает

- `PreviewGeneratorOptions.YawDegrees = {180, 270, 0, 90}` — карточка показывает лицо.
- `PreviewGenerator.RendererVersion = "0.2.3b"` — кэш превью инвалидируется, все
  PNG перегенерируются при первом показе.
- `LibraryView.axaml` — DynamicResource для фона, рамки и текста; биндинги на
  `ScanButtonText` и `EmptyStateText`.
- `LibraryViewModel` — computed-свойства из `App.Loc`, `RefreshLocalized()`,
  переделанный `StatusText` через `StatusState`.
- `MainWindowViewModel.CurrentLanguage.set` — вызывает `Library.RefreshLocalized()`
  после `App.Loc.SetLanguage`.
- `lang/en.json`, `lang/ru.json` — расширены ключами `Library.*`.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.3b\patch_0.2.3b.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24 теста, 0 сбоев.
- При первом показе карточек превью перерисовываются: модель лицом к камере.
- Переключение темы `auto`→`dark`→`light` меняет фон и рамку карточек.
- Переключение языка `ru`→`en` меняет кнопку «Сканировать папку» / «Scan folder»,
  статус «Моделей: 172» / «Models: 172», пустое состояние.
# Патч 0.2.3 — Экран «Библиотека»: сетка карточек с превью

**Итерация:** 0.2 · **Статус:** реализован

## Что делает

- `AppServices` — composition root (SQLite factory, репозитории, Scanner, PreviewGenerator).
- `LibraryViewModel` — загрузка моделей, команда сканирования папок, коллекция карточек.
- `ModelCardViewModel` — модель + превью + метаданные, превью генерируется в фоне (`Task.Run`), UI не блокируется.
- `LibraryView.axaml` — сетка карточек (`WrapPanel` + `ScrollViewer`), кнопка «Сканировать папку», пустое состояние.
- `LibraryView.axaml.cs` — Avalonia `IStorageProvider.OpenFolderPickerAsync` для выбора папок.
- `MainWindow.axaml` — заменяет приветствие на `LibraryView`, ComboBox языка/темы остаются сверху.
- `MainWindowViewModel` — свойство `Library`, DI-инициализация.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.3\patch_0.2.3.ps1"

## DoD

- Приложение запускается, показывает пустое состояние.
- Кнопка «Сканировать папку» → FolderPicker → карточки с превью.
- UI не блокируется во время сканирования.
- Hover-панель и виртуализация — **в 0.2.3a / 0.2.3b** (не входят в этот патч).
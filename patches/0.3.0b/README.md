# Патч 0.3.0b — фикс инверсии вращения + локализация карточки

**Итерация:** 0.3 · **Статус:** реализован

## Причины

1. **Горизонтальное вращение мышью инвертировано.** `_yaw -= dx` — при движении мыши
   вправо модель поворачивалась влево. По вертикали было `_pitch += dy` (правильно).
2. **Карточка модели не локализовалась.** Все строки («← Назад», «Сохранить»,
   заголовки вкладок, метки полей, «Сохранено», «Загрузка 3D…», «Файл модели не выбран»)
   были захардкожены по-русски.

## Что делает

- `ThreeDViewer.OnPointerMoved`: `_yaw += dx * 0.5f` (симметрично с pitch).
- `ThreeDViewer` больше не пишет в `StatusLabel` напрямую — через `DataContext`
  выставляет `ThreeDViewState` на `ModelCardPageViewModel`; текст — binding на `ThreeDStatusText`.
- `ModelCardPageViewModel`: `ThreeDViewState`, `ThreeDErrorMessage`, `SaveState`,
  `SaveErrorMessage` + computed `ThreeDStatusText`, `ThreeDStatusVisible`,
  `SaveStatusText`, `BackButtonText`, `SaveButtonText`, `Tab*Header`, `Label*`,
  `AssociationsPlaceholder`, `TagsPlaceholder`, `RefreshLocalized()`.
- `MainWindowViewModel.CurrentLanguage.set`: дополнительно вызывает
  `(CurrentPage as ModelCardPageViewModel)?.RefreshLocalized()`.
- `ModelCardView.axaml`: все строки → `{Binding ...}`.
- `lang/en.json` + `lang/ru.json`: новые ключи `Card.Actions.Back`, `Card.Actions.Save`,
  `Card.Status.Saved`, `Card.Status.ErrorPrefix`, `Card.Placeholder.*`, `Card.ThreeD.*`.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.0b\patch_0.3.0b.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24/24.
- Горизонтальный drag вращает модель в сторону движения мыши.
- Переключение языка `ru`→`en` мгновенно меняет все надписи на карточке: «← Back»,
  «Save», «Info/Files/Associations/Tags/Notes», «Title/Author/Source URL/...»
- Если 3D в состоянии «Файл не выбран» — текст тоже переключается.
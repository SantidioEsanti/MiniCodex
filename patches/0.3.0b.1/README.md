# Патч 0.3.0b.1 — фикс XAML карточки модели

**Итерация:** 0.3 · **Статус:** реализован

## Причина

В 0.3.0b `xmlns:vm` был объявлен внутри `<RadioButton>` в `ModelCardView.axaml`.
Компилятор Avalonia требует, чтобы все `xmlns`-декларации были только на корневом
элементе (`AXN0002`). Вторичная ошибка — `InitializeComponent не существует` —
следствие: XAML не скомпилировался, поэтому generated-класс `ModelCardView.g.cs` не создался.

## Что делает

- `xmlns:vm` перенесён на корневой `<UserControl>`.
- Добавлен `x:DataType="vm:ModelCardPageViewModel"` — для compiled bindings.
- `$parent[UserControl]` заменён на `$parent[ListBox]` в Command-binding
  (надёжнее и явнее — RadioButton находится внутри ListBox.ItemTemplate).
- Логика не менялась.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.0b.1\patch_0.3.0b.1.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24/24.
- UI карточки работает как в 0.3.0b: drag вправо = модель вправо, язык переключается.
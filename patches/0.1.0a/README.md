# Патч 0.1.0a — Добавление иконки приложения

**Итерация:** 0.1 (Фундамент)
**Статус:** реализован

## Что делает

- Добавляет `<ApplicationIcon>Assets\icon.ico</ApplicationIcon>` в `MiniCodex.App.csproj`.
- Добавляет `<AvaloniaResource Include="Assets\**" />` в `MiniCodex.App.csproj`, чтобы файлы иконок попадали в сборку.
- Добавляет атрибут `Icon="/Assets/icon.ico"` в тег `<Window>` в `MainWindow.axaml`.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.1.0a\patch_0.1.0a.ps1"

## Откат

Скопировать файлы из `backups\0.1.0a_{timestamp}\` обратно в `D:\AI\MiniCodex\`.
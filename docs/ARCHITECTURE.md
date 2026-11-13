\# ARCHITECTURE — MiniCodex



\*\*Версия:\*\* 1.0 · \*\*Дата:\*\* 2026-11-09



\## 1. Обзор



MiniCodex — portable-десктоп на .NET 8 + Avalonia UI. Разделение на слои:



\- \*\*MiniCodex.App\*\* — Avalonia UI, ViewModels, Views, DI-контейнер.

\- \*\*MiniCodex.Core\*\* — бизнес-логика, сервисы (ScannerService, PreviewGenerator-интерфейс, IntegrationService, AppPaths, локализация).

\- \*\*MiniCodex.Data\*\* — SQLite (Microsoft.Data.Sqlite), репозитории, миграции.

\- \*\*MiniCodex.Render\*\* — парсинг мешей (Assimp.NET + собственные парсеры STL/3MF), 3D-рендер (HelixToolkit), генерация превью.

\- \*\*MiniCodex.Tests\*\* — юнит-тесты.



Зависимости: App → Core, Data, Render; Data → Core; Render → Core; Core — без зависимостей от UI/Data/Render.



\## 2. Portable-структура



Корень приложения (рядом с EXE) → `./data/`:



\- `library.db` — SQLite

\- `cache/previews/{model\_id}/{angle}.png` — кэш превью

\- `assets/{model\_id}/` — Hybrid-хранение ассоциаций



`AppPaths` в Core создаёт каталоги при старте.



\## 3. Локализация



JSON-словари в `lang/en.json`, `lang/ru.json`. Ключи — `PascalCase.Category.Subkey`.

Загрузка при старте, автовыбор по `CultureInfo.CurrentUICulture`, fallback → EN. Все строки UI — в JSON с первого коммита.



\## 4. Темы



Avalonia `ThemeVariant` (light/dark/auto). Выбор сохраняется в `Setting`.



\## 5. Патчи



Все изменения после базовой структуры — патч-скриптами по `patches/README.md`. Прямое редактирование `src/` запрещено.



\## 6. Открытые ADR



\- Формат кэша превью: PNG (MVP), WebP — кандидат на v1.1.

\- Удаление модели из библиотеки: файлы на диске не трогаем до релиза MVP.

\- Hybrid-корень по умолчанию: `./data/assets/` без диалога.


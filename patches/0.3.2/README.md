# Патч 0.3.2 — Теги + Поиск

**Итерация:** 0.3 · **Статус:** реализован

## Что делает

### Теги
- `IModelTagRepository` + `ModelTagRepository` — CRUD связи Model↔Tag.
- `ITagRepository.GetAllWithUsageAsync` — теги с usage-count (LEFT JOIN).
- `ITagService` + `TagService`:
  - `CreateOrGetAsync(name)` — идемпотентно (case-insensitive)
  - `AddToModelAsync(modelId, name)` — создаёт тег при необходимости + привязка
  - `RemoveFromModelAsync(modelId, tagId)` — отвязка
- Карточка модели, вкладка «Теги»: TextBox + кнопка «Добавить» + чипы с `×`.

### Поиск
- `IModelRepository.SearchAsync(query, tagId)`:
  - по `title` / `author` / `source_url` (LIKE)
  - по имени тега (EXISTS-подзапрос)
  - фильтр по `tagId`
- Библиотека: SearchBox сверху (debounce 200 мс), сайдбар с тегами + счётчик.
- `Ctrl+F` — фокус на SearchBox.

### Локализация
- `Library.SearchPlaceholder`, `Library.TagsHeader`, `Library.AllModels`
- `Card.Tags.Placeholder`, `Card.Tags.Add`, `Card.Tags.Empty`

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.2\patch_0.3.2.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 36 тестов (28 + 8 новых), все зелёные.
- В карточке: добавили тег «Fantasy» → чип, в БД `Tag`+`ModelTag`. Удаление — запись уходит.
- В библиотеке: поиск «fant» → находит модель по тегу. Клик на тег в сайдбаре → фильтр.
- `Ctrl+F` фокусирует SearchBox.
- Пустой `SearchQuery` + «Все модели» → весь список.
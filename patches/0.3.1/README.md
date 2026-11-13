# Патч 0.3.1 — Ассоциации (drag-and-drop, авто-привязка, Hybrid)

**Итерация:** 0.3 · **Статус:** реализован

## Что делает

- `IAssetService` / `AssetService` (Core):
  - `ImportAsync` — копирование файла в `data/assets/{modelId}/{8hex}_{origName}{ext}` + запись Asset
  - `RemoveFromCardAsync` — удаление записи из БД; **файл на диске остаётся** (MVP)
  - `AutoLinkAsync` — поиск рядом с primary `{basename}_*.{png,jpg,jpeg,webp,pdf}`, импорт как reference
  - `EnsureThumbnailAsync` — миниатюра в `data/cache/asset-thumbs/{assetId}.png`
- `IAssetThumbnailGenerator` (Core) + `SkiaThumbnailGenerator` (Render): ресайз изображений / заглушка с буквой типа.
- UI карточки, вкладка «Ассоциации»:
  - Drop-зона (drag-and-drop файлов), file picker «Add file»
  - ComboBox выбора типа (reference/render/photo/document/profile)
  - ComboBox фильтра по типу (all + 5 типов)
  - Галерея 150×150: миниатюра, имя, тип, кнопка «×» (Убрать из карточки)
  - Кнопка «Авто-привязка» — сразу импортирует найденные
- `AppServices.AssetService` — инициализация.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.3.1\patch_0.3.1.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 28 тестов (24 + 4 новых), все зелёные.
- Drag-and-drop PNG/JPG/PDF в карточку → ассоциация с миниатюрой.
- «Добавить файл» → file picker → импорт.
- «Авто-привязка» → находит {basename}_*.png рядом с primary.
- «Убрать» → запись из БД удаляется, **файл в data/assets/{modelId}/ остаётся**.
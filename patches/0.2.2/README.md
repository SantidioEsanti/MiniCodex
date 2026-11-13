# Патч 0.2.2 — Генерация 4 ракурсов превью + кэш PNG

**Итерация:** 0.2 · **Статус:** реализован

## Что делает

- `SkiaPreviewRenderer` — оффскрин-рендер (SkiaSharp) с Z-buffer и flat shading.
- `IMeshGeometryLoader` + `AssimpMeshLoader.LoadGeometry` — полная геометрия (вершины + индексы) из STL/OBJ/3MF/PLY.
- `PreviewGenerator` — 4 ракурса (0°/90°/180°/270°) + наклон 15°.
- Кэш: `{cacheDir}/{modelId}/{angle}.png` + `metadata.json`.
- Инвалидация по `source_updated_at`: если источник новее — перегенерация.
- Тесты: 2 × рендерер + 4 × generator = 6 новых.

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.2\patch_0.2.2.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 24 теста (18 старых + 6 новых), все зелёные.
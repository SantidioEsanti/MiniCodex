# Патч 0.2.0 — Парсеры STL/OBJ/3MF, метаданные

**Итерация:** 0.2 (Сканирование и превью) · **Статус:** реализован

## Что делает

- Добавляет пакет `AssimpNet 4.1.0` в `MiniCodex.Render`.
- Создаёт `MeshInfo` (полигоны, размер файла, bounding box, SizeX/Y/Z).
- Создаёт `IMeshLoader` (интерфейс) и `AssimpMeshLoader` (реализация, поддержка stl/obj/3mf/ply).
- `AssimpMeshLoader.Load()` при битом/отсутствующем файле возвращает `null` — по ROADMAP 3.1 («битый файл → запись в лог, модель не теряется»).
- Тесты: ASCII STL, OBJ, отсутствующий файл, битый файл (4 теста).

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.0\patch_0.2.0.ps1"

## DoD

- `dotnet build src/MiniCodex.sln` — успешно.
- `dotnet test src/MiniCodex.sln` — 12 тестов (8 старых + 4 новых), все зелёные.
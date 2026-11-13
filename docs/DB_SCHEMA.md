\# DB\_SCHEMA — MiniCodex



\*\*Версия:\*\* 1.0 · \*\*Дата:\*\* 2026-11-09



Схема SQLite (`./data/library.db`). Источник — раздел 6 HANDOFF.



\## Таблицы



\- `Model` — логическая карточка (id UUID, title, author, source\_url, model\_type, primary\_model\_file\_id, status, difficulty 1–5, real\_height\_mm, model\_height\_mm, scale\_ratio, notes, created\_at, updated\_at).

\- `ModelFile` — файл модели (id, model\_id, path, file\_role, part\_name, file\_size\_bytes, polygon\_count).

\- `Asset` — ассоциированный файл (id, model\_id, asset\_type, absolute\_path, thumbnail\_path, sort\_order, storage\_mode).

\- `Tag` — тег (id, name, parent\_id, color).

\- `ModelTag` — связь Model ↔ Tag.

\- `Collection` — умные коллекции (id, name, filter\_query JSON, is\_smart).

\- `Setting` — key-value настройки (в т.ч. `Db.SchemaVersion`).



\## Перечисления (строковые)



\- `Model.status`: planned | printed | painted

\- `Model.model\_type`: single | split | multipart | diorama | variant\_set

\- `ModelFile.file\_role`: main | part | presupported | hollowed | variant | accessory

\- `Asset.asset\_type`: reference | render | photo | document | profile

\- `Asset.storage\_mode`: hybrid | adjacent | central | restructure



\## Миграции



Применяются при старте. Текущая версия — в `Setting` (key `Db.SchemaVersion`). Идемпотентность обязательна.



\## Планируемые расширения



\- `Model.orientation\_json` — ориентация модели (патч 0.4.2).

\- Индексы по `Model.title`, `Tag.name`, `ModelFile.path` — по мере необходимости.


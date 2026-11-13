\# Регламент патчей MiniCodex



После создания базовой структуры \*\*все изменения в `src/` — только патч-скриптами PowerShell\*\*.

Прямое редактирование файлов в `src/` запрещено.



\## Расположение



`D:\\AI\\MiniCodex\\patches\\{MAJOR}.{MINOR}.{PATCH}\\patch\_{MAJOR}.{MINOR}.{PATCH}.ps1`



Рядом — `README.md` с описанием: что меняет, зачем, какие файлы затрагивает.



\## Обязанности патч-скрипта



1\. Создать бэкап затронутых файлов в `D:\\AI\\MiniCodex\\backups\\{version}\_{YYYYMMDD\_HHMMSS}\\`.

2\. Быть идемпотентным (повторный запуск не ломает состояние).

3\. Логировать действия в консоль и в `D:\\AI\\MiniCodex\\patches\\{version}\\patch.log`.

4\. При ошибке — сообщить, указать путь к бэкапу и команду восстановления. Автоматический откат не делать.

5\. В конце — обновить `CHANGELOG.md`.



\## Запуск



Всегда полный путь, всегда `-ExecutionPolicy Bypass`:



```powershell

powershell -ExecutionPolicy Bypass -File "D:\\AI\\MiniCodex\\patches\\0.1.0\\patch\_0.1.0.ps1"


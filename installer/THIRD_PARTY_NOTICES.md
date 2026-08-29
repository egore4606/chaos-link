# Сторонние компоненты установщика

Офлайн-установщик Chaos Link включает неизменённые официальные бинарные файлы:

- AutoHotkey v2.0.26 — GNU General Public License v2.0, исходный код и лицензия:
  https://github.com/AutoHotkey/AutoHotkey/tree/v2.0.26
- cloudflared 2026.5.2 — Apache License 2.0, исходный код и лицензия:
  https://github.com/cloudflare/cloudflared/tree/2026.5.2

Версии и SHA-256 включённых файлов записаны в `BUILD-MANIFEST.json`. Сценарий сборки
скачивает их только из официальных GitHub Releases и прерывает сборку при несовпадении
контрольной суммы. Во время установки сетевые загрузки не выполняются.

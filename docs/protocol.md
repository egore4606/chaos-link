# Протокол WebSocket

Клиенты подключаются по адресам:

```text
/ws?room=K7M2&role=controller&name=Egor
/ws?room=K7M2&role=agent&name=Gaming-PC
```

Первое сообщение должно прийти в течение пяти секунд. Оно авторизует соединение,
не добавляя секрет в журналы доступа reverse proxy:

```json
{ "type": "auth", "token": "friend-access" }
```

Сообщения контроллера:

```json
{ "type": "trigger", "effectId": "reload" }
{ "type": "ping", "clientTime": 1785935600000 }
```

Сообщения администратора:

```json
{ "type": "pause", "paused": true }
{ "type": "blockUser", "targetClientId": "...", "blockSeconds": 30 }
{ "type": "blockUser", "targetClientId": "...", "blockSeconds": -1 }
{ "type": "blockUser", "targetClientId": "...", "blockSeconds": 0 }
{ "type": "setCooldown", "effectId": "reload", "cooldownSeconds": 15 }
```

Сообщения агента:

```json
{ "type": "ack", "eventId": "...", "status": "executed", "detail": null }
{ "type": "ping", "clientTime": 1785935600000 }
```

Каждый принятый запуск получает уникальный `eventId`, серверное значение
`nextAvailableAt` и значение `executeAt`. Изменение комнаты защищено блокировкой,
поэтому два одновременных запроса контроллеров не могут оба запустить один эффект.
`blockSeconds` равен `30` для временной блокировки, `-1` для блокировки до ручного
снятия и `0` для разблокировки. Кулдаун может принимать значения от 0 до 3600 секунд.

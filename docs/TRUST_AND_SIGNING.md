# Доверие к сборкам и цифровая подпись

## Что уже делает проект

- готовые файлы публикуются только через GitHub Releases по HTTPS;
- сборка формирует `SHA256SUMS.txt` для установщика и деинсталлятора;
- исходный код установщика открыт в `installer/` и `scripts/`;
- релизный GitHub Actions workflow создаёт подписанную GitHub provenance-attestation для EXE;
- установщик показывает каталог назначения и все выполняемые действия;
- автозапуск, скрытая служба и отключение средств защиты не используются.

Проверка загруженного файла:

```powershell
Get-FileHash .\ChaosLink-Setup.exe -Algorithm SHA256
```

Полученное значение должно полностью совпадать со строкой `ChaosLink-Setup.exe` в `SHA256SUMS.txt` того же релиза.

Происхождение EXE из GitHub Actions можно дополнительно проверить:

```powershell
gh attestation verify .\ChaosLink-Setup.exe -R egore4606/chaos-link
```

## Почему Windows или Chrome всё ещё могут предупреждать

Microsoft Defender SmartScreen использует репутацию конкретного файла и издателя. Неподписанный новый файл начинает без репутации при каждом обновлении; самоподписанный сертификат не создаёт доверенного издателя. Chrome Safe Browsing также может предупреждать о новом или редко загружаемом EXE.

Это нельзя безопасно исправить переименованием файла, упаковкой в архив или просьбой отключить защиту. Такие обходы ухудшают доверие и могут сами выглядеть подозрительно.

## Что требуется для релизов без «неизвестного издателя»

1. Пройти проверку личности/организации у доверенного поставщика подписи.
2. Получить постоянный OV‑сертификат либо настроить Microsoft Artifact Signing.
3. Подписывать одним издателем `ChaosLink-Setup.exe` и `ChaosLink-Uninstall.exe` с SHA-256 и доверенной отметкой времени.
4. Проверять подпись до загрузки файлов в GitHub Release.
5. Сохранять одного издателя между версиями, чтобы его репутация могла накапливаться.

После установки сертификата в хранилище Windows локальная сборка подписывается так:

```powershell
$env:CHAOS_LINK_SIGNING_THUMBPRINT = '40-ЗНАКОВ-THUMBPRINT-БЕЗ-ПРОБЕЛОВ'
.\scripts\build-portable-installer.ps1
```

Сборка вызывает `scripts/sign-release.ps1`, проверяет обе подписи через SignTool и только затем создаёт `SHA256SUMS.txt`. Закрытый ключ и пароль сертификата не сохраняются в репозитории.

Даже новый корректно подписанный файл иногда получает первоначальное предупреждение до накопления репутации. Microsoft Store — единственный описанный Microsoft путь, который полностью исключает предупреждение SmartScreen при загрузке приложения из Store.

Официальные материалы:

- [Microsoft: SmartScreen reputation for Windows app developers](https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation)
- [Microsoft Artifact Signing](https://learn.microsoft.com/azure/artifact-signing/)
- [Google Chrome: blocked downloads](https://support.google.com/chrome/answer/6261569)

# AirPlay 2 для Станции Лайт

Готовый пакет и исходники решения, проверенного на **Станции Лайт (`station-micro`)**
26 октября 2026: приём музыки, физические кнопки громкости/паузы, вспышка кольца,
короткий сигнал и возврат Алисы после воспроизведения.

Полная инструкция: [AirPlay 2 на Лайт](../../docs/recipes/airplay-lite.md).

```sh
# Проверка устройства, без изменения файлов:
./contrib/airplay-lite/install.sh --check 192.168.1.50:5555

# Новая установка; имя mDNS нужно заменить на настоящее имя своей колонки:
./contrib/airplay-lite/install.sh 192.168.1.50:5555 yandexmicro-EXAMPLE123
```

| Файл | Назначение |
|---|---|
| `../packages/airplay-lite-5.6.2.tar.gz` и `.sha256` | Готовые ARM64-бинарники, библиотеки и конфигурация |
| `install.sh` | Установка с компьютера по явно выбранному ADB-соединению |
| `preflight.sh`, `install-device.sh` | Проверки совместимости и применение на устройстве |
| `device/` | Все скрипты и конфиги, исходник `airplay-buttons.c` |
| `S99zairplay` | Автозапуск с ожиданием `/data` и звуковой карты |
| `build.sh`, `extract-runtime.sh` | Сборка из официального образа Shairport и исходника кнопок |
| `bundle.py` | Создание архива, проверка SHA256, безопасная распаковка и настройка mDNS |

В переносимом архиве вместо серийного номера используется `@MDNS_HOST@`.
Установщик подставляет имя и пересчитывает файловый манифест.
Старый `yandex-station-airplay-fix.sh` этому пакету не нужен: `airplayd` не используется.

Сборка пакета с Docker и Python 3.9+:

```sh
./contrib/airplay-lite/build.sh
```

Для проверки исходников без изменения колонки:

```sh
python3 -m unittest discover -s contrib/airplay-lite/tests -v
bash -n contrib/airplay-lite/install.sh contrib/airplay-lite/build.sh
```

AirPlay 2 для Яндекс Станции Лайт (station-micro, CY8CMBR3108).
Проверено на устройстве с ядром 4.9.68, Buildroot 2020.02.1, 26 октября 2026.

Shairport Sync 5.6.2 и NQPTP 1.2.9 (smi11), ARM64/musl.
Источник и digest официального образа: VERSION.
Исходники Shairport: https://github.com/mikebrady/shairport-sync/tree/5.6.2
Исходники NQPTP: https://github.com/mikebrady/nqptp
Описание сборки: https://github.com/mikebrady/shairport-sync/tree/5.6.2/docker

Управление: /data/shairport/airplay.sh start|stop|restart|status
Автозапуск: /etc/init.d/S99zairplay
Логи и PID: /tmp/shairport/ (оперативная память).
Настройки приёмника: ap2/shairport.conf
Настройки звука: etc/asound.conf

Во время воспроизведения AirPlay Алиса останавливается. После завершения
активного состояния (таймер 2 с) запускается снова. Запуск самой Алисы
занимает дополнительное время. Monitor восстанавливает её при сбое служб.

Обработчик event1 управляет кнопками, пока источник остаётся подключённым:
громкость — ALSA Master, пауза/продолжение — MPRIS PlayPause источнику.
На нажатие: вспышка кольца 140 мс и тихий тон 70 мс. Тон смешивается с AirPlay
через отдельный 64-битный dmix, а во время работы Алисы — через штатный aplay.
Физический переключатель микрофона event0 не перехватывается.
Исходник обработчика: airplay-buttons.c.

Это самостоятельный пакет. Он не содержит airplayd, и старый скрипт
yandex-station-airplay-fix.sh к нему применять не нужно.

Установщик создаёт служебные пользователя/группу avahi, если их ещё нет,
и сохраняет прежние passwd/group в backup/. Системные ALSA-конфиги и
штатные скрипты запуска Quasar не изменяются.
Проверка файлов: cd /data/shairport && sha256sum -c MANIFEST.sha256

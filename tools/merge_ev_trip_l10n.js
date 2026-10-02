// ⚡ EV сафар ёрдамчиси — уч тилдаги матнлар (uz_Cyrl / uz_Latn / ru).
// Ишлатиш: node tools/merge_ev_trip_l10n.js
const fs = require('fs');
const path = require('path');

const keys = {
  uz_Cyrl: {
    ev_trip_entry: 'Қаерга борамиз?',
    ev_trip_title: 'Сафар ёрдамчиси',
    ev_trip_where: 'Қаерга борамиз?',
    ev_trip_search_hint: 'Шаҳарни қидиринг...',
    ev_trip_not_found: 'Топилмади — бошқа ном билан қидиринг',
    ev_trip_change: 'Ўзгартириш',
    ev_trip_charge_now: 'Ҳозирги заряд',
    ev_trip_calculate: 'Ҳисоблаш',
    ev_trip_km: 'км',

    ev_trip_car_title: 'Электромобил маълумоти',
    ev_trip_car_subtitle:
      'Бир марта киритилади — кейин ҳар сафарда қайта сўралмайди.',
    ev_trip_car_model: 'Модел (ихтиёрий)',
    ev_trip_car_missing: 'Автомобил маълумоти тўлдирилмаган',
    ev_trip_car_missing_body:
      'Батарея сиғими ва сарфи бўлмаса режа ҳисобланмайди.',
    ev_trip_car_fill: 'Тўлдириш',
    ev_trip_car_invalid: 'Батарея сиғими ва сарфини киритинг.',
    ev_trip_car_save_failed: 'Сақланмади — яна уриниб кўринг.',
    ev_trip_battery: 'Батарея сиғими (kWh)',
    ev_trip_battery_hint: 'Фойдаланиладиган сиғим — паспортдагидан бир оз кам.',
    ev_trip_consumption: 'Сарф (kWh/100 км)',
    ev_trip_consumption_hint: 'Реал сарф — тезлик ва иситишга қараб ўзгаради.',
    ev_trip_connectors: 'Разъёмлар',

    ev_trip_no_charging: 'Зарядлашга ҳожат йўқ',
    ev_trip_charge_stops: 'марта зарядлаш керак',
    ev_trip_total_distance: 'Жами масофа',
    ev_trip_arrival: 'Етиб келганда',
    ev_trip_station: 'Зарядлаш нуқтаси',
    ev_trip_off_route: 'йўлдан',
    ev_trip_backup: 'Заҳира вариант',
    ev_trip_unverified: 'Текширилмаган',
    ev_trip_open_navigator: 'Навигаторда очиш',
    ev_trip_legend_primary: 'Асосий тўхташ',
    ev_trip_legend_backup: 'Заҳира',
    ev_trip_legend_other: 'Йўл бўйидаги бошқа станциялар',

    ev_trip_gap_title: 'Бу маршрут ҳозирги база билан хавфли',
    ev_trip_gap_body:
      'Станциялар орасидаги масофа машинанинг имкониятидан катта. Режа ўйлаб топилмади.',
    ev_trip_gap_next: 'кейинги нуқта',
    ev_trip_gap_none: 'олдинда станция йўқ',

    ev_trip_error_route: 'Маршрут олинмади — интернетни текширинг.',
    ev_trip_error_geometry: 'Бу манзилга йўл топилмади.',
    ev_trip_location_missing: 'GPS аниқланмади — жойлашувни ёқинг.',

    ev_trip_warn_unverified_stops:
      'Режадаги айрим нуқталар очиқ манбадан олинган ва жойида текширилмаган.',
    ev_trip_warn_no_backup:
      'Айрим тўхташларда заҳира вариант йўқ — эҳтиёт бўлинг.',
    ev_trip_warn_start_soc_below_reserve:
      'Ҳозирги заряд заҳира даражасидан паст.',
    ev_trip_warn_connector_unknown:
      'Машинанинг разъёми кўрсатилмаган — станциялар разъём бўйича филтрланмади.',
    ev_trip_warn_slow_ac_only:
      'Режада секин AC станция бор — зарядлаш узоқ давом этади.',
  },

  uz_Latn: {
    ev_trip_entry: 'Qayerga boramiz?',
    ev_trip_title: 'Safar yordamchisi',
    ev_trip_where: 'Qayerga boramiz?',
    ev_trip_search_hint: 'Shaharni qidiring...',
    ev_trip_not_found: 'Topilmadi — boshqa nom bilan qidiring',
    ev_trip_change: 'O\'zgartirish',
    ev_trip_charge_now: 'Hozirgi zaryad',
    ev_trip_calculate: 'Hisoblash',
    ev_trip_km: 'km',

    ev_trip_car_title: 'Elektromobil ma\'lumoti',
    ev_trip_car_subtitle:
      'Bir marta kiritiladi — keyin har safarda qayta so\'ralmaydi.',
    ev_trip_car_model: 'Model (ixtiyoriy)',
    ev_trip_car_missing: 'Avtomobil ma\'lumoti to\'ldirilmagan',
    ev_trip_car_missing_body:
      'Batareya sig\'imi va sarfi bo\'lmasa reja hisoblanmaydi.',
    ev_trip_car_fill: 'To\'ldirish',
    ev_trip_car_invalid: 'Batareya sig\'imi va sarfini kiriting.',
    ev_trip_car_save_failed: 'Saqlanmadi — yana urinib ko\'ring.',
    ev_trip_battery: 'Batareya sig\'imi (kWh)',
    ev_trip_battery_hint:
      'Foydalaniladigan sig\'im — pasportdagidan bir oz kam.',
    ev_trip_consumption: 'Sarf (kWh/100 km)',
    ev_trip_consumption_hint:
      'Real sarf — tezlik va isitishga qarab o\'zgaradi.',
    ev_trip_connectors: 'Raz\'yomlar',

    ev_trip_no_charging: 'Zaryadlashga hojat yo\'q',
    ev_trip_charge_stops: 'marta zaryadlash kerak',
    ev_trip_total_distance: 'Jami masofa',
    ev_trip_arrival: 'Yetib kelganda',
    ev_trip_station: 'Zaryadlash nuqtasi',
    ev_trip_off_route: 'yo\'ldan',
    ev_trip_backup: 'Zaxira variant',
    ev_trip_unverified: 'Tekshirilmagan',
    ev_trip_open_navigator: 'Navigatorda ochish',
    ev_trip_legend_primary: 'Asosiy to\'xtash',
    ev_trip_legend_backup: 'Zaxira',
    ev_trip_legend_other: 'Yo\'l bo\'yidagi boshqa stansiyalar',

    ev_trip_gap_title: 'Bu marshrut hozirgi baza bilan xavfli',
    ev_trip_gap_body:
      'Stansiyalar orasidagi masofa mashinaning imkoniyatidan katta. Reja o\'ylab topilmadi.',
    ev_trip_gap_next: 'keyingi nuqta',
    ev_trip_gap_none: 'oldinda stansiya yo\'q',

    ev_trip_error_route: 'Marshrut olinmadi — internetni tekshiring.',
    ev_trip_error_geometry: 'Bu manzilga yo\'l topilmadi.',
    ev_trip_location_missing: 'GPS aniqlanmadi — joylashuvni yoqing.',

    ev_trip_warn_unverified_stops:
      'Rejadagi ayrim nuqtalar ochiq manbadan olingan va joyida tekshirilmagan.',
    ev_trip_warn_no_backup:
      'Ayrim to\'xtashlarda zaxira variant yo\'q — ehtiyot bo\'ling.',
    ev_trip_warn_start_soc_below_reserve:
      'Hozirgi zaryad zaxira darajasidan past.',
    ev_trip_warn_connector_unknown:
      'Mashinaning raz\'yomi ko\'rsatilmagan — stansiyalar raz\'yom bo\'yicha filtrlanmadi.',
    ev_trip_warn_slow_ac_only:
      'Rejada sekin AC stansiya bor — zaryadlash uzoq davom etadi.',
  },

  ru: {
    ev_trip_entry: 'Куда едем?',
    ev_trip_title: 'Помощник в поездке',
    ev_trip_where: 'Куда едем?',
    ev_trip_search_hint: 'Поиск города...',
    ev_trip_not_found: 'Не найдено — попробуйте другое название',
    ev_trip_change: 'Изменить',
    ev_trip_charge_now: 'Текущий заряд',
    ev_trip_calculate: 'Рассчитать',
    ev_trip_km: 'км',

    ev_trip_car_title: 'Данные электромобиля',
    ev_trip_car_subtitle:
      'Вводится один раз — потом не спрашивается при каждой поездке.',
    ev_trip_car_model: 'Модель (необязательно)',
    ev_trip_car_missing: 'Данные автомобиля не заполнены',
    ev_trip_car_missing_body:
      'Без ёмкости батареи и расхода маршрут не рассчитывается.',
    ev_trip_car_fill: 'Заполнить',
    ev_trip_car_invalid: 'Укажите ёмкость батареи и расход.',
    ev_trip_car_save_failed: 'Не сохранено — попробуйте снова.',
    ev_trip_battery: 'Ёмкость батареи (кВт·ч)',
    ev_trip_battery_hint: 'Полезная ёмкость — чуть меньше паспортной.',
    ev_trip_consumption: 'Расход (кВт·ч/100 км)',
    ev_trip_consumption_hint:
      'Реальный расход — зависит от скорости и отопления.',
    ev_trip_connectors: 'Разъёмы',

    ev_trip_no_charging: 'Заряжаться не нужно',
    ev_trip_charge_stops: 'раз нужно зарядиться',
    ev_trip_total_distance: 'Всего',
    ev_trip_arrival: 'По приезде',
    ev_trip_station: 'Зарядная станция',
    ev_trip_off_route: 'от трассы',
    ev_trip_backup: 'Резервный вариант',
    ev_trip_unverified: 'Не проверено',
    ev_trip_open_navigator: 'Открыть в навигаторе',
    ev_trip_legend_primary: 'Основная остановка',
    ev_trip_legend_backup: 'Резерв',
    ev_trip_legend_other: 'Другие станции по трассе',

    ev_trip_gap_title: 'Этот маршрут рискован с текущей базой',
    ev_trip_gap_body:
      'Расстояние между станциями больше запаса хода. Маршрут не придуман.',
    ev_trip_gap_next: 'следующая точка',
    ev_trip_gap_none: 'впереди станций нет',

    ev_trip_error_route: 'Маршрут не получен — проверьте интернет.',
    ev_trip_error_geometry: 'Дорога до этого города не найдена.',
    ev_trip_location_missing: 'GPS не определён — включите геолокацию.',

    ev_trip_warn_unverified_stops:
      'Часть точек взята из открытых источников и не проверена на месте.',
    ev_trip_warn_no_backup:
      'На некоторых остановках нет резервного варианта — будьте осторожны.',
    ev_trip_warn_start_soc_below_reserve:
      'Текущий заряд ниже резервного уровня.',
    ev_trip_warn_connector_unknown:
      'Разъём автомобиля не указан — станции не фильтровались по разъёму.',
    ev_trip_warn_slow_ac_only:
      'В маршруте есть медленная AC-станция — зарядка займёт много времени.',
  },
};

// ДИҚҚАТ: файллар алифбо бўйича ТАРТИБЛАНМАГАН ва CRLF билан ёзилган.
// Шунинг учун бу скрипт `merge_marshrut_*`дан фарқли — сортламайди ва
// LF ёзмайди: акс ҳолда 2439 калитнинг ҳаммаси ўрин алмашиб, diff
// ўқилмас бўлиб қоларди. Янги калитлар охирига қўшилади.
const serialize = (data) =>
  JSON.stringify(data, null, 2).replace(/\n/g, '\r\n') + '\r\n';

for (const [file, entries] of Object.entries(keys)) {
  const p = path.join(__dirname, '..', 'assets', 'lang', `${file}.json`);
  const raw = fs.readFileSync(p, 'utf8');
  const data = JSON.parse(raw);

  // Ҳимоя: тегмасдан қайта ёзиш айнан бир хил натижа бермаса, формат
  // тахминимиз нотўғри — файлга тегмаймиз.
  if (serialize(data) !== raw) {
    console.error(`${file}: format mismatch — файл ўзгартирилмади`);
    process.exitCode = 1;
    continue;
  }

  let added = 0;
  let updated = 0;
  for (const [k, v] of Object.entries(entries)) {
    if (!(k in data)) {
      data[k] = v;
      added++;
    } else if (data[k] !== v) {
      data[k] = v;
      updated++;
    }
  }

  fs.writeFileSync(p, serialize(data));
  console.log(`${file}: added ${added}, updated ${updated}`);
}

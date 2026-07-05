const fs = require('fs');
const path = require('path');

const keys = {
  uz_Cyrl: {
    marshrut_direction_card_hint:
      'Қаердан ва қаerga МФЙ танланг — қидирув автоматик бошланади',
    marshrut_eta_min_unit: 'дақ',
    marshrut_call_hint: 'Тизим навбат бўйича чақиради',
    marshrut_empty_no_active: 'Ҳозир фаол рейс йўқ',
    marshrut_empty_all_full: '{n} та рейс тўлиқ',
    marshrut_empty_all_offline: 'Ҳайдовчилар ҳозир офлайн',
    marshrut_empty_wrong_route:
      'Бу йўналишда ҳайдовчи йўқ — йўналишни алмаштириб кўринг',
    marshrut_empty_too_far: 'Яқин атрофдаги ҳайдовчилар топилмади',
    marshrut_more_drivers_hidden:
      'Яна {n} та ҳайдовчи фильтр сабабли кўринmayapti',
  },
  uz_Latn: {
    marshrut_direction_card_hint:
      "Qayerdan va qayerga MFY tanlang — qidiruv avtomatik boshlanadi",
    marshrut_eta_min_unit: 'daq',
    marshrut_call_hint: "Tizim navbat bo'yicha chaqiradi",
    marshrut_empty_no_active: "Hozir faol reys yo'q",
    marshrut_empty_all_full: '{n} ta reys to\'liq',
    marshrut_empty_all_offline: 'Haydovchilar hozir offline',
    marshrut_empty_wrong_route:
      "Bu yo'nalishda haydovchi yo'q — yo'nalishni almashtirib ko'ring",
    marshrut_empty_too_far: 'Yaqin atrofdagi haydovchilar topilmadi',
    marshrut_more_drivers_hidden:
      "Yana {n} ta haydovchi filter sababli ko'rinmayapti",
  },
  ru: {
    marshrut_direction_card_hint:
      'Выберите МФY откуда и куда — поиск начнётся автоматически',
    marshrut_eta_min_unit: 'мин',
    marshrut_call_hint: 'Система вызывает по очереди',
    marshrut_empty_no_active: 'Сейчас нет активных рейсов',
    marshrut_empty_all_full: '{n} рейсов заполнены',
    marshrut_empty_all_offline: 'Водители сейчас offline',
    marshrut_empty_wrong_route:
      'Нет водителей по этому направлению — попробуйте поменять направление',
    marshrut_empty_too_far: 'Поблизости водители не найдены',
    marshrut_more_drivers_hidden: 'Ещё {n} водителей скрыты фильтром',
  },
};

for (const [file, entries] of Object.entries(keys)) {
  const p = path.join('c:/projects/ava_gurlan/assets/lang', `${file}.json`);
  const data = JSON.parse(fs.readFileSync(p, 'utf8'));
  let added = 0;
  for (const [k, v] of Object.entries(entries)) {
    if (!(k in data)) {
      data[k] = v;
      added++;
    }
  }
  const sorted = Object.fromEntries(
    Object.entries(data).sort(([a], [b]) => a.localeCompare(b)),
  );
  fs.writeFileSync(p, JSON.stringify(sorted, null, 2) + '\n');
  console.log(`${file}: added ${added} keys`);
}

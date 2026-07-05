const fs = require('fs');
const path = require('path');

const keys = {
  uz_Cyrl: {
    marshrut_tab_list: 'Рўйхат',
    marshrut_tab_map: 'Харита',
    marshrut_map_no_drivers_gps:
      'Ҳайдовчилар joylashuvi hozir ko\'rinmayapti — ro\'yxatdan tanlang',
    marshrut_map_marker_snippet: '{eta} daq · {seats} o\'rin',
    marshrut_remind_later: 'Keyinroq eslatish',
    marshrut_remind_later_hint:
      'Haydovchi paydo bo\'lsa, bildirishnoma yuboramiz',
    marshrut_remind_in_15: '15 daqiqadan keyin',
    marshrut_remind_in_30: '30 daqiqadan keyin',
    marshrut_remind_scheduled: 'Eslatma o\'rnatildi',
    marshrut_remind_scheduled_at: 'Eslatma: {time} da',
    marshrut_remind_cancel: 'Eslatmani bekor qilish',
    marshrut_remind_cancelled: 'Eslatma bekor qilindi',
    marshrut_remind_notification_title: 'Marshrut taksi',
    marshrut_remind_notification_body:
      '{from} → {to} yo\'nalishida qayta qidiring',
  },
  uz_Latn: {
    marshrut_tab_list: 'Ro\'yxat',
    marshrut_tab_map: 'Xarita',
    marshrut_map_no_drivers_gps:
      'Haydovchilar joylashuvi hozir ko\'rinmayapti — ro\'yxatdan tanlang',
    marshrut_map_marker_snippet: '{eta} daq · {seats} o\'rin',
    marshrut_remind_later: 'Keyinroq eslatish',
    marshrut_remind_later_hint:
      'Haydovchi paydo bo\'lsa, bildirishnoma yuboramiz',
    marshrut_remind_in_15: '15 daqiqadan keyin',
    marshrut_remind_in_30: '30 daqiqadan keyin',
    marshrut_remind_scheduled: 'Eslatma o\'rnatildi',
    marshrut_remind_scheduled_at: 'Eslatma: {time} da',
    marshrut_remind_cancel: 'Eslatmani bekor qilish',
    marshrut_remind_cancelled: 'Eslatma bekor qilindi',
    marshrut_remind_notification_title: 'Marshrut taksi',
    marshrut_remind_notification_body:
      '{from} → {to} yo\'nalishida qayta qidiring',
  },
  ru: {
    marshrut_tab_list: 'Список',
    marshrut_tab_map: 'Карта',
    marshrut_map_no_drivers_gps:
      'Местоположение водителей сейчас недоступно — выберите из списка',
    marshrut_map_marker_snippet: '{eta} мин · {seats} мест',
    marshrut_remind_later: 'Напомнить позже',
    marshrut_remind_later_hint:
      'Отправим уведомление, когда можно снова искать',
    marshrut_remind_in_15: 'Через 15 минут',
    marshrut_remind_in_30: 'Через 30 минут',
    marshrut_remind_scheduled: 'Напоминание установлено',
    marshrut_remind_scheduled_at: 'Напоминание в {time}',
    marshrut_remind_cancel: 'Отменить напоминание',
    marshrut_remind_cancelled: 'Напоминание отменено',
    marshrut_remind_notification_title: 'Маршрутное такси',
    marshrut_remind_notification_body:
      'Повторите поиск: {from} → {to}',
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
  console.log(`${file}: added ${added}`);
}

const fs = require('fs');
const path = require('path');

/** Phase 1 — bosh ekran l10n (grid, hamyon, promo, non banner). */
const keys = {
  uz_Cyrl: {
    home_module_local: 'МАҲАЛЛИЙ ТАКСИ',
    home_module_intercity: 'ШАҲАРЛАРАРО ТАКСИ',
    milk_short_label: 'СУТ ҚАБУЛ',
    home_module_courier: 'КУРЬЕР ХИЗМАТИ',
    home_module_carpet: 'ГИЛАМ ЮВИШ',
    home_module_relatives: 'ЯҚИНЛАРИМ',
    home_module_tire: 'АВТО ШИНА',
    home_module_car_wash: 'АВТО ЮВИШ',
    home_module_oil_change: 'МОЙ АЛМАШТИРИШ',
    home_coming_soon: 'Тез орада',
    home_location_gurlan: 'Гурлан, Хоразм',
    home_date_today: '{day}.{month}.{year} йил',
    home_amount_with_currency: '{amount} {currency}',
    home_display_name_aka: '{name} aka',
    home_wallet_active: 'Фаол',
    home_wallet_last_tx_prefix: 'Охирги: ',
    non_promo_title: 'Нон буюртма bering',
    non_promo_subtitle: 'Яangi non — 500 сўm, eshigingizga',
    non_promo_cta: 'Буюртма →',
    home_promo_order_cta: 'Буюртма bering →',
  },
  uz_Latn: {
    home_module_courier: 'Kuryer xizmati',
    home_module_carpet: 'Gilam yuvish',
    home_module_relatives: 'Mening yaqinlarim',
    home_module_tire: 'Avto shina',
    home_module_car_wash: 'Avto yuvish',
    home_module_oil_change: 'Moy almashtirish',
    home_coming_soon: 'Tez kunda',
    home_location_gurlan: 'Gurlan, Xorazm',
    home_date_today: '{day}.{month}.{year} yil',
    home_amount_with_currency: '{amount} {currency}',
    home_display_name_aka: '{name} aka',
    home_wallet_active: 'Faol',
    home_wallet_last_tx_prefix: 'Oxirgi: ',
    non_promo_title: 'Non buyurtma qiling',
    non_promo_subtitle: "Yangi non — 500 so'm, eshigingizga",
    non_promo_cta: 'Buyurtma →',
    home_promo_order_cta: 'Buyurtma berish →',
  },
  ru: {
    home_module_courier: 'Курьерская служба',
    home_module_carpet: 'Стирка ковров',
    home_module_relatives: 'Мои близкие',
    home_module_tire: 'Автошины',
    home_module_car_wash: 'Автомойка',
    home_module_oil_change: 'Замена масла',
    home_coming_soon: 'Скоро',
    home_location_gurlan: 'Гурлан, Хорезм',
    home_date_today: '{day}.{month}.{year} г.',
    home_amount_with_currency: '{amount} {currency}',
    home_display_name_aka: '{name} aka',
    home_wallet_active: 'Активен',
    home_wallet_last_tx_prefix: 'Последняя: ',
    non_promo_title: 'Закажите хлеб',
    non_promo_subtitle: 'Свежий хлеб — 500 сум, к вашей двери',
    non_promo_cta: 'Заказ →',
    home_promo_order_cta: 'Оформить заказ →',
  },
};

for (const [file, entries] of Object.entries(keys)) {
  const p = path.join('c:/projects/ava_gurlan/assets/lang', `${file}.json`);
  const data = JSON.parse(fs.readFileSync(p, 'utf8'));
  let n = 0;
  for (const [k, v] of Object.entries(entries)) {
    data[k] = v;
    n++;
  }
  const sorted = Object.fromEntries(
    Object.entries(data).sort(([a], [b]) => a.localeCompare(b)),
  );
  fs.writeFileSync(p, JSON.stringify(sorted, null, 2) + '\n');
  console.log(`${file}: ${n} keys`);
}

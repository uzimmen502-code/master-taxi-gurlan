const fs = require('fs');
const path = require('path');

const keys = {
  uz_Cyrl: {
    marshrut_taxi: 'МАРШРУТ ТАКСИ',
    marshrut_quick_directions: 'Тез танлов',
    marshrut_results_header: '🚐 {count} · {price}',
    marshrut_results_header_count: '🚐 {count}',
    marshrut_nearest_driver: 'Энг яқин: {name} · {eta} daq',
    marshrut_sticky_route: '{from} → {to}',
    marshrut_seat_price_short: '{price} сўм/ўрин',
  },
  uz_Latn: {
    marshrut_quick_directions: 'Tez tanlov',
    marshrut_results_header: '🚐 {count} · {price}',
    marshrut_results_header_count: '🚐 {count}',
    marshrut_nearest_driver: 'Eng yaqin: {name} · {eta} daq',
    marshrut_sticky_route: '{from} → {to}',
    marshrut_seat_price_short: "{price} so'm/o'rin",
  },
  ru: {
    marshrut_quick_directions: 'Быстрый выбор',
    marshrut_results_header: '🚐 {count} · {price}',
    marshrut_results_header_count: '🚐 {count}',
    marshrut_nearest_driver: 'Ближайший: {name} · {eta} мин',
    marshrut_sticky_route: '{from} → {to}',
    marshrut_seat_price_short: '{price} сум/место',
  },
};

for (const [file, entries] of Object.entries(keys)) {
  const p = path.join('c:/projects/ava_gurlan/assets/lang', `${file}.json`);
  const data = JSON.parse(fs.readFileSync(p, 'utf8'));
  let changed = 0;
  for (const [k, v] of Object.entries(entries)) {
    if (data[k] !== v) {
      data[k] = v;
      changed++;
    }
  }
  const sorted = Object.fromEntries(
    Object.entries(data).sort(([a], [b]) => a.localeCompare(b)),
  );
  fs.writeFileSync(p, JSON.stringify(sorted, null, 2) + '\n');
  console.log(`${file}: updated ${changed}`);
}

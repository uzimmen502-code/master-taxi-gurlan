const fs = require('fs');
const path = require('path');

const keys = {
  uz_Cyrl: {
    marshrut_recent_directions: 'Сўнгги йўналишлар',
    marshrut_popular_directions: 'Машhur йўналишлар',
    marshrut_mfy_search_hint: 'МФЙ qidiring...',
    marshrut_mfy_no_results: 'Topilmadi — boshqa nom bilan qidiring',
  },
  uz_Latn: {
    marshrut_recent_directions: 'So\'nggi yo\'nalishlar',
    marshrut_popular_directions: 'Mashhur yo\'nalishlar',
    marshrut_mfy_search_hint: 'MFY qidiring...',
    marshrut_mfy_no_results: 'Topilmadi — boshqa nom bilan qidiring',
  },
  ru: {
    marshrut_recent_directions: 'Недавние направления',
    marshrut_popular_directions: 'Популярные направления',
    marshrut_mfy_search_hint: 'Поиск МФY...',
    marshrut_mfy_no_results: 'Не найдено — попробуйте другой запрос',
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

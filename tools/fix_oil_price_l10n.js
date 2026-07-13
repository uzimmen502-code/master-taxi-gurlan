const fs = require('fs');
for (const f of ['uz_Cyrl', 'uz_Latn', 'ru']) {
  const path = `assets/lang/${f}.json`;
  const j = JSON.parse(fs.readFileSync(path, 'utf8'));
  if (f === 'uz_Cyrl') {
    j.oil_price_from = '{price} сўм';
    j.oil_price_from_multiline = '{price}\nсўм';
  } else if (f === 'uz_Latn') {
    j.oil_price_from = '{price} so‘m';
    j.oil_price_from_multiline = '{price}\nso‘m';
  } else {
    j.oil_price_from = '{price} сум';
    j.oil_price_from_multiline = '{price}\nсум';
  }
  const sorted = Object.keys(j)
    .sort()
    .reduce((a, k) => {
      a[k] = j[k];
      return a;
    }, {});
  fs.writeFileSync(path, JSON.stringify(sorted, null, 2) + '\n');
  const check = JSON.parse(fs.readFileSync(path, 'utf8'));
  console.log(
    f,
    'nl=',
    check.oil_price_from_multiline.includes('\n'),
    'save=',
    !!check.oil_save,
  );
}

/**
 * O'zbek lotin matnini kirillga (uz_Cyrl.json uchun).
 * @param {string} text
 * @returns {string}
 */
function latinToUzCyrl(text) {
  if (!text || !/[A-Za-z]/.test(text)) return text;

  /** @type {string[]} */
  const placeholders = [];
  // ASCII harf ishlatilmaydi — aks holda P→П buziladi.
  let s = text.replace(/\{[^}]+\}/g, (m) => {
    placeholders.push(m);
    return `\uE000${placeholders.length - 1}\uE001`;
  });

  const digraphs = [
    ["G'", 'Ғ'],
    ["g'", 'ғ'],
    ["O'", 'Ў'],
    ["o'", 'ў'],
    ['Yu', 'Ю'],
    ['yu', 'ю'],
    ['Sh', 'Ш'],
    ['sh', 'ш'],
    ['Ch', 'Ч'],
    ['ch', 'ч'],
    ['Ng', 'Нг'],
    ['ng', 'нг'],
  ];
  for (const [from, to] of digraphs) {
    s = s.split(from).join(to);
  }

  /** @type {Record<string, string>} */
  const map = {
    A: 'А',
    B: 'Б',
    D: 'Д',
    E: 'Е',
    F: 'Ф',
    G: 'Г',
    H: 'Ҳ',
    I: 'И',
    J: 'Ж',
    K: 'К',
    L: 'Л',
    M: 'М',
    N: 'Н',
    O: 'О',
    P: 'П',
    Q: 'Қ',
    R: 'Р',
    S: 'С',
    T: 'Т',
    U: 'У',
    V: 'В',
    X: 'Х',
    Y: 'Й',
    Z: 'З',
    a: 'а',
    b: 'б',
    d: 'д',
    e: 'е',
    f: 'ф',
    g: 'г',
    h: 'ҳ',
    i: 'и',
    j: 'ж',
    k: 'к',
    l: 'л',
    m: 'м',
    n: 'н',
    o: 'о',
    p: 'п',
    q: 'қ',
    r: 'р',
    s: 'с',
    t: 'т',
    u: 'у',
    v: 'в',
    x: 'х',
    y: 'й',
    z: 'з',
  };

  s = s.replace(/[A-Za-z]/g, (c) => map[c] ?? c);
  s = s.replace(/\uE000(\d+)\uE001/g, (_, i) => placeholders[Number(i)]);

  return s
    .replace(/\bGPS\b/g, 'GPS')
    .replace(/\bMFY\b/g, 'МФY')
    .replace(/\bETA\b/g, 'ETA')
    .replace(/\bTAXI\b/g, 'ТАКСИ')
    .replace(/\bAPK\b/g, 'APK')
    .replace(/\bpush\b/g, 'push')
    .replace(/\bOnlayn\b/g, 'Онлайн')
    .replace(/\bonlayn\b/g, 'онлайн');
}

module.exports = { latinToUzCyrl };

/// Супермаркет миқдор арифметикаси — БУТУН сонларда (8-банд).
///
/// Миқдор «минг улуш»да сақланади: 1,5 кг → 1500, 2 дона → 2000. Нарх — бутун сўм / бирлик.
/// Сатр суммаси = `price × qtyMilli / 1000`, ярми юқорига (PROPOSED — сервер ҳисоби authoritative;
/// клиент фақат кўрсатади).
library;

int smToMilli(num v) => (v * 1000).round();

/// Серверга юбориладиган миқдор: бутун бўлса `int`, акс ҳолда `double` (1.5).
num smFromMilli(int milli) => milli % 1000 == 0 ? milli ~/ 1000 : milli / 1000;

/// Миқдор қадамга мос ва мусбатми.
bool smIsValidQty(int qtyMilli, int stepMilli) =>
    qtyMilli > 0 && stepMilli > 0 && qtyMilli % stepMilli == 0;

/// Миқдорни энг яқин рухсат этилган қадамга (камида бир қадам) тўғрилайди.
int smSnapQty(int qtyMilli, int stepMilli) {
  if (stepMilli <= 0) return qtyMilli;
  if (qtyMilli <= stepMilli) return stepMilli;
  final n = (qtyMilli + stepMilli ~/ 2) ~/ stepMilli;
  return n * stepMilli;
}

/// Сатр суммаси (бутун сўм).
int smLineTotal(int unitPrice, int qtyMilli) {
  if (unitPrice <= 0 || qtyMilli <= 0) return 0;
  return (unitPrice * qtyMilli + 500) ~/ 1000;
}

/// «1,5» / «2» — кўрсатиш учун.
String smFormatQty(int milli) {
  final whole = milli ~/ 1000;
  final frac = milli % 1000;
  if (frac == 0) return '$whole';
  var f = frac.toString().padLeft(3, '0');
  while (f.endsWith('0')) {
    f = f.substring(0, f.length - 1);
  }
  return '$whole,$f';
}

/// Фоиз бўйича сумма, ярми юқорига: `amount × percent / 100` (percent каср бўлиши мумкин: 11, 10.5).
int smPercentOf(int amount, num percent) {
  if (amount <= 0 || percent <= 0) return 0;
  final bp = (percent * 100).round(); // базис пункт
  return (amount * bp + 5000) ~/ 10000;
}

/// Фоиз бўйича сумма, юқорига яхлитлаб (вақтинча ушлаб қолиш — камайиб кетмасин).
int smPercentCeil(int amount, num percent) {
  if (amount <= 0 || percent <= 0) return 0;
  final bp = (percent * 100).round();
  return (amount * bp + 9999) ~/ 10000;
}

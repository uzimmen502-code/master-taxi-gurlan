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

/// Фоиз матни (эга 2026-11-28, 0.01 % аниқлик): 10 → «10», 12.5 → «12.5», 12.25 → «12.25».
String smPercentText(num percent) {
  final bp = (percent * 100).round();
  if (bp % 100 == 0) return '${bp ~/ 100}';
  return (bp / 100).toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

/// Админ киритган фоиз → bps (кўпи билан 2 хона каср, вергул ҳам; 0..maxBps); нотўғри — null.
int? smPercentTextToBps(String text, {required int maxBps}) {
  final t = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(t)) return null;
  final parts = t.split('.');
  final bps = int.parse(parts[0]) * 100 + (parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return bps > maxBps ? null : bps;
}

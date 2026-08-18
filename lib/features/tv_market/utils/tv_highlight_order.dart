/// Rolikdan kelganda highlight elementini roʻyxatning boshiga qo‘yadi.
List<T> tvOrderHighlightFirst<T>(
  List<T> items,
  bool Function(T item) isHighlight,
) {
  if (items.length < 2) return items;
  final hi = <T>[];
  final rest = <T>[];
  for (final item in items) {
    if (isHighlight(item)) {
      hi.add(item);
    } else {
      rest.add(item);
    }
  }
  if (hi.isEmpty) return items;
  return [...hi, ...rest];
}

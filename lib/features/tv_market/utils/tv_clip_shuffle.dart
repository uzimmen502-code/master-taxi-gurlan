import 'dart:math';

/// Илова ҳар очилганда ролик тартибини ўзгартиради.
List<T> tvShuffleClips<T>(List<T> items) {
  if (items.length < 2) return List<T>.from(items);
  final out = List<T>.from(items);
  out.shuffle(Random());
  return out;
}

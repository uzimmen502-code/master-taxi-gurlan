import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/ava_book.dart';

class AvaBookRepository {
  static AvaBook? _cached;

  Future<AvaBook> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final raw = await rootBundle
        .loadString('assets/book/ava_imkoniyatlar_kitobi.json');
    final book = AvaBook.fromJson(json.decode(raw) as Map<String, dynamic>);
    _cached = book;
    return book;
  }
}

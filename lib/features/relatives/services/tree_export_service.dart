import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../models/relative_person.dart';
import 'gedcom_exporter.dart';

/// GEDCOM fayl va daraxt rasmi (PNG/PDF) ulashish.
class TreeExportService {
  TreeExportService._();

  static Future<void> shareGedcom(List<RelativePerson> people) async {
    if (people.isEmpty) {
      throw StateError('empty');
    }
    final body = GedcomExporter.build(people: people);
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = await _writeTemp('nasab_daraxti_$stamp.ged', body);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/plain')],
      subject: 'AVA Zona — nasab daraxti (GEDCOM)',
    );
  }

  static Future<void> shareTreePng(GlobalKey captureKey) async {
    final png = await _capturePng(captureKey);
    if (png == null) throw StateError('capture');
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = await _writeTempBytes('nasab_daraxti_$stamp.png', png);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      subject: 'AVA Zona — nasab daraxti',
    );
  }

  static Future<void> shareTreePdf(GlobalKey captureKey) async {
    final png = await _capturePng(captureKey);
    if (png == null) throw StateError('capture');
    final doc = pw.Document();
    final image = pw.MemoryImage(png);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'AVA Zona — Насаб дарахти',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    final bytes = await doc.save();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = await _writeTempBytes('nasab_daraxti_$stamp.pdf', bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'AVA Zona — nasab daraxti (PDF)',
    );
  }

  static Future<Uint8List?> _capturePng(
    GlobalKey captureKey, {
    double pixelRatio = 2.0,
  }) async {
    final ctx = captureKey.currentContext;
    if (ctx == null) return null;
    final boundary = ctx.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    if (boundary.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  static Future<File> _writeTemp(String name, String text) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(text, flush: true);
    return file;
  }

  static Future<File> _writeTempBytes(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

import 'dart:math' as math;

import 'package:ava_gurlan/features/jobs/controllers/jobs_controller.dart';
import 'package:ava_gurlan/features/jobs/jobs_colors.dart';
import 'package:ava_gurlan/features/jobs/jobs_sections.dart';
import 'package:ava_gurlan/features/home/widgets/service_circle_tile.dart';
import 'package:ava_gurlan/models/job_ad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

JobAd _ad(String id, {String type = 'ad', bool urgent = false}) => JobAd(
      id: id,
      type: type,
      text: 'матн $id',
      title: 'эълон $id',
      authorName: 'Эга',
      authorPhone: '998901234567',
      address: '',
      isUrgent: urgent,
      status: 'active',
    );

List<String> _ids(List<JobAd> l) => l.map((e) => e.id).toList();

void main() {
  group('jobsSectionFeed — бўлим рўйхати', () {
    test('ШОШИЛИНЧ эълон бўлимда КЎРИНАДИ ва тепада туради (bug fix)', () {
      // Аввал шошилинч эълон таб филтридан чиқиб кетар ва ҳеч қаерда
      // кўринмасди.
      final sorted = [_ad('a'), _ad('u', urgent: true), _ad('b')];
      expect(_ids(jobsSectionFeed(sorted, AdKind.ad)), ['u', 'a', 'b']);
    });

    test('оддийлар тартиби сақланади', () {
      final sorted = [
        _ad('a'),
        _ad('u1', urgent: true),
        _ad('b'),
        _ad('u2', urgent: true),
        _ad('c'),
      ];
      expect(_ids(jobsSectionFeed(sorted, AdKind.ad)),
          ['u1', 'u2', 'a', 'b', 'c']);
    });

    test('бошқа тур кирмайди: Хизматлар бўлимида эълон йўқ ва аксинча', () {
      final sorted = [
        _ad('a'),
        _ad('s', type: 'service'),
        _ad('u', urgent: true),
      ];
      expect(_ids(jobsSectionFeed(sorted, AdKind.service)), ['s']);
      expect(_ids(jobsSectionFeed(sorted, AdKind.ad)), ['u', 'a']);
    });

    test('хизматда шошилинч белгиси ишламайди — тартиб ўзгармайди', () {
      final sorted = [
        _ad('s1', type: 'service'),
        _ad('s2', type: 'service', urgent: true),
      ];
      expect(_ids(jobsSectionFeed(sorted, AdKind.service)), ['s1', 's2']);
    });

    test('бўш рўйхат — йиқилмайди', () {
      expect(jobsSectionFeed(const [], AdKind.ad), isEmpty);
    });
  });

  group('JobsSections — иккита алоҳида бўлим', () {
    test('админ дарвозаси иккаласи учун битта `jobs` (эга қарори)', () {
      expect(JobsSections.gateId, 'jobs');
    });

    test('ҳар бўлимнинг ўз плиткаси, сарлавҳаси ва тугмаси', () {
      expect(JobsSections.tileIdFor(AdKind.ad), 'jobs');
      expect(JobsSections.tileIdFor(AdKind.service), 'jobs_services');
      expect(JobsSections.titleKeyFor(AdKind.ad), 'home_module_jobs_ads');
      expect(JobsSections.titleKeyFor(AdKind.service),
          'home_module_jobs_services');
      expect(JobsSections.addKeyFor(AdKind.ad), 'jobs_add_ad');
      expect(JobsSections.addKeyFor(AdKind.service), 'jobs_add_service');
    });

    test('эски «Иш бор» (work) — «Эълонлар» бўлимига тушади', () {
      expect(JobsSections.sectionOf(AdKind.work), AdKind.ad);
      expect(JobsSections.tileIdFor(AdKind.work), 'jobs');
    });

    test('бош саҳифа плиткалари РАНГДА фарқ қилади', () {
      expect(olxTintFor(JobsSections.adsTileId),
          isNot(olxTintFor(JobsSections.servicesTileId)));
    });

    // Эга қарори (2026-10-18): экранларда иккала бўлим бренд рангида (аввал
    // яшил/жигарранг: AppBar'даги тўқ матн ~3.5:1 ва ~2.4:1 контраст берарди).
    double lum(Color c) {
      double ch(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    double contrast(Color a, Color b) {
      final la = lum(a), lb = lum(b);
      final hi = math.max(la, lb), lo = math.min(la, lb);
      return (hi + 0.05) / (lo + 0.05);
    }

    test('«Эълонлар» ва «Хизматлар» AppBar фони — бренд (#FFA500)', () {
      expect(JobsColors.accentFor(AdKind.ad), const Color(0xFFFFA500));
      expect(JobsColors.accentFor(AdKind.service), const Color(0xFFFFA500));
    });

    test('AppBar/тугма: onBar матни бўлим фонида ўқилади (>= 4.5:1)', () {
      for (final k in [AdKind.ad, AdKind.service]) {
        expect(contrast(JobsColors.onBar, JobsColors.accentFor(k)),
            greaterThanOrEqualTo(4.5),
            reason: '$k AppBar/тугма контрасти');
      }
    });

    test('оқ ва крем фонда бўлим матни ўқилади (>= 4.5:1)', () {
      for (final k in [AdKind.ad, AdKind.service]) {
        final ink = JobsColors.accentTextFor(k);
        for (final bg in [
          Colors.white,
          JobsColors.surface,
          JobsColors.scaffold,
          JobsColors.fieldFill,
        ]) {
          expect(contrast(ink, bg), greaterThanOrEqualTo(4.5),
              reason: '$k матн ранги $bg фонда');
        }
      }
    });

    test('«Хизматлар» плиткасининг ранги ва иконкаси бор (кулранг эмас)', () {
      const fallback = Color(0xFFD9E2EC);
      expect(olxTintFor(JobsSections.servicesTileId), isNot(fallback));
      expect(hasServiceGlyph(JobsSections.servicesTileId), isTrue);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/relatives/screens/family_tree_view.dart';
import 'package:ava_gurlan/features/relatives/utils/family_tree_line_router.dart';
import 'package:ava_gurlan/features/relatives/utils/family_tree_routing_report.dart';
import 'package:ava_gurlan/models/relative_person.dart';

void main() {
  group('FamilyTreeLineRouter', () {
    test('to\'g\'ri segment to\'siq ichidan o\'tmaydi', () {
      final obs = [const Rect.fromLTWH(100, 100, 80, 60)];
      final router = FamilyTreeLineRouter(
        obstacles: obs,
        laneStep: 22,
        linePad: 8,
      );

      final blocked = router.route(
        const Offset(140, 50),
        const Offset(140, 210),
        obstacles: obs,
      );
      expect(blocked, isNotNull);
      expect(router.pathClear(blocked!, obs), isTrue);
      expect(blocked.length, lessThanOrEqualTo(FamilyTreeLineRouter.maxPathPoints));
    });

    test('gorizontal bus boshqa ramkadan o\'tmaydi', () {
      final obs = [
        const Rect.fromLTWH(50, 150, 60, 50),
        const Rect.fromLTWH(200, 150, 60, 50),
        const Rect.fromLTWH(125, 120, 60, 50),
      ];
      final router = FamilyTreeLineRouter(
        obstacles: obs,
        laneStep: 22,
        linePad: 8,
      );

      final path = router.route(
        const Offset(80, 100),
        const Offset(230, 100),
        obstacles: obs,
      );
      expect(path, isNotNull);
      expect(router.pathClear(path!, obs), isTrue);
    });

    test('laneStep koridor va yo\'laklar soniga moslashadi', () {
      expect(
        FamilyTreeLineRouter.laneStepFor(
          corridorHeight: 100,
          laneCount: 1,
          linePad: 8,
        ),
        inInclusiveRange(16, 28),
      );
      expect(
        FamilyTreeLineRouter.laneStepFor(
          corridorHeight: 100,
          laneCount: 5,
          linePad: 8,
        ),
        closeTo(16.8, 0.5),
      );
    });

    test('yo\'l topilmasa null qaytadi (fallback yo\'q)', () {
      final obs = [
        const Rect.fromLTWH(0, 0, 500, 500),
      ];
      final router = FamilyTreeLineRouter(
        obstacles: obs,
        laneStep: 22,
        linePad: 8,
      );

      final path = router.route(
        const Offset(250, 250),
        const Offset(250, 400),
        obstacles: obs,
      );
      expect(path, isNull);
    });

    test('har oila alohida bus Y oladi', () {
      final router = FamilyTreeLineRouter(
        obstacles: const [],
        laneStep: 22,
        linePad: 8,
      );
      final y1 = router.allocateBusY(
        laneId: 'a',
        corridorId: 0,
        preferred: 100,
        minY: 80,
        maxY: 200,
        minX: 0,
        maxX: 300,
      );
      final y2 = router.allocateBusY(
        laneId: 'b',
        corridorId: 0,
        preferred: 100,
        minY: 80,
        maxY: 200,
        minX: 0,
        maxX: 300,
      );
      expect(y1, isNotNull);
      expect(y2, isNotNull);
      expect((y1! - y2!).abs(), greaterThanOrEqualTo(18));
    });

    test('har oila alohida stem X oladi (Y oralig\'i ustma-ust)', () {
      final router = FamilyTreeLineRouter(
        obstacles: const [],
        laneStep: 22,
        linePad: 8,
      );
      final x1 = router.allocateStemX(
        laneId: 'a',
        corridorId: 0,
        preferred: 150,
        minX: 50,
        maxX: 250,
        minY: 0,
        maxY: 120,
      );
      final x2 = router.allocateStemX(
        laneId: 'b',
        corridorId: 0,
        preferred: 150,
        minX: 50,
        maxX: 250,
        minY: 0,
        maxY: 140,
      );
      expect(x1, isNotNull);
      expect(x2, isNotNull);
      expect((x1! - x2!).abs(), greaterThanOrEqualTo(18));
    });

    test('band segmentga penalty — bo\'sh yo\'l afzal', () {
      final router = FamilyTreeLineRouter(
        obstacles: const [],
        laneStep: 22,
        linePad: 8,
        preferShortestDirect: false,
      );
      // Qisqa band vertikal — to'g'ri gorizontalni bloklaydi, aylanma mumkin.
      router.registerSegment(const Offset(100, 90), const Offset(100, 110));
      final path = router.route(
        const Offset(50, 100),
        const Offset(150, 100),
      );
      expect(path, isNotNull);
      for (var i = 0; i < path!.length - 1; i++) {
        expect(
          FamilyTreeLineRouter.segmentsConflict(
            path[i],
            path[i + 1],
            const Offset(100, 90),
            const Offset(100, 110),
          ),
          isFalse,
        );
      }
    });
  });

  group('FamilyTreeView routing integration', () {
    setUp(() {
      FamilyTreeView.debugRoutingReport = null;
    });

    Future<FamilyTreeRoutingReport> pumpTree(
      WidgetTester tester,
      List<RelativePerson> people,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 900,
              child: FamilyTreeView(people: people),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final report = FamilyTreeView.debugRoutingReport;
      expect(report, isNotNull, reason: 'routing report yaratilmagan');
      if (!report!.routingSucceeded || !report.allSegmentsClearOfFrames) {
        // ignore: avoid_print
        print(
          'ROUTING DEBUG: ok=${report.routingSucceeded} '
          'violations=${report.violations} '
          'segments=${report.segments.length} '
          'cards=${report.cardRects.length} '
          'rowGap=${report.layoutRowGap} '
          'sibGap=${report.layoutSiblingGap}',
        );
      }
      return report;
    }

    testWidgets('3 avlod, 4 juftlik, ko\'p farzand — 0 buzilish', (tester) async {
      final people = _complexThreeGenerationTree();
      final report = await pumpTree(tester, people);

      expect(report.routingSucceeded, isTrue);
      expect(report.segments, isNotEmpty);
      expect(report.allSegmentsClearOfFrames, isTrue,
          reason: 'violations=${report.violations}');
      _expectChildrenBelowParents(report);
    });

    testWidgets('parallel tarmoqlar — gorizontal bus ramkadan o\'tmaydi',
        (tester) async {
      final people = _wideParallelBranchesTree();
      final report = await pumpTree(tester, people);

      expect(report.routingSucceeded, isTrue);
      expect(report.allSegmentsClearOfFrames, isTrue,
          reason: 'violations=${report.violations}, '
              'segments=${report.segments.length}, '
              'rowGap=${report.layoutRowGap}');
    });

    testWidgets('yakka ota-ona + 6 farzand', (tester) async {
      final people = [
        const RelativePerson(id: 'p', fullName: 'Ota', gender: 'male'),
        for (var i = 1; i <= 6; i++)
          RelativePerson(
            id: 'c$i',
            fullName: 'Farzand $i',
            gender: i.isEven ? 'female' : 'male',
            fatherId: 'p',
          ),
      ];
      final report = await pumpTree(tester, people);

      expect(report.routingSucceeded, isTrue);
      expect(report.allSegmentsClearOfFrames, isTrue);
      _expectChildrenBelowParents(report);
    });

    testWidgets('ikki mustaqil ildiz — har ikkala tarmoq chiziqlari toza',
        (tester) async {
      final people = [
        const RelativePerson(id: 'a1', fullName: 'A1', gender: 'male'),
        const RelativePerson(
            id: 'a2', fullName: 'A2', gender: 'female', fatherId: 'a1'),
        const RelativePerson(id: 'b1', fullName: 'B1', gender: 'male'),
        const RelativePerson(
            id: 'b2', fullName: 'B2', gender: 'female', fatherId: 'b1'),
        const RelativePerson(
            id: 'b3', fullName: 'B3', gender: 'male', fatherId: 'b1'),
      ];
      final report = await pumpTree(tester, people);

      expect(report.routingSucceeded, isTrue);
      expect(report.allSegmentsClearOfFrames, isTrue);
    });
  });
}

List<RelativePerson> _complexThreeGenerationTree() {
  return [
    const RelativePerson(
        id: 'gg1', fullName: 'Bobo', gender: 'male', spouseId: 'gg2'),
    const RelativePerson(
        id: 'gg2', fullName: 'Momo', gender: 'female', spouseId: 'gg1'),
    const RelativePerson(
      id: 'f1',
      fullName: 'Ota1',
      gender: 'male',
      fatherId: 'gg1',
      motherId: 'gg2',
      spouseId: 'm1',
    ),
    const RelativePerson(
        id: 'm1', fullName: 'Ona1', gender: 'female', spouseId: 'f1'),
    const RelativePerson(
      id: 'f2',
      fullName: 'Ota2',
      gender: 'male',
      fatherId: 'gg1',
      motherId: 'gg2',
      spouseId: 'm2',
    ),
    const RelativePerson(
        id: 'm2', fullName: 'Ona2', gender: 'female', spouseId: 'f2'),
    const RelativePerson(
      id: 'f3',
      fullName: 'Ota3',
      gender: 'male',
      fatherId: 'gg1',
      motherId: 'gg2',
      spouseId: 'm3',
    ),
    const RelativePerson(
        id: 'm3', fullName: 'Ona3', gender: 'female', spouseId: 'f3'),
    const RelativePerson(
      id: 'f4',
      fullName: 'Ota4',
      gender: 'male',
      fatherId: 'gg1',
      motherId: 'gg2',
      spouseId: 'm4',
    ),
    const RelativePerson(
        id: 'm4', fullName: 'Ona4', gender: 'female', spouseId: 'f4'),
    for (var i = 1; i <= 3; i++)
      RelativePerson(
        id: 'c1_$i',
        fullName: 'C1-$i',
        gender: i.isEven ? 'female' : 'male',
        fatherId: 'f1',
        motherId: 'm1',
      ),
    for (var i = 1; i <= 2; i++)
      RelativePerson(
        id: 'c2_$i',
        fullName: 'C2-$i',
        gender: i.isEven ? 'female' : 'male',
        fatherId: 'f2',
        motherId: 'm2',
      ),
    for (var i = 1; i <= 4; i++)
      RelativePerson(
        id: 'c3_$i',
        fullName: 'C3-$i',
        gender: i.isEven ? 'female' : 'male',
        fatherId: 'f3',
        motherId: 'm3',
      ),
    const RelativePerson(
      id: 'c4_1',
      fullName: 'C4-1',
      gender: 'male',
      fatherId: 'f4',
      motherId: 'm4',
    ),
  ];
}

void _expectChildrenBelowParents(FamilyTreeRoutingReport report) {
  expect(
    report.childrenBelowParents,
    isTrue,
    reason: 'farzand ota-onadan tepada joylashgan',
  );
}

/// Keng yoyilgan parallel oilalar — gorizontal bus muammosi uchun.
List<RelativePerson> _wideParallelBranchesTree() {
  return [
    const RelativePerson(
        id: 'root_m', fullName: 'Root', gender: 'male', spouseId: 'root_f'),
    const RelativePerson(
        id: 'root_f', fullName: 'RootF', gender: 'female', spouseId: 'root_m'),
    for (var i = 1; i <= 5; i++) ...[
      RelativePerson(
        id: 'p${i}m',
        fullName: 'P$i M',
        gender: 'male',
        fatherId: 'root_m',
        motherId: 'root_f',
        spouseId: 'p${i}f',
      ),
      RelativePerson(
        id: 'p${i}f',
        fullName: 'P$i F',
        gender: 'female',
        spouseId: 'p${i}m',
      ),
      for (var j = 1; j <= 3; j++)
        RelativePerson(
          id: 'p${i}c$j',
          fullName: 'P$i-C$j',
          gender: j.isEven ? 'female' : 'male',
          fatherId: 'p${i}m',
          motherId: 'p${i}f',
        ),
    ],
  ];
}

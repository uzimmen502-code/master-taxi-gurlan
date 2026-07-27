import 'dart:async';

import '../../../models/relative_person.dart';
import '../../../models/tree_person.dart';
import '../../../repositories/relatives_repository.dart';
import '../../../repositories/tree_repository.dart';
import 'tree_redirect_resolver.dart';

/// Дарахт экрани учун бирлаштирилган ҳолат (meta+personal+component+redirects).
class FamilyTreeBundle {
  const FamilyTreeBundle({
    required this.componentId,
    required this.personId,
    required this.personal,
    required this.component,
    required this.redirects,
    required this.renderPeople,
    required this.duplicateGroups,
    this.loading = false,
  });

  final String componentId;
  final String personId;
  final List<RelativePerson> personal;
  final List<TreePerson> component;
  final TreeRedirectMap redirects;
  final List<RelativePerson> renderPeople;
  final List<List<TreePerson>> duplicateGroups;
  final bool loading;

  Map<String, RelativePerson> get personalById =>
      {for (final p in personal) p.id: p};

  Map<String, TreePerson> get componentById =>
      {for (final n in component) n.id: n};
}

/// Nested StreamBuilder ўрнига: битта stream.
class FamilyTreeBundleSource {
  FamilyTreeBundleSource({
    required this.userId,
    TreeRepository? treeRepo,
    RelativesRepository? relativesRepo,
  })  : _tree = treeRepo ?? TreeRepository(),
        _relatives = relativesRepo ?? RelativesRepository();

  final String userId;
  final TreeRepository _tree;
  final RelativesRepository _relatives;

  Stream<FamilyTreeBundle> watch() {
    late StreamController<FamilyTreeBundle> controller;
    StreamSubscription<({String componentId, String personId})>? metaSub;
    StreamSubscription<List<RelativePerson>>? personalSub;
    StreamSubscription<List<TreePerson>>? compSub;

    var componentId = '';
    var personId = '';
    var personal = const <RelativePerson>[];
    var component = const <TreePerson>[];
    var metaReady = false;
    var personalReady = false;
    var compReady = false;
    var emitSeq = 0;

    Future<void> emit({bool forceLoading = false}) async {
      final seq = ++emitSeq;
      final waiting = !metaReady || !personalReady || !compReady;
      if (forceLoading ||
          (waiting && personal.isEmpty && component.isEmpty)) {
        if (!controller.isClosed) {
          controller.add(FamilyTreeBundle(
            componentId: componentId,
            personId: personId,
            personal: personal,
            component: component,
            redirects: const {},
            renderPeople: const [],
            duplicateGroups: const [],
            loading: true,
          ));
        }
      }
      if (waiting && personal.isEmpty && component.isEmpty) return;

      final ids = TreeRepository.collectTreeRelatedIds(personal, component);
      final redirects = await _tree.fetchRedirectsForIds(ids);
      if (seq != emitSeq || controller.isClosed) return;

      final people = buildTreeRenderPeople(
        personal: personal,
        component: component,
        redirects: redirects,
      );
      if (!controller.isClosed) {
        controller.add(FamilyTreeBundle(
          componentId: componentId,
          personId: personId,
          personal: personal,
          component: component,
          redirects: redirects,
          renderPeople: people,
          duplicateGroups: findDuplicateGroups(component),
          loading: false,
        ));
      }
    }

    void listenComponent(String id) {
      unawaited(compSub?.cancel());
      compReady = false;
      component = const [];
      compSub = _tree.watchComponent(id).listen(
        (c) {
          component = c;
          compReady = true;
          unawaited(emit());
        },
        onError: controller.addError,
      );
    }

    controller = StreamController<FamilyTreeBundle>(
      onListen: () {
        metaSub = _tree.watchMyTreeMeta(userId).listen(
          (meta) {
            componentId = meta.componentId;
            personId = meta.personId;
            metaReady = true;
            listenComponent(componentId);
            unawaited(emit());
          },
          onError: controller.addError,
        );
        personalSub = _relatives.watchPeople(userId).listen(
          (p) {
            personal = p;
            personalReady = true;
            unawaited(emit());
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await metaSub?.cancel();
        await personalSub?.cancel();
        await compSub?.cancel();
      },
    );

    return controller.stream;
  }
}

/// Display merge (genealogy ← component, CRM ← personal).
List<RelativePerson> buildTreeRenderPeople({
  required List<RelativePerson> personal,
  required List<TreePerson> component,
  required TreeRedirectMap redirects,
}) {
  final personalById = {for (final p in personal) p.id: p};
  final compById = {for (final n in component) n.id: n};
  final renderById = <String, RelativePerson>{};
  final allIds = {
    ...component.map((n) => n.id),
    ...personal.map((p) => p.id),
  };
  for (final id in allIds) {
    if (redirects.containsKey(id)) continue;
    final merged = mergeForTreeDisplay(personalById[id], compById[id]);
    if (merged == null) continue;
    renderById[id] = resolvePersonLinks(merged, redirects);
  }
  return renderById.values.toList(growable: false);
}

RelativePerson? mergeForTreeDisplay(RelativePerson? personal, TreePerson? node) {
  if (personal == null && node == null) return null;
  if (personal == null) return node!.toRelativePerson();
  if (node == null) return personal;
  return RelativePerson(
    id: node.id,
    fullName: node.fullName.isNotEmpty ? node.fullName : personal.fullName,
    firstName: personal.firstName,
    lastName: personal.lastName,
    patronymic: personal.patronymic,
    photoUrl: node.photoUrl.isNotEmpty ? node.photoUrl : personal.photoUrl,
    photoPath: personal.photoPath,
    phone: personal.phone,
    address: personal.address,
    birthDate: node.birthDate ?? personal.birthDate,
    gender: node.gender.isNotEmpty ? node.gender : personal.gender,
    relationDegree: personal.relationDegree,
    side: personal.side,
    notes: personal.notes,
    fatherId: node.fatherId ?? personal.fatherId,
    motherId: node.motherId ?? personal.motherId,
    spouseId: node.spouseId ?? personal.spouseId,
    isSelf: personal.isSelf,
    createdAt: personal.createdAt,
  );
}

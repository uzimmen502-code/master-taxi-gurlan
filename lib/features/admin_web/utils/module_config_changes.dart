import '../../../models/service_module_config.dart';

/// «Ҳудудлар ва хизматлар»: бир катак ўзгариши — `from` → `to`.
///
/// `null` — туман/МФЙ катагида «мерос» (override йўқ); Global устунда
/// `from == null` — модул ҳужжатда йўқ эди. Сервер (`adminSaveModuleConfig`)
/// `from`ни ўзидаги жорий қиймат билан солиштиради: бошқа бўлса — конфликт.
class ModuleChange {
  const ModuleChange(this.moduleId, this.from, this.to);

  final String moduleId;
  final ModuleStatus? from;
  final ModuleStatus? to;

  Map<String, Object?> toJson() => {
        'moduleId': moduleId,
        'from': from?.wire,
        'to': to?.wire,
      };
}

/// Сақланган ([saved]) ва жорий ([current]) ҳолат фарқи — [ids] тартибида,
/// фақат ўзгарганлари. Ўзгармаган катак серверга юборилмайди.
List<ModuleChange> diffModuleStatuses(
  Map<String, ModuleStatus?> saved,
  Map<String, ModuleStatus?> current,
  Iterable<String> ids,
) =>
    [
      for (final id in ids)
        if (saved[id] != current[id]) ModuleChange(id, saved[id], current[id]),
    ];

/// Катак ойнасидаги танлов. Ойна ташқарисига босиб ёпилса `showDialog`
/// `null` қайтаради — бу «ҳеч нарса танланмади». «Мерос» эса алоҳида банд:
/// `CellPick(null)`.
class CellPick {
  const CellPick(this.status);

  final ModuleStatus? status;
}

/// Танлов катакни ўзгартирадими? Ёпилган ойна (`pick == null`) — йўқ.
bool cellPickChanges(CellPick? pick, ModuleStatus? current) =>
    pick != null && pick.status != current;

/// «Журнал» ёзуви — `adminListModuleConfigAudit` жавобидан
/// (`admin_audit`, kind `module_config_changed`).
class ModuleAuditEntry {
  const ModuleAuditEntry({
    required this.actor,
    required this.scope,
    required this.targetId,
    required this.changes,
    required this.source,
    this.enforceFrom,
    this.enforceTo,
    this.at,
  });

  /// Ўзгартирган админ телефони (998…).
  final String actor;

  /// `global` · `district` · `area`.
  final String scope;
  final String targetId;
  final List<ModuleChange> changes;

  /// `admin_ui` · `apk_module_sync`.
  final String source;
  final bool? enforceFrom;
  final bool? enforceTo;
  final DateTime? at;

  factory ModuleAuditEntry.fromMap(Map<Object?, Object?> m) {
    ModuleStatus? st(Object? v) => v == null ? null : ModuleStatus.fromWire(v);
    final rawChanges = m['changes'];
    final enforce = m['enforce'];
    final atMs = m['at'];
    return ModuleAuditEntry(
      actor: '${m['actor'] ?? ''}',
      scope: '${m['scope'] ?? ''}',
      targetId: '${m['targetId'] ?? ''}',
      source: '${m['source'] ?? ''}',
      changes: [
        if (rawChanges is List)
          for (final c in rawChanges)
            if (c is Map)
              ModuleChange(
                  '${c['moduleId'] ?? ''}', st(c['from']), st(c['to'])),
      ],
      enforceFrom: enforce is Map ? enforce['from'] as bool? : null,
      enforceTo: enforce is Map ? enforce['to'] as bool? : null,
      at: atMs is num
          ? DateTime.fromMillisecondsSinceEpoch(atMs.toInt())
          : null,
    );
  }
}

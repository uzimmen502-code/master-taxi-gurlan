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

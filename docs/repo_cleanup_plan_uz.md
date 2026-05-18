# Repository Cleanup Plan

Бу ҳужжат ҳозирги dirty working tree'ни хавфсиз тартиблаш учун.

## Ҳозирги ҳолат

Repository'да бир нечта турдаги ўзгаришлар аралашиб кетган:

- Катта app refactor: eski `lib/screens/*` ва eski service файллар ўчган, янги `lib/features/*` структураси пайдо бўлган.
- Marshrut dispatch architecture: queue dispatch, policy, audit, admin screens, driver lifecycle.
- Firestore rules/indexes: dispatch ва бошқа модуллар учун rules/indexes ўзгарган.
- Firebase/backend: `functions/*`, `firebase.json`, `storage.rules`, scripts.
- Assets/config: Android, web, localization, food images, generated/plugin files.

## Нима учун эҳтиёт бўлиш керак

Фақат Marshrut dispatch файлларини commit қилиш етарли эмас, чунки улар қуйидаги shared untracked файлларга таянади:

- `lib/main.dart`
- `lib/main_admin.dart`
- `lib/features/admin_web/screens/admin_shell.dart`
- `lib/core/utils/formatters.dart`
- `lib/utils/app_theme.dart`
- `lib/shared/widgets/*`
- `lib/services/location_service.dart`
- `lib/services/notification_service.dart`
- `lib/repositories/marshrut_driver_repository.dart`
- `lib/repositories/queue_repository.dart`
- `lib/repositories/schedules_repository.dart`
- `lib/models/schedule.dart`
- `lib/models/queue_entry.dart`
- `lib/models/marshrut_driver_option.dart`
- `lib/models/marshrut_driver_profile.dart`

Шунинг учун dispatch-only commit buildable бўлмаслиги мумкин.

## Тавсия қилинган commit тартиби

### 1. Baseline feature refactor commit

Мақсад: янги `lib/features/*`, `lib/models/*`, `lib/repositories/*`, `lib/services/*`, `lib/shared/*`, `lib/core/*`, `lib/utils/*` структурасини бир buildable baseline сифатида commit қилиш.

Кириши мумкин:

- `lib/main.dart`
- `lib/main_admin.dart`
- `lib/features/**`
- `lib/models/**`
- `lib/repositories/**`
- `lib/services/**`
- `lib/core/**`
- `lib/shared/**`
- `lib/utils/**`
- eski `lib/screens/*` ва eski service deletions, агар refactor шуни талаб қилса.

Commitдан олдин:

- `flutter test`
- `dart analyze` натижасида error йўқлигини текшириш
- user/admin build

### 2. Marshrut dispatch hardening commit

Мақсад: professional queue dispatch ва lifecycle/race condition ҳимояларини алоҳида кўрсатиш.

Кириши керак:

- `lib/features/marshrut/**`
- `lib/features/admin_web/screens/marshrut_admin_screen.dart`
- `lib/features/admin_web/screens/marshrut_dispatch_history_screen.dart`
- `lib/repositories/rides_repository.dart`
- `lib/models/active_trip.dart`
- `lib/models/marshrut_dispatch_event.dart`
- `docs/marshrut_dispatch_test_plan_uz.md`
- `docs/marshrut_dispatch_release_notes_uz.md`

Эслатма: агар 1-commit baseline қилинмаса, бу commit алоҳида compile бўлмаслиги мумкин.

### 3. Firebase rules/indexes commit

Мақсад: Firestore rules/indexes ва hosting config'ни алоҳида review қилиш.

Кириши мумкин:

- `firestore.rules`
- `firestore.indexes.json`
- `firebase.json`
- `storage.rules`
- `scripts/**`

Текширув:

- `firebase deploy --only firestore:rules --dry-run`
- `firebase deploy --only firestore:indexes --dry-run`
- `firebase deploy --only hosting --dry-run`

### 4. Assets/config/backend commit

Мақсад: Android/web/assets/functions каби катта unrelated ўзгаришларни алоҳида кўриш.

Кириши мумкин:

- `android/**`
- `web/**`
- `assets/**`
- `functions/**`
- `y/**`
- `pubspec.yaml`
- `pubspec.lock`
- platform generated files

Бу commit энг эҳтиёткорлик билан кўрилади, чунки config ва production behavior'га таъсири катта.

## Ҳозирги safest next step

1. Аввал baseline feature refactor scope'ни тасдиқлаш.
2. Шу baseline compile бўлишини текшириш.
3. Keyin Marshrut dispatch hardening'ни алоҳида commit қилиш.
4. Кейин Firebase rules/indexes ва hosting deploy'ни алоҳида қилиш.

## Текширувлар

Охирги текширувларда:

- `flutter test` ўтди.
- Marshrut-related targeted analyze error'сиз ўтди.
- Combined user/admin build ўтди.
- Firestore rules/indexes dry-run ўтди.
- Hosting dry-run ўтди.

Қолганлари:

- Full `dart analyze`да warning/info кўп, лекин real error йўқ.
- Manual live/test project checklist ҳали бажарилмаган.

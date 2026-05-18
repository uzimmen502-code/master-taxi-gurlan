# Baseline Commit Scope

Бу ҳужжат current dirty tree'ни биринчи хавфсиз commit'га тайёрлаш учун.

## Мақсад

Биринчи commit "baseline feature refactor" бўлиши керак. У янги app структурасини buildable ҳолатда сақлайди, лекин production config/assets/backend deploy ўзгаришларини аралаштирмайди.

## Baseline commit'га кириши керак

### App entry ва умумий структура

- `lib/main.dart`
- `lib/main_admin.dart`
- `lib/core/**`
- `lib/shared/**`
- `lib/widgets/**`
- `lib/utils/**`
- `lib/l10n/app_localizations.dart`
- `lib/firebase_options.dart`

### Янги feature структураси

- `lib/features/**`

Бу ичига қуйидагилар киради:

- admin web
- analytics
- bread
- chat
- courier
- driver home
- driver schedule
- food
- home
- intercity taxi
- jobs
- local taxi passenger
- map picker
- marshrut
- onboarding
- profile

### Model/repository/service қатлами

- `lib/models/**`
- `lib/repositories/**`
- `lib/services/**`

### Eski структура deletions

Агар янги `lib/features/**` структураси eski файлларни алмаштирган бўлса, baseline commit'га қуйидаги deletions ҳам кириши керак:

- `lib/screens/**`
- eski `lib/services/price_service.dart`
- eski `lib/services/directions_service.dart`
- eski `lib/services/saved_places_screen.dart`
- eski local taxi driver/passenger service/screen deletions

## Baseline commit'га эҳтиёткорлик билан киритилади

Бу файллар app compile учун керак бўлиши мумкин, лекин алоҳида кўриб чиқиш керак:

- `pubspec.yaml`
- `pubspec.lock`
- `assets/lang/ru.json`
- `assets/lang/uz_Cyrl.json`
- `assets/lang/uz_Latn.json`
- `test/widget_test.dart`

## Baseline commit'га кирмаслиги керак

Қуйидагилар baseline refactor'дан алоҳида commit бўлиши керак:

### Firebase/backend

- `firebase.json`
- `firestore.rules`
- `firestore.indexes.json`
- `storage.rules`
- `functions/**`
- `y/**`
- `scripts/**`

### Platform/config

- `android/**`
- `macos/**`
- `web/**`
- `flutter_native_splash.*`

### Assets/images

- `assets/images/**`
- янги `.webp` food/product images

### Local/generated/test artifacts

- `.firebase/**`
- `chrome-profile-*`
- `root-live*.png`
- `cors.json`
- `firebase` binary/file агар project artifact бўлмаса

## Baseline commit олдидан текширув

Baseline staging қилингандан кейин:

```powershell
flutter test
dart analyze
powershell -ExecutionPolicy Bypass -File scripts/build_combined_web.ps1
```

Эслатма: full `dart analyze`да warning/info қолиши мумкин. Real error бўлмаслиги муҳим.

## Baseline staging preview

Dry-run учун ишлатилган command:

```powershell
git add --dry-run -- "lib" "pubspec.yaml" "pubspec.lock" "assets/lang" "test/widget_test.dart"
```

Preview натижасига кўра baseline scope қуйидагиларни қамраб олади:

- янги `lib/features/**` структураси;
- янги `lib/models/**`, `lib/repositories/**`, `lib/services/**`;
- янги `lib/core/**`, `lib/shared/**`, `lib/utils/**`, `lib/widgets/**`;
- `lib/main.dart`, `lib/main_admin.dart`;
- eski `lib/screens/**` ва eski service deletions;
- `pubspec.yaml`, `pubspec.lock`;
- `assets/lang/**`;
- `test/widget_test.dart`.

Preview натижасига кўра baseline scope'га кирмайди:

- `firestore.rules`;
- `firestore.indexes.json`;
- `firebase.json`;
- `functions/**`;
- `y/**`;
- `android/**`;
- `web/**`;
- product/food image assets;
- `scripts/**`;
- `storage.rules`.

Агар baseline commit қилишга рухсат берилса, аввал шу command билан staging қилиш керак:

```powershell
git add -- "lib" "pubspec.yaml" "pubspec.lock" "assets/lang" "test/widget_test.dart"
```

## Кейинги commit'лар

1. `Baseline feature refactor`
2. `Marshrut dispatch hardening`
3. `Firebase rules and indexes`
4. `Hosting/scripts`
5. `Assets and platform config`

Шу тартиб review ва rollback'ни осон қилади.

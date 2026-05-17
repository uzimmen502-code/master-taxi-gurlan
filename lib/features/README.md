# features/

Ilovaning har bir biznes-modulі alohida papkada.

## Tuzilma (har bir feature ichida):
```
features/<name>/
├── screens/         # MaterialApp ga ko'rinadigan top-level ekranlar
├── widgets/         # faqat shu featureda ishlatiladigan widgetlar
├── controllers/     # ChangeNotifier'lar (ProfileController, ...)
└── models/          # faqat shu featureda ishlatiladigan modellar (umumiy bo'lsa /lib/models/ ga)
```

## Planlangan featurelar:
- `auth/` — login, register, phone_auth
- `home/`
- `profile/`
- `local_taxi/` (driver + passenger)
- `marshrut/`
- `intercity/`
- `courier/`
- `food/`
- `bread/`
- `admin/`

## Qoidalar:
1. Bir feature boshqa featureni **import qilmaydi**. Umumiy nimadir kerak bo'lsa → `shared/`, `repositories/`, `services/` ga.
2. Controller (ChangeNotifier) `Provider` orqali screen'ga ulanadi.
3. Screen iloji boricha "ahmoq" bo'lsin — logikani controller bajaradi.

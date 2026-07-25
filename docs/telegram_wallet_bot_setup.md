# Telegram Wallet Bot — ишга тушириш (env)

`functions.config()` эскирган. Энди **`.env`** ишлатилади.

## 3-қадам (янги)

### 1) Файл яратинг
`c:\projects\ava_gurlan\functions\.env` файлини очинг (ёки нусха):

```bash
cd c:\projects\ava_gurlan\functions
copy .env.example .env
```

### 2) `.env` ичига ёзинг
```env
TELEGRAM_WALLET_BOT_TOKEN=BotFather_берган_TOKEN
TELEGRAM_WALLET_BOT_USERNAME=AvaZonaWalletBot
TELEGRAM_WALLET_WEBHOOK_SECRET=ava_wallet_2026_secret_xyz
```

- `TOKEN` — @BotFather дан  
- `USERNAME` — @ белгисиз (масалан `AvaZonaWalletBot`)  
- `SECRET` — ўзингиз ўйлаган узун парол  

Сақланг. Бу файл git’га тушмайди.

### 3) Deploy
```bash
cd c:\projects\ava_gurlan
firebase deploy --only functions,firestore:rules,firestore:indexes,storage
```

### 4) Webhook (5-қадам)
Deployдан кейин Functions URL олинг, охирига қўшинг:
`?key=ava_wallet_2026_secret_xyz`

Кейин браузерда:
```
https://api.telegram.org/botTOKEN/setWebhook?url=ТОЛИК_URL&secret_token=ava_wallet_2026_secret_xyz
```

### 5) Админда карта (6-қадам)
Finance Center → Telegram ҳамён → Созлама

---

**Эски `firebase functions:config:set` ишлатманг** — керак эмас.

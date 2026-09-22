# «AVA ёрдамчиси» — илова ичидаги AI чат (В-1) — эга учун йўриқнома

**2026-09-21 ўзгариш:** Custom GPT йўли ёпилди — OpenAI шахсий аккаунтларда (Free/Go/Plus/Pro) янги GPT яратишни ўчирган, 2026-12-11 дан мавжуд GPT'лар ҳам ишламайди. Шунинг учун ёрдамчи **илова ичида**, Cloud Function + OpenAI API орқали қурилди. ChatGPT Plus обунаси бу мақсадда керак эмас.

Код тарафи тайёр: [functions/assistant_chat.js](../functions/assistant_chat.js) (сервер), [functions/assistant_prompt.js](../functions/assistant_prompt.js) (system prompt — Instructions + AVA билими + FAQ), [lib/features/assistant/](../lib/features/assistant/) (чат экрани, Pro пакетлар).

---

## 1. Тарифлар (эга қарори, 2026-09-22)

| Тариф | Лимит | Web search | Нарх |
|---|---|---|---|
| Оддий пакет | кунига 10 хабар | йўқ | бепул |
| Plus (бир марталик тўлов) | амалда чексиз (юмшоқ чегара 300/кун) | кунига 10 та | **12 500 сўм, бир марта** (доимий, 10 йил) |

Аввалги 7/15/30 кунлик пакетлар (15 000 / 25 000 / 30 000) default'дан олиб ташланди; керак бўлса `settings/assistant.packages` орқали қайтарилади: `[{"id":"d7","days":7,"price":15000},{"id":"d15","days":15,"price":25000},{"id":"d30","days":30,"price":30000,"promo":true}]`.
- Тўлов — **AVA ҳамёнидан** (`bonusBalance`), `assistantBuyPackage` callable; `wallet_ledger` + settlement ledger'га `purchase_debit / assistant_package` ёзуви тушади.
- Пакет жорий Pro муддатига **қўшилади** (7 кунлик олиб, 3 кун ўтгач яна 7 кунлик олса — жами 11 кун қолади).
- Кун чегараси — Тошкент вақти (00:00).
- Барча рақамлар `settings/assistant` ҳужжатидан релизсиз ўзгартирилади (3-бўлим).

**Харажат баҳоси:** `gpt-4.1-mini` билан бир хабар ≈ $0.0003–0.001 (4–13 сўм). Web search — ҳар қидирув ≈ $0.025–0.03 (300–400 сўм), шунинг учун фақат Pro'да ва кунига 10 та. Pro фойдаланувчи энг ёмон ҳолатда кунига ≈ 4 000–5 000 сўм харажат қилиши мумкин (10 қидирув + 300 хабар), одатда 100–500 сўм.

---

## 2. Сиз бажарадиган қадамлар (бир марта)

1. **OpenAI API калити.** [platform.openai.com](https://platform.openai.com) → аккаунт (ChatGPT аккаунти билан кириш мумкин) → **Billing** → $5–10 баланс қўйинг (pre-paid) → **API keys** → *Create new secret key* → калитни нусхаланг (`sk-...`, бир марта кўрсатилади).
2. Калитни `functions/.env` файлига қўйинг (файл git'га тушмайди):
   ```
   OPENAI_API_KEY=sk-...
   ```
3. Деплой:
   ```bash
   firebase deploy --only functions:assistantChat,functions:assistantGetStatus,functions:assistantBuyPackage,functions:assistantClearHistory,firestore:rules
   ```
4. Иловани янги релиз билан чиқаринг (Home'даги «AVA ёрдамчиси» тугмаси энди илова ичидаги чатни очади).
5. OpenAI'да **Usage limits** (Billing → Limits) ўрнатинг — масалан ойига $50 — кутилмаган харажатдан ҳимоя.

---

## 3. `settings/assistant` — релизсиз созлаш (ихтиёрий)

Firebase Console → Firestore → `settings` → `assistant` ҳужжати (йўқ бўлса яратинг). Ҳамма майдон ихтиёрий — йўқ бўлса код default'и ишлайди:

| Майдон | Default | Изоҳ |
|---|---|---|
| `enabled` | `true` | `false` — ёрдамчи вақтинча ўчирилади |
| `model` | `gpt-5-mini` | OpenAI модель номи (4.1-mini web search натижасини хом кўчиради) |
| `freeDailyLimit` | `10` | бепул кунлик хабар |
| `proDailyLimit` | `300` | Pro юмшоқ чегара |
| `proWebSearchDailyLimit` | `10` | Pro web search/кун |
| `reasoningEffort` | `low` | gpt-5*/o* учун; `minimal`/`low`/`medium` |
| `perMinuteLimit` | `8` | тезлик чегараси |
| `maxHistoryMessages` | `12` | суҳбат контексти (охирги N хабар) |
| `packages` | 7/15/30 кун | `[{id, days, price, promo}]` массив |
| `systemPrompt` | код ичидаги | тўлиқ алмаштиради (эҳтиёт бўлинг) |
| `extraKnowledge` | — | prompt охирига қўшилади — янги модул/акция ҳақида қисқа матн |

Масалан янги хизмат қўшилганда `extraKnowledge`га 3–4 қатор ёзиш кифоя — деплой керак эмас.

---

## 4. Кузатув

- **Харажат:** platform.openai.com → Usage (кунлик).
- **Фойдаланиш:** Firestore `users/{uid}/assistant_usage/{YYYY-MM-DD}` — `messages`, `webSearches`, `inputTokens`, `outputTokens`.
- **Сотувлар:** `users/{uid}/assistant_packages/*` ва `wallet_ledger` (`refType: assistant_package`).
- **Хатолар:** Firebase Console → Functions → Logs → `assistant:` префикси (`api_key_missing`, `OpenAI HTTP 429` ва ҳ.к.).

---

## 5. Синов — қабул мезони

- [ ] Бепул фойдаланувчи: 10 та хабардан кейин Pro варақаси чиқади; эртаси куни яна 10 та.
- [ ] «Шаҳарлараро таксига қандай буюртма бераман?» (3 тилда) — иловадаги ном/қадамлар билан жавоб.
- [ ] «Менинг балансим қанча?» — ўйлаб топмайди, «Ҳамён» бўлимига йўналтиради.
- [ ] Кирилл ўзбекчада савол — кирилл ўзбекчада жавоб.
- [ ] Pro: «Бугун Тошкентда об-ҳаво қандай?» — интернетдан жавоб, хабар остида «Интернетдан қидирилди» белгиси.
- [ ] Пакет сотиб олиш: баланс камаяди, `wallet_ledger`да ёзув, Pro муддати кўрсатилади; баланс етарли бўлмаса — «Тўлдириш» тугмаси Ҳамённи очади.
- [ ] Иккинчи пакет — муддат қўшилади (алмаштирилмайди).

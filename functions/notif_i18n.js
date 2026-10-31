/**
 * Серверда ёзиладиган хабарлар — УЧ ТИЛДА (uz_Cyrl / uz_Latn / ru).
 *
 * Тил қоидаси (эга, 2026-10-15): матн ўзгарса учала тил бирга. Фойдаланувчи
 * тили ИЛОВАДА сақланади; сервер уни `users/{id}.appLang` дан ўқийди
 * (илова `fcm_service`/тил ўзгарганда ёзади). Майдон йўқ (эски илова) —
 * `uz_Cyrl` (аввалги ҳолат, тахмин қилинмайди).
 *
 * Фақат ҳозирча ўтказилган хабарлар шу ерда: шаҳарлараро автоматик суриш ва
 * йўқолган посилка (`lost_*`, AVA Logistics).
 * Калит → тил → { title, body }; `{name}` ўринбосарлар `render`да.
 */
'use strict';

const DEFAULT_LANG = 'uz_Cyrl';
const LANGS = ['uz_Cyrl', 'uz_Latn', 'ru'];

const MESSAGES = {
  auto_shift_driver: {
    uz_Cyrl: { title: '⏱ Рейс {hours} соатга сурилди', body: 'Салон тўлмади. Янги жўнаш вақти {time} ({n}/{max}).' },
    uz_Latn: { title: '⏱ Reys {hours} soatga surildi', body: 'Salon to\'lmadi. Yangi jo\'nash vaqti {time} ({n}/{max}).' },
    ru: { title: '⏱ Рейс перенесён на {hours} ч.', body: 'Салон не заполнен. Новое время отправления {time} ({n}/{max}).' },
  },
  auto_shift_passenger: {
    uz_Cyrl: { title: '🕐 Рейс вақти ўзгарди', body: 'Жўнаш {time} га сурилди. Қулай бўлмаса бронни бекор қилишингиз мумкин.' },
    uz_Latn: { title: '🕐 Reys vaqti o\'zgardi', body: 'Jo\'nash {time} ga surildi. Qulay bo\'lmasa bronni bekor qilishingiz mumkin.' },
    ru: { title: '🕐 Время рейса изменилось', body: 'Отправление перенесено на {time}. Если неудобно, можно отменить бронь.' },
  },
  auto_shift_stop_cap: {
    uz_Cyrl: { title: '⏱ Рейс автоматик сурилмайди', body: 'Бугунги суриш лимити ({max} марта) тугади. Янги вақтни ўзингиз белгиланг ёки рейсни тугатинг.' },
    uz_Latn: { title: '⏱ Reys avtomatik surilmaydi', body: 'Bugungi surish limiti ({max} marta) tugadi. Yangi vaqtni o\'zingiz belgilang yoki reysni tugating.' },
    ru: { title: '⏱ Рейс больше не переносится автоматически', body: 'Лимит переносов на сегодня ({max}) исчерпан. Укажите новое время сами или завершите рейс.' },
  },
  china_quote_ready: {
    uz_Cyrl: { title: '🇨🇳 Хитой сўровингизга таклиф келди', body: '{refNo} бўйича таклифни иловада кўришингиз мумкин.' },
    uz_Latn: { title: '🇨🇳 Xitoy so\'rovingizga taklif keldi', body: '{refNo} bo\'yicha taklifni ilovada ko\'rishingiz mumkin.' },
    ru: { title: '🇨🇳 Получено предложение по запросу в Китай', body: 'Предложение по {refNo} можно посмотреть в приложении.' },
  },
  auto_shift_stop_midnight: {
    uz_Cyrl: { title: '⏱ Рейс автоматик сурилмайди', body: 'Жўнаш вақти кеч бўлгани учун рейс бугун яна сурилмайди. Янги кунга кўчиринг ёки тугатинг.' },
    uz_Latn: { title: '⏱ Reys avtomatik surilmaydi', body: 'Jo\'nash vaqti kech bo\'lgani uchun reys bugun yana surilmaydi. Yangi kunga ko\'chiring yoki tugating.' },
    ru: { title: '⏱ Рейс больше не переносится автоматически', body: 'Время отправления слишком позднее, поэтому рейс сегодня больше не переносится. Перенесите на другой день или завершите.' },
  },

  // ── Ҳайдовчи рейсни қўлда кўчирди (`rescheduleTaxiTrip`, audit H6, 2026-10). Матн PROPOSED —
  // эга тасдиқлайди (рус тили ҳам). `{date}` — КК.ОО, `{time}` — СС:ДД (Тошкент).
  reschedule_passenger: {
    uz_Cyrl: { title: '🕐 Рейс вақти ўзгарди', body: 'Рейс {date} куни соат {time} га кўчирилди. Қулай бўлмаса бронни бекор қилишингиз мумкин.' },
    uz_Latn: { title: '🕐 Reys vaqti o\'zgardi', body: 'Reys {date} kuni soat {time} ga ko\'chirildi. Qulay bo\'lmasa bronni bekor qilishingiz mumkin.' },
    ru: { title: '🕐 Время рейса изменилось', body: 'Отправление перенесено на {date}, {time}. Если неудобно, можно отменить бронь.' },
  },

  // ── Йўқолган посилка (AVA Logistics, D1, 2026-10-16). Матнлар PROPOSED — эга тасдиқлайди
  // (рус тили ҳам ҳали эга кўриб чиқмаган). `{amount}` — посилка қиймати G, `{left}` — қолган қарз.
  lost_customer_full: {
    uz_Cyrl: { title: 'Жўнатма йўқолди — пул қайтарилди', body: '{tracking} жўнатмаси йўқолган деб топилди. Посилка қиймати {amount} сўм ҳисобингизга қайтарилди. Етказиб бериш хизмати ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Jo\'natma yo\'qoldi — pul qaytarildi', body: '{tracking} jo\'natmasi yo\'qolgan deb topildi. Posilka qiymati {amount} so\'m hisobingizga qaytarildi. Yetkazib berish xizmati haqi qaytarilmaydi.' },
    ru: { title: 'Посылка утеряна — деньги возвращены', body: 'Посылка {tracking} признана утерянной. Стоимость посылки {amount} сум возвращена на ваш счёт. Плата за доставку не возвращается.' },
  },
  lost_customer_partial: {
    uz_Cyrl: { title: 'Жўнатма йўқолди — пул қисман қайтарилди', body: '{tracking} жўнатмаси йўқолган деб топилди. Посилка қийматидан {amount} сўм ҳисобингизга қайтарилди. Қолган {left} сўм курьер тўлаганидан кейин қўшилади. Етказиб бериш хизмати ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Jo\'natma yo\'qoldi — pul qisman qaytarildi', body: '{tracking} jo\'natmasi yo\'qolgan deb topildi. Posilka qiymatidan {amount} so\'m hisobingizga qaytarildi. Qolgan {left} so\'m kuryer to\'laganidan keyin qo\'shiladi. Yetkazib berish xizmati haqi qaytarilmaydi.' },
    ru: { title: 'Посылка утеряна — деньги возвращены частично', body: 'Посылка {tracking} признана утерянной. Из стоимости посылки {amount} сум возвращено на ваш счёт. Оставшиеся {left} сум будут добавлены после оплаты курьером. Плата за доставку не возвращается.' },
  },
  lost_customer_none: {
    uz_Cyrl: { title: 'Жўнатма йўқолди', body: '{tracking} жўнатмаси йўқолган деб топилди. Посилка қиймати ({amount} сўм) курьер тўлаганидан кейин ҳисобингизга қайтарилади. Етказиб бериш хизмати ҳақи қайтарилмайди.' },
    uz_Latn: { title: 'Jo\'natma yo\'qoldi', body: '{tracking} jo\'natmasi yo\'qolgan deb topildi. Posilka qiymati ({amount} so\'m) kuryer to\'laganidan keyin hisobingizga qaytariladi. Yetkazib berish xizmati haqi qaytarilmaydi.' },
    ru: { title: 'Посылка утеряна', body: 'Посылка {tracking} признана утерянной. Стоимость посылки ({amount} сум) будет возвращена на ваш счёт после оплаты курьером. Плата за доставку не возвращается.' },
  },
  lost_customer_payment: {
    uz_Cyrl: { title: 'Ҳисобингизга пул қўшилди', body: '{tracking} жўнатмаси бўйича {amount} сўм ҳисобингизга қайтарилди. Қолган: {left} сўм.' },
    uz_Latn: { title: 'Hisobingizga pul qo\'shildi', body: '{tracking} jo\'natmasi bo\'yicha {amount} so\'m hisobingizga qaytarildi. Qolgan: {left} so\'m.' },
    ru: { title: 'На ваш счёт поступили деньги', body: 'По посылке {tracking} на ваш счёт возвращено {amount} сум. Осталось: {left} сум.' },
  },
  lost_customer_done: {
    uz_Cyrl: { title: 'Посилка қиймати тўлиқ қайтарилди', body: '{tracking} жўнатмаси бўйича посилка қиймати тўлиқ қайтарилди (жами {total} сўм).' },
    uz_Latn: { title: 'Posilka qiymati to\'liq qaytarildi', body: '{tracking} jo\'natmasi bo\'yicha posilka qiymati to\'liq qaytarildi (jami {total} so\'m).' },
    ru: { title: 'Стоимость посылки возвращена полностью', body: 'По посылке {tracking} стоимость возвращена полностью (всего {total} сум).' },
  },
  lost_courier: {
    uz_Cyrl: { title: 'Жўнатма йўқолган деб белгиланди', body: '{tracking} жўнатмаси сизда йўқолган деб белгиланди. Ҳисобингиздан {taken} сўм ечилди. Қолган қарз: {left} сўм.' },
    uz_Latn: { title: 'Jo\'natma yo\'qolgan deb belgilandi', body: '{tracking} jo\'natmasi sizda yo\'qolgan deb belgilandi. Hisobingizdan {taken} so\'m yechildi. Qolgan qarz: {left} so\'m.' },
    ru: { title: 'Посылка отмечена как утерянная', body: 'Посылка {tracking} отмечена как утерянная у вас. С вашего счёта списано {taken} сум. Остаток долга: {left} сум.' },
  },

  // ── Мижоз тасдиғи («Олдим» / «Бердим», D2/D7, 2026-10-16). Курьер қадамини мижоз ўз қурилмасида
  // тасдиқлайди (`customer_confirm.js`). Матнлар PROPOSED — эга тасдиқлайди (рус тили ҳам).
  // Мижозга ички атамалар (LEG, зона, settlement…) кўрсатилмайди (45-банд).
  // `{summary}` — маҳсулот ва миқдор, `{amount}` — жами сўм (бўшлиқ билан).
  confirm_restaurant_received: {
    uz_Cyrl: { title: 'Буюртмани олдингизми?', body: 'Курьер буюртмани етказдим деб белгилади. Буюртмани олганингизни тасдиқланг.' },
    uz_Latn: { title: 'Buyurtmani oldingizmi?', body: 'Kuryer buyurtmani yetkazdim deb belgiladi. Buyurtmani olganingizni tasdiqlang.' },
    ru: { title: 'Вы получили заказ?', body: 'Курьер отметил, что доставил заказ. Подтвердите, что вы его получили.' },
  },
  // ── «Етказилмади» мижоз тасдиғи билан (эга, 2026-10-31). Матнлар PROPOSED — эга тасдиқлайди.
  confirm_restaurant_delivery_failed: {
    uz_Cyrl: { title: 'Курьер буюртмани етказа олмадими?', body: 'Курьер «етказиб бўлмади» деб белгилади. Буюртмани олмаган бўлсангиз, тасдиқланг. Олмоқчи бўлсангиз, «Олмоқчиман» тугмасини босинг.' },
    uz_Latn: { title: 'Kuryer buyurtmani yetkaza olmadimi?', body: 'Kuryer «yetkazib bo\'lmadi» deb belgiladi. Buyurtmani olmagan bo\'lsangiz, tasdiqlang. Olmoqchi bo\'lsangiz, «Olmoqchiman» tugmasini bosing.' },
    ru: { title: 'Курьер не смог доставить заказ?', body: 'Курьер отметил, что не смог доставить заказ. Если вы не получили заказ, подтвердите. Если хотите получить его, нажмите «Хочу получить».' },
  },
  restaurant_delivery_failed_decide: {
    uz_Cyrl: { title: 'Буюртма бўйича қарор керак', body: 'Курьер «етказиб бўлмади» деди, мижоз жавоб бермади. Буюртма етказилмадими ёки курьер етказишни давом эттирсинми — ҳал қилинг.' },
    uz_Latn: { title: 'Buyurtma bo\'yicha qaror kerak', body: 'Kuryer «yetkazib bo\'lmadi» dedi, mijoz javob bermadi. Buyurtma yetkazilmadimi yoki kuryer yetkazishni davom ettirsinmi — hal qiling.' },
    ru: { title: 'Нужно решение по заказу', body: 'Курьер сообщил, что не смог доставить заказ, а клиент не ответил. Решите: заказ не доставлен или курьер продолжает доставку.' },
  },
  restaurant_delivery_failed_final: {
    uz_Cyrl: { title: 'Буюртма етказилмади', body: 'Буюртма «етказилмади» деб ёпилди.' },
    uz_Latn: { title: 'Buyurtma yetkazilmadi', body: 'Buyurtma «yetkazilmadi» deb yopildi.' },
    ru: { title: 'Заказ не доставлен', body: 'Заказ закрыт как недоставленный.' },
  },
  courier_delivery_failed_final: {
    uz_Cyrl: { title: 'Буюртма ёпилди', body: '«Етказиб бўлмади» тасдиқланди. Кейинги буюртмага ўтишингиз мумкин.' },
    uz_Latn: { title: 'Buyurtma yopildi', body: '«Yetkazib bo\'lmadi» tasdiqlandi. Keyingi buyurtmaga o\'tishingiz mumkin.' },
    ru: { title: 'Заказ закрыт', body: 'Отметка «не удалось доставить» подтверждена. Можно переходить к следующему заказу.' },
  },
  customer_delivery_failed_final: {
    uz_Cyrl: { title: 'Буюртма етказилмади', body: 'Курьер буюртмани етказа олмади ва буюртма ёпилди.' },
    uz_Latn: { title: 'Buyurtma yetkazilmadi', body: 'Kuryer buyurtmani yetkaza olmadi va buyurtma yopildi.' },
    ru: { title: 'Заказ не доставлен', body: 'Курьер не смог доставить заказ, заказ закрыт.' },
  },
  courier_delivery_failed_continue: {
    uz_Cyrl: { title: 'Буюртмани етказинг', body: '«Етказиб бўлмади» қабул қилинмади: етказишни давом эттиринг.' },
    uz_Latn: { title: 'Buyurtmani yetkazing', body: '«Yetkazib bo\'lmadi» qabul qilinmadi: yetkazishni davom ettiring.' },
    ru: { title: 'Продолжите доставку', body: 'Отметка «не удалось доставить» не принята: продолжайте доставку.' },
  },
  customer_delivery_failed_continue: {
    uz_Cyrl: { title: 'Буюртма етказилади', body: 'Курьер буюртмангизни етказишни давом эттиради.' },
    uz_Latn: { title: 'Buyurtma yetkaziladi', body: 'Kuryer buyurtmangizni yetkazishni davom ettiradi.' },
    ru: { title: 'Заказ будет доставлен', body: 'Курьер продолжит доставку вашего заказа.' },
  },
  // ── «Етказилмади» — нон/бозор, гилам, сут, йиғиш (эга, 2026-10-31; delivery_failed.js).
  // Матнлар PROPOSED — эга тасдиқлайди. Курьерга якун/давом — юқоридаги умумий калитлар.
  confirm_order_delivery_failed: {
    uz_Cyrl: { title: 'Курьер буюртмани етказа олмадими?', body: 'Курьер «етказиб бўлмади» деб белгилади. Буюртмани олмаган бўлсангиз, тасдиқланг — ҳамёндан тўлаган бўлсангиз, пул қайтади. Олмоқчи бўлсангиз, «Олмоқчиман» тугмасини босинг.' },
    uz_Latn: { title: 'Kuryer buyurtmani yetkaza olmadimi?', body: 'Kuryer «yetkazib bo\'lmadi» deb belgiladi. Buyurtmani olmagan bo\'lsangiz, tasdiqlang — hamyondan to\'lagan bo\'lsangiz, pul qaytadi. Olmoqchi bo\'lsangiz, «Olmoqchiman» tugmasini bosing.' },
    ru: { title: 'Курьер не смог доставить заказ?', body: 'Курьер отметил, что не смог доставить заказ. Если вы его не получили, подтвердите — оплата с кошелька, если была, вернётся. Если хотите получить заказ, нажмите «Хочу получить».' },
  },
  confirm_carpet_pickup_failed: {
    uz_Cyrl: { title: 'Курьер гиламни ола олмадими?', body: 'Курьер «гиламни олиб бўлмади» деб белгилади. Тўғри бўлса, тасдиқланг — гилам кейинроқ олиб кетилади. Ҳозир бермоқчи бўлсангиз, «Ҳозир бераман» тугмасини босинг.' },
    uz_Latn: { title: 'Kuryer gilamni ola olmadimi?', body: 'Kuryer «gilamni olib bo\'lmadi» deb belgiladi. To\'g\'ri bo\'lsa, tasdiqlang — gilam keyinroq olib ketiladi. Hozir bermoqchi bo\'lsangiz, «Hozir beraman» tugmasini bosing.' },
    ru: { title: 'Курьер не смог забрать ковёр?', body: 'Курьер отметил, что не смог забрать ковёр. Если это так, подтвердите — ковёр заберут позже. Если хотите передать его сейчас, нажмите «Передам сейчас».' },
  },
  confirm_carpet_return_failed: {
    uz_Cyrl: { title: 'Курьер гиламни топшира олмадими?', body: 'Курьер «гиламни топшириб бўлмади» деб белгилади. Тўғри бўлса, тасдиқланг — гилам цехга қайтади ва қайта етказилади. Олмоқчи бўлсангиз, «Олмоқчиман» тугмасини босинг.' },
    uz_Latn: { title: 'Kuryer gilamni topshira olmadimi?', body: 'Kuryer «gilamni topshirib bo\'lmadi» deb belgiladi. To\'g\'ri bo\'lsa, tasdiqlang — gilam sexga qaytadi va qayta yetkaziladi. Olmoqchi bo\'lsangiz, «Olmoqchiman» tugmasini bosing.' },
    ru: { title: 'Курьер не смог вернуть ковёр?', body: 'Курьер отметил, что не смог передать ковёр. Если это так, подтвердите — ковёр вернётся в цех и будет доставлен повторно. Если хотите получить его, нажмите «Хочу получить».' },
  },
  confirm_agro_pickup_failed: {
    uz_Cyrl: { title: 'Курьер маҳсулотни ола олмадими?', body: 'Курьер «маҳсулотни олиб бўлмади» деб белгилади. Тўғри бўлса, тасдиқланг — маҳсулот кейинроқ олиб кетилади. Ҳозир бермоқчи бўлсангиз, «Ҳозир бераман» тугмасини босинг.' },
    uz_Latn: { title: 'Kuryer mahsulotni ola olmadimi?', body: 'Kuryer «mahsulotni olib bo\'lmadi» deb belgiladi. To\'g\'ri bo\'lsa, tasdiqlang — mahsulot keyinroq olib ketiladi. Hozir bermoqchi bo\'lsangiz, «Hozir beraman» tugmasini bosing.' },
    ru: { title: 'Курьер не смог забрать продукцию?', body: 'Курьер отметил, что не смог забрать продукцию. Если это так, подтвердите — её заберут позже. Если хотите передать её сейчас, нажмите «Передам сейчас».' },
  },
  confirm_collection_failed: {
    uz_Cyrl: { title: 'Курьер маҳсулотни ола олмадими?', body: 'Курьер «йиғиб олиш бўлмади» деб белгилади. Тўғри бўлса, тасдиқланг — админ янги вақт белгилайди. Ҳозир бермоқчи бўлсангиз, «Ҳозир бераман» тугмасини босинг.' },
    uz_Latn: { title: 'Kuryer mahsulotni ola olmadimi?', body: 'Kuryer «yig\'ib olish bo\'lmadi» deb belgiladi. To\'g\'ri bo\'lsa, tasdiqlang — admin yangi vaqt belgilaydi. Hozir bermoqchi bo\'lsangiz, «Hozir beraman» tugmasini bosing.' },
    ru: { title: 'Курьер не смог забрать продукцию?', body: 'Курьер отметил, что сбор не состоялся. Если это так, подтвердите — администратор назначит новое время. Если хотите передать продукцию сейчас, нажмите «Передам сейчас».' },
  },
  delivery_failed_decide: {
    uz_Cyrl: { title: 'Курьер вазифаси бўйича қарор керак', body: 'Курьер вазифани бажара олмаганини белгилади, мижоз жавоб бермади. «Етказилмади» ёки «Давом этсин» — ҳал қилинг.' },
    uz_Latn: { title: 'Kuryer vazifasi bo\'yicha qaror kerak', body: 'Kuryer vazifani bajara olmaganini belgiladi, mijoz javob bermadi. «Yetkazilmadi» yoki «Davom etsin» — hal qiling.' },
    ru: { title: 'Нужно решение по заданию курьера', body: 'Курьер отметил, что не смог выполнить задание, а клиент не ответил. Решите: «Не доставлено» или «Продолжить».' },
  },
  customer_order_delivery_failed_refund: {
    uz_Cyrl: { title: 'Буюртма етказилмади — пул қайтарилди', body: 'Буюртма бекор қилинди. Ҳамёндан тўланган {amount} сўм ҳисобингизга қайтарилди.' },
    uz_Latn: { title: 'Buyurtma yetkazilmadi — pul qaytarildi', body: 'Buyurtma bekor qilindi. Hamyondan to\'langan {amount} so\'m hisobingizga qaytarildi.' },
    ru: { title: 'Заказ не доставлен — деньги возвращены', body: 'Заказ отменён. Оплаченные с кошелька {amount} сум возвращены на ваш счёт.' },
  },
  customer_pickup_failed_final: {
    uz_Cyrl: { title: 'Курьер олиб кета олмади', body: 'Буюртмангиз қайта навбатга қўйилди — курьер қайта келади.' },
    uz_Latn: { title: 'Kuryer olib keta olmadi', body: 'Buyurtmangiz qayta navbatga qo\'yildi — kuryer qayta keladi.' },
    ru: { title: 'Курьер не смог забрать', body: 'Ваш заказ снова поставлен в очередь — курьер приедет ещё раз.' },
  },
  customer_carpet_return_failed_final: {
    uz_Cyrl: { title: 'Гилам топширилмади', body: 'Гиламингиз цехга қайтарилди ва қайта етказилади.' },
    uz_Latn: { title: 'Gilam topshirilmadi', body: 'Gilamingiz sexga qaytarildi va qayta yetkaziladi.' },
    ru: { title: 'Ковёр не передан', body: 'Ваш ковёр возвращён в цех и будет доставлен повторно.' },
  },
  customer_collection_failed_final: {
    uz_Cyrl: { title: 'Йиғиб олиш бўлмади', body: 'Курьер маҳсулотни ола олмади. Админ янги вақт белгилайди.' },
    uz_Latn: { title: 'Yig\'ib olish bo\'lmadi', body: 'Kuryer mahsulotni ola olmadi. Admin yangi vaqt belgilaydi.' },
    ru: { title: 'Сбор не состоялся', body: 'Курьер не смог забрать продукцию. Администратор назначит новое время.' },
  },
  // ── Топшириш (эга, 2026-10-31). Матнлар PROPOSED — эга тасдиқлайди.
  courier_handover_done: {
    uz_Cyrl: { title: 'Буюртма топширилди', body: 'Буюртма бошқа курьерга топширилди. Ҳақингиз масофа улушига қараб ҳисобланади.' },
    uz_Latn: { title: 'Buyurtma topshirildi', body: 'Buyurtma boshqa kuryerga topshirildi. Haqingiz masofa ulushiga qarab hisoblanadi.' },
    ru: { title: 'Заказ передан', body: 'Заказ передан другому курьеру. Ваша оплата рассчитывается по доле пройденного расстояния.' },
  },
  customer_courier_changed: {
    uz_Cyrl: { title: 'Курьер алмашди', body: 'Буюртмангизни энди бошқа курьер етказади.' },
    uz_Latn: { title: 'Kuryer almashdi', body: 'Buyurtmangizni endi boshqa kuryer yetkazadi.' },
    ru: { title: 'Курьер сменился', body: 'Ваш заказ теперь доставит другой курьер.' },
  },
  courier_return_done: {
    uz_Cyrl: { title: 'Буюртма ресторанга қайтарилди', body: 'Ресторан буюртмани қабул қилди.' },
    uz_Latn: { title: 'Buyurtma restoranga qaytarildi', body: 'Restoran buyurtmani qabul qildi.' },
    ru: { title: 'Заказ возвращён в ресторан', body: 'Ресторан принял заказ.' },
  },
  customer_no_courier_cancel: {
    uz_Cyrl: { title: 'Буюртма бекор қилинди', body: 'Буюртмангиз учун курьер топилмади, буюртма бекор қилинди.' },
    uz_Latn: { title: 'Buyurtma bekor qilindi', body: 'Buyurtmangiz uchun kuryer topilmadi, buyurtma bekor qilindi.' },
    ru: { title: 'Заказ отменён', body: 'Для вашего заказа не нашёлся курьер, заказ отменён.' },
  },
  customer_no_courier_cancel_prepaid: {
    uz_Cyrl: { title: 'Буюртма бекор қилинди', body: 'Буюртмангиз учун курьер топилмади, буюртма бекор қилинди. Олдиндан тўлаган пулингизни қайтариш учун ресторанга хабар берилди.' },
    uz_Latn: { title: 'Buyurtma bekor qilindi', body: 'Buyurtmangiz uchun kuryer topilmadi, buyurtma bekor qilindi. Oldindan to\'lagan pulingizni qaytarish uchun restoranga xabar berildi.' },
    ru: { title: 'Заказ отменён', body: 'Для вашего заказа не нашёлся курьер, заказ отменён. Ресторан уведомлён о возврате вашей предоплаты.' },
  },
  restaurant_no_courier_cancel: {
    uz_Cyrl: { title: 'Буюртма бекор қилинди', body: 'Қайтарилган буюртмага 30 дақиқада курьер топилмади. AVA ҳақи қайтарилди.' },
    uz_Latn: { title: 'Buyurtma bekor qilindi', body: 'Qaytarilgan buyurtmaga 30 daqiqada kuryer topilmadi. AVA haqi qaytarildi.' },
    ru: { title: 'Заказ отменён', body: 'Для возвращённого заказа за 30 минут не нашёлся курьер. Комиссия AVA возвращена.' },
  },
  restaurant_no_courier_cancel_prepaid: {
    uz_Cyrl: { title: 'Буюртма бекор қилинди — пулни қайтаринг', body: 'Қайтарилган буюртмага 30 дақиқада курьер топилмади. Мижоз олдиндан тўлаган — пулини мижозга қайтаринг. AVA ҳақи қайтарилди.' },
    uz_Latn: { title: 'Buyurtma bekor qilindi — pulni qaytaring', body: 'Qaytarilgan buyurtmaga 30 daqiqada kuryer topilmadi. Mijoz oldindan to\'lagan — pulini mijozga qaytaring. AVA haqi qaytarildi.' },
    ru: { title: 'Заказ отменён — верните деньги', body: 'Для возвращённого заказа за 30 минут не нашёлся курьер. Клиент внёс предоплату — верните ему деньги. Комиссия AVA возвращена.' },
  },
  confirm_carpet_pickup: {
    uz_Cyrl: { title: 'Гиламни курьерга бердингизми?', body: 'Курьер гиламни олдим деб белгилади. Гиламни курьерга берганингизни тасдиқланг.' },
    uz_Latn: { title: 'Gilamni kuryerga berdingizmi?', body: 'Kuryer gilamni oldim deb belgiladi. Gilamni kuryerga berganingizni tasdiqlang.' },
    ru: { title: 'Вы передали ковёр курьеру?', body: 'Курьер отметил, что забрал ковёр. Подтвердите, что вы передали ковёр курьеру.' },
  },
  confirm_carpet_return: {
    uz_Cyrl: { title: 'Гиламингизни олдингизми?', body: 'Курьер гиламни етказдим деб белгилади. Гиламни қайтиб олганингизни тасдиқланг.' },
    uz_Latn: { title: 'Gilamingizni oldingizmi?', body: 'Kuryer gilamni yetkazdim deb belgiladi. Gilamni qaytib olganingizni tasdiqlang.' },
    ru: { title: 'Вы получили ковёр обратно?', body: 'Курьер отметил, что доставил ковёр. Подтвердите, что вы получили его обратно.' },
  },
  confirm_agro_pickup: {
    uz_Cyrl: { title: 'Маҳсулотни курьерга бердингизми?', body: 'Курьер маҳсулотни олдим деб белгилади. Курьерга берганингизни тасдиқланг.' },
    uz_Latn: { title: 'Mahsulotni kuryerga berdingizmi?', body: 'Kuryer mahsulotni oldim deb belgiladi. Kuryerga berganingizni tasdiqlang.' },
    ru: { title: 'Вы передали продукцию курьеру?', body: 'Курьер отметил, что забрал продукцию. Подтвердите, что вы передали её курьеру.' },
  },
  confirm_collection_finalize: {
    uz_Cyrl: { title: 'Курьер ёзган миқдорни тасдиқлайсизми?', body: 'Курьер қуйидагини ёзди: {summary}. Жами: {amount} сўм. Тўғри бўлса, тасдиқланг — шундан кейин ҳисоб-китоб амалга ошади.' },
    uz_Latn: { title: 'Kuryer yozgan miqdorni tasdiqlaysizmi?', body: 'Kuryer quyidagini yozdi: {summary}. Jami: {amount} so\'m. To\'g\'ri bo\'lsa, tasdiqlang — shundan keyin hisob-kitob amalga oshadi.' },
    ru: { title: 'Подтверждаете количество, указанное курьером?', body: 'Курьер указал: {summary}. Итого: {amount} сум. Если всё верно, подтвердите — после этого будет произведён расчёт.' },
  },
};

/** Номаълум/бўш → `uz_Cyrl`. */
function normalizeLang(v) {
  const s = String(v || '');
  return LANGS.includes(s) ? s : DEFAULT_LANG;
}

function render(key, lang, params = {}) {
  const m = MESSAGES[key];
  if (!m) throw new Error(`notif_i18n: unknown key ${key}`);
  const t = m[normalizeLang(lang)];
  const fill = (s) => s.replace(/\{(\w+)\}/g, (_, k) => (params[k] === undefined ? `{${k}}` : String(params[k])));
  return { title: fill(t.title), body: fill(t.body) };
}

/** `users/{999…|9 рақам}` ҳужжатидан тил (бир марта ўқиш; хато — default). */
async function langOfPhone(db, phone) {
  const d = String(phone || '').replace(/\D/g, '');
  const ids = d.length === 9 ? [`998${d}`, d] : [d];
  for (const id of ids) {
    try {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) return normalizeLang((s.data() || {}).appLang);
    } catch (_) { /* default */ }
  }
  return DEFAULT_LANG;
}

/** `langOfPhone`нинг транзакция ичидаги варианти (ёзишдан ОЛДИН чақирилади). */
async function langOfPhoneTx(tx, db, phone) {
  const d = String(phone || '').replace(/\D/g, '');
  const ids = d.length === 9 ? [`998${d}`, d] : [d];
  for (const id of ids) {
    const s = await tx.get(db.collection('users').doc(id));
    if (s.exists) return normalizeLang((s.data() || {}).appLang);
  }
  return DEFAULT_LANG;
}

module.exports = { MESSAGES, LANGS, DEFAULT_LANG, normalizeLang, render, langOfPhone, langOfPhoneTx };

#!/usr/bin/env node
/**
 * Relatives moduli rel_* kalitlarini 3 ta til fayliga qo'shadi.
 * Ishlatish: node tools/merge_relatives_l10n.js
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');

/** @type {Record<string, { uz_Cyrl: string, uz_Latn: string, ru: string }>} */
const keys = {
  rel_title: {
    uz_Cyrl: 'Қариндошларим',
    uz_Latn: 'Qarindoshlarim',
    ru: 'Мои родственники',
  },
  rel_tab_list: {
    uz_Cyrl: 'Рўйхат',
    uz_Latn: 'Ro\'yxat',
    ru: 'Список',
  },
  rel_tab_tree: {
    uz_Cyrl: '🌳 Насаб дарахти',
    uz_Latn: '🌳 Nasab daraxti',
    ru: '🌳 Семейное дерево',
  },
  rel_tab_dates: {
    uz_Cyrl: '📅 Санalar',
    uz_Latn: '📅 Sanalar',
    ru: '📅 Даты',
  },
  rel_fab_add: {
    uz_Cyrl: 'Қариндош',
    uz_Latn: 'Qarindosh',
    ru: 'Родственник',
  },
  rel_tooltip_history: {
    uz_Cyrl: 'Дарахт тарихи',
    uz_Latn: 'Daraxt tarixi',
    ru: 'История дерева',
  },
  rel_tooltip_add_event: {
    uz_Cyrl: 'Сана / учрашuv қўшish',
    uz_Latn: 'Sana / uchrashuv qo\'shish',
    ru: 'Добавить дату / встречу',
  },
  rel_empty_list: {
    uz_Cyrl: 'Ҳали қариндош қўшмагансиз.',
    uz_Latn: 'Hali qarindosh qo\'shmadingiz.',
    ru: 'Вы ещё не добавили родственников.',
  },
  rel_empty_dates: {
    uz_Cyrl: 'Ҳали сана йўқ.\n⊕ тугмаси орқали учрашuv ёки муҳим сана қўшинг.',
    uz_Latn: 'Hali sana yo\'q.\n⊕ tugmasi orqali uchrashuv yoki muhim sana qo\'shing.',
    ru: 'Дат пока нет.\nДобавьте встречу или важную дату через кнопку ⊕.',
  },
  rel_me: {
    uz_Cyrl: 'Мен',
    uz_Latn: 'Men',
    ru: 'Я',
  },
  rel_age_years: {
    uz_Cyrl: '{count} ёш',
    uz_Latn: '{count} yosh',
    ru: '{count} лет',
  },
  rel_birthday_subtitle: {
    uz_Cyrl: '{date} · {age} ёшga to\'ldi',
    uz_Latn: '{date} · {age} yoshga to\'ldi',
    ru: '{date} · исполнится {age} лет',
  },
  rel_menu_album: {
    uz_Cyrl: '📷 Альбом',
    uz_Latn: '📷 Albom',
    ru: '📷 Альбом',
  },
  rel_today: {
    uz_Cyrl: 'Бугун!',
    uz_Latn: 'Bugun!',
    ru: 'Сегодня!',
  },
  rel_days_left: {
    uz_Cyrl: '{count} кун',
    uz_Latn: '{count} kun',
    ru: '{count} дн.',
  },
  rel_every_year: {
    uz_Cyrl: 'ҳар йили',
    uz_Latn: 'har yili',
    ru: 'ежегодно',
  },
  rel_side_paternal: {
    uz_Cyrl: 'Ота томон',
    uz_Latn: 'Ota tomon',
    ru: 'По отцу',
  },
  rel_side_maternal: {
    uz_Cyrl: 'Она томон',
    uz_Latn: 'Ona tomon',
    ru: 'По матери',
  },
  rel_phone_verify: {
    uz_Cyrl: 'Аввал профилда телефонни тасдиқланг.',
    uz_Latn: 'Avval profilda telefonni tasdiqlang.',
    ru: 'Сначала подтвердите телефон в профиле.',
  },
  rel_session_expired: {
    uz_Cyrl: 'Сессия tugadi. Ilovadan chiqib qayta kiring.',
    uz_Latn: 'Sessiya tugadi. Ilovadan chiqib qayta kiring.',
    ru: 'Сессия истекла. Выйдите из приложения и войдите снова.',
  },
  rel_session_phone_mismatch: {
    uz_Cyrl: 'Телефон sessiyasi profil bilan mos emas. Profildan telefonni qayta tasdiqlang.',
    uz_Latn: 'Telefon sessiyasi profil bilan mos emas. Profildan telefonni qayta tasdiqlang.',
    ru: 'Телефон сессии не совпадает с профилем. Подтвердите телефон в профиле снова.',
  },
  rel_session_refresh_failed: {
    uz_Cyrl: 'Сессия yangilanmadi. Qayta urinib ko\'ring.',
    uz_Latn: 'Sessiya yangilanmadi. Qayta urinib ko\'ring.',
    ru: 'Не удалось обновить сессию. Попробуйте снова.',
  },
  rel_delete_self_forbidden: {
    uz_Cyrl: '«Мен» ёзuvini o\'chirib bo\'lmaydi — bu sizning profilingiz.',
    uz_Latn: '«Men» yozuvini o\'chirib bo\'lmaydi — bu sizning profilingiz.',
    ru: 'Запись «Я» нельзя удалить — это ваш профиль.',
  },
  rel_delete_confirm_body: {
    uz_Cyrl: '«{name}» ni o\'chirasizmi?',
    uz_Latn: '«{name}» ni o\'chirasizmi?',
    ru: 'Удалить «{name}»?',
  },
  rel_deleted: {
    uz_Cyrl: '«{name}» o\'chirildi.',
    uz_Latn: '«{name}» o\'chirildi.',
    ru: '«{name}» удалён.',
  },
  rel_delete_denied: {
    uz_Cyrl: 'O\'chirishga ruxsat yo\'q. Telefonni profildan qayta tasdiqlang.',
    uz_Latn: 'O\'chirishga ruxsat yo\'q. Telefonni profildan qayta tasdiqlang.',
    ru: 'Нет прав на удаление. Подтвердите телефон в профиле снова.',
  },
  rel_delete_offline: {
    uz_Cyrl: 'Internet yo\'q. Ulanishni tekshirib qayta urinib ko\'ring.',
    uz_Latn: 'Internet yo\'q. Ulanishni tekshirib qayta urinib ko\'ring.',
    ru: 'Нет интернета. Проверьте подключение и попробуйте снова.',
  },
  rel_delete_error: {
    uz_Cyrl: 'O\'chirishda xato: {error}',
    uz_Latn: 'O\'chirishda xato: {error}',
    ru: 'Ошибка удаления: {error}',
  },
  rel_delete_i_confirm: {
    uz_Cyrl: 'Ўчираман',
    uz_Latn: 'O\'chiraman',
    ru: 'Удалить',
  },
  rel_form_add_title: {
    uz_Cyrl: 'Қариндош қўшиш',
    uz_Latn: 'Qarindosh qo\'shish',
    ru: 'Добавить родственника',
  },
  rel_form_self_hint: {
    uz_Cyrl: 'Исм, телефон, манзил ва туғилган сана profilingizdan avtomat sinxronlanadi. Bu yerda nasab bog\'lanishlarini tanlashingiz mumkin.',
    uz_Latn: 'Ism, telefon, manzil va tug\'ilgan sana profilingizdan avtomat sinxronlanadi. Bu yerda nasab bog\'lanishlarini tanlashingiz mumkin.',
    ru: 'Имя, телефон, адрес и дата рождения синхронизируются из профиля. Здесь можно выбрать родственные связи.',
  },
  rel_field_name: {
    uz_Cyrl: 'Исм-фамилия *',
    uz_Latn: 'Ism-familiya *',
    ru: 'ФИО *',
  },
  rel_field_degree: {
    uz_Cyrl: 'Қариндошлик даражаси (масalan: amaki)',
    uz_Latn: 'Qarindoshlik darajasi (masalan: amaki)',
    ru: 'Степень родства (например: дядя)',
  },
  rel_field_address: {
    uz_Cyrl: 'Манзил',
    uz_Latn: 'Manzil',
    ru: 'Адрес',
  },
  rel_field_birth: {
    uz_Cyrl: 'Туғилган сана',
    uz_Latn: 'Tug\'ilgan sana',
    ru: 'Дата рождения',
  },
  rel_field_gender: {
    uz_Cyrl: 'Жинс',
    uz_Latn: 'Jins',
    ru: 'Пол',
  },
  rel_field_side: {
    uz_Cyrl: 'Томон',
    uz_Latn: 'Tomon',
    ru: 'Линия',
  },
  rel_field_notes: {
    uz_Cyrl: 'Изоҳ',
    uz_Latn: 'Izoh',
    ru: 'Заметка',
  },
  rel_gender_none: {
    uz_Cyrl: 'Танланмаган',
    uz_Latn: 'Tanlanmagan',
    ru: 'Не выбран',
  },
  rel_gender_male: {
    uz_Cyrl: 'Эркак',
    uz_Latn: 'Erkak',
    ru: 'Мужской',
  },
  rel_gender_female: {
    uz_Cyrl: 'Аёл',
    uz_Latn: 'Ayol',
    ru: 'Женский',
  },
  rel_tree_links_section: {
    uz_Cyrl: '🌳 Насаб bog\'lanishi',
    uz_Latn: '🌳 Nasab bog\'lanishi',
    ru: '🌳 Родственные связи',
  },
  rel_father: {
    uz_Cyrl: 'Отаси',
    uz_Latn: 'Otasi',
    ru: 'Отец',
  },
  rel_mother: {
    uz_Cyrl: 'Онаси',
    uz_Latn: 'Onasi',
    ru: 'Мать',
  },
  rel_spouse: {
    uz_Cyrl: 'Турмуш ўртоғи',
    uz_Latn: 'Turmush o\'rtog\'i',
    ru: 'Супруг(а)',
  },
  rel_link_none: {
    uz_Cyrl: '— yo\'q —',
    uz_Latn: '— yo\'q —',
    ru: '— нет —',
  },
  rel_photo_upload_error: {
    uz_Cyrl: 'Rasm yuklashda xatolik: {error}',
    uz_Latn: 'Rasm yuklashda xatolik: {error}',
    ru: 'Ошибка загрузки фото: {error}',
  },
  rel_name_required: {
    uz_Cyrl: 'Ism-familiyani kiriting.',
    uz_Latn: 'Ism-familiyani kiriting.',
    ru: 'Введите имя и фамилию.',
  },
  rel_invite_empty: {
    uz_Cyrl: 'Kutilmayotgan ulash taklifi yo\'q.',
    uz_Latn: 'Kutilmayotgan ulash taklifi yo\'q.',
    ru: 'Нет ожидающих приглашений.',
  },
  rel_invite_sheet_title: {
    uz_Cyrl: 'Ulash takliflari',
    uz_Latn: 'Ulash takliflari',
    ru: 'Приглашения к связи',
  },
  rel_invite_body: {
    uz_Cyrl: '{from} sizni «{node}» sifatida o\'z daraxtiga ulashni taklif qilmoqda.',
    uz_Latn: '{from} sizni «{node}» sifatida o\'z daraxtiga ulashni taklif qilmoqda.',
    ru: '{from} предлагает связать вас с деревом как «{node}».',
  },
  rel_invite_from_default: {
    uz_Cyrl: 'Foydalanuvchi',
    uz_Latn: 'Foydalanuvchi',
    ru: 'Пользователь',
  },
  rel_invite_reject: {
    uz_Cyrl: 'Rad etish',
    uz_Latn: 'Rad etish',
    ru: 'Отклонить',
  },
  rel_invite_accept: {
    uz_Cyrl: 'Qabul qilish',
    uz_Latn: 'Qabul qilish',
    ru: 'Принять',
  },
  rel_invite_merged: {
    uz_Cyrl: '🎉 Daraxtlar birlashdi!',
    uz_Latn: '🎉 Daraxtlar birlashdi!',
    ru: '🎉 Деревья объединены!',
  },
  rel_invite_rejected: {
    uz_Cyrl: 'Taklif rad etildi.',
    uz_Latn: 'Taklif rad etildi.',
    ru: 'Приглашение отклонено.',
  },
  rel_invite_banner: {
    uz_Cyrl: '{count} ta ulash taklifi bor — ko\'rish uchun bosing',
    uz_Latn: '{count} ta ulash taklifi bor — ko\'rish uchun bosing',
    ru: '{count} приглаш. — нажмите, чтобы посмотреть',
  },
  rel_invite_tooltip: {
    uz_Cyrl: '{count} ta ulash taklifi',
    uz_Latn: '{count} ta ulash taklifi',
    ru: '{count} приглашений',
  },
  rel_invite_tooltip_empty: {
    uz_Cyrl: 'Ulash takliflari',
    uz_Latn: 'Ulash takliflari',
    ru: 'Приглашения к связи',
  },
  rel_event_add_title: {
    uz_Cyrl: 'Sana / uchrashuv',
    uz_Latn: 'Sana / uchrashuv',
    ru: 'Дата / встреча',
  },
  rel_event_edit_title: {
    uz_Cyrl: 'Sanani tahrirlash',
    uz_Latn: 'Sanani tahrirlash',
    ru: 'Редактировать дату',
  },
  rel_event_field_title: {
    uz_Cyrl: 'Nomi * (masalan: Nikoh yili)',
    uz_Latn: 'Nomi * (masalan: Nikoh yili)',
    ru: 'Название * (например: год свадьбы)',
  },
  rel_event_field_type: {
    uz_Cyrl: 'Turi',
    uz_Latn: 'Turi',
    ru: 'Тип',
  },
  rel_event_field_date: {
    uz_Cyrl: 'Sana *',
    uz_Latn: 'Sana *',
    ru: 'Дата *',
  },
  rel_event_repeat: {
    uz_Cyrl: 'Har yili takrorlanadi',
    uz_Latn: 'Har yili takrorlanadi',
    ru: 'Повторять каждый год',
  },
  rel_event_repeat_sub: {
    uz_Cyrl: 'Yil sanalari uchun (nikoh, xotira va h.k.)',
    uz_Latn: 'Yil sanalari uchun (nikoh, xotira va h.k.)',
    ru: 'Для годовщин (свадьба, память и т.д.)',
  },
  rel_event_place: {
    uz_Cyrl: 'Joy (ixtiyoriy)',
    uz_Latn: 'Joy (ixtiyoriy)',
    ru: 'Место (необязательно)',
  },
  rel_event_linked: {
    uz_Cyrl: 'Bog\'langan qarindoshlar',
    uz_Latn: 'Bog\'langan qarindoshlar',
    ru: 'Связанные родственники',
  },
  rel_event_title_required: {
    uz_Cyrl: 'Nomini kiriting.',
    uz_Latn: 'Nomini kiriting.',
    ru: 'Введите название.',
  },
  rel_event_date_required: {
    uz_Cyrl: 'Sanani tanlang.',
    uz_Latn: 'Sanani tanlang.',
    ru: 'Выберите дату.',
  },
  rel_event_type_meeting: {
    uz_Cyrl: 'Uchrashuv',
    uz_Latn: 'Uchrashuv',
    ru: 'Встреча',
  },
  rel_event_type_anniversary: {
    uz_Cyrl: 'Yil sanalari (nikoh va h.k.)',
    uz_Latn: 'Yil sanalari (nikoh va h.k.)',
    ru: 'Годовщины (свадьба и т.д.)',
  },
  rel_event_type_memorial: {
    uz_Cyrl: 'Xotira (yil oshi va h.k.)',
    uz_Latn: 'Xotira (yil oshi va h.k.)',
    ru: 'Память (годовщина смерти и т.д.)',
  },
  rel_event_type_other: {
    uz_Cyrl: 'Boshqa',
    uz_Latn: 'Boshqa',
    ru: 'Другое',
  },
  rel_history_title: {
    uz_Cyrl: 'Daraxt tarixi',
    uz_Latn: 'Daraxt tarixi',
    ru: 'История дерева',
  },
  rel_history_empty: {
    uz_Cyrl: 'Hozircha o\'zgarishlar tarixi bo\'sh.\nUlash yoki birlashtirish amallari shu yerda ko\'rinadi.',
    uz_Latn: 'Hozircha o\'zgarishlar tarixi bo\'sh.\nUlash yoki birlashtirish amallari shu yerda ko\'rinadi.',
    ru: 'История изменений пока пуста.\nЗдесь будут отображаться связи и объединения.',
  },
  rel_history_undone: {
    uz_Cyrl: '(qaytarilgan)',
    uz_Latn: '(qaytarilgan)',
    ru: '(отменено)',
  },
  rel_history_undo: {
    uz_Cyrl: 'Qaytarish',
    uz_Latn: 'Qaytarish',
    ru: 'Отменить',
  },
  rel_undo_title: {
    uz_Cyrl: 'Amalni qaytarish',
    uz_Latn: 'Amalni qaytarish',
    ru: 'Отменить действие',
  },
  rel_undo_body: {
    uz_Cyrl: '«{summary}» amalini qaytarmoqchimisiz?\nDaraxt amaldan oldingi holatiga qaytariladi.',
    uz_Latn: '«{summary}» amalini qaytarmoqchimisiz?\nDaraxt amaldan oldingi holatiga qaytariladi.',
    ru: 'Отменить действие «{summary}»?\nДерево вернётся к прежнему состоянию.',
  },
  rel_undo_confirm: {
    uz_Cyrl: 'Ha, qaytar',
    uz_Latn: 'Ha, qaytar',
    ru: 'Да, отменить',
  },
  rel_undo_done: {
    uz_Cyrl: 'Amal qaytarildi.',
    uz_Latn: 'Amal qaytarildi.',
    ru: 'Действие отменено.',
  },
  rel_history_type_link: {
    uz_Cyrl: '🔗 Ulash',
    uz_Latn: '🔗 Ulash',
    ru: '🔗 Связь',
  },
  rel_history_type_merge: {
    uz_Cyrl: '🔁 Birlashtirish',
    uz_Latn: '🔁 Birlashtirish',
    ru: '🔁 Объединение',
  },
  rel_history_type_edit: {
    uz_Cyrl: '✏️ Tahrir',
    uz_Latn: '✏️ Tahrir',
    ru: '✏️ Редактирование',
  },
  rel_history_type_create: {
    uz_Cyrl: '➕ Qo\'shildi',
    uz_Latn: '➕ Qo\'shildi',
    ru: '➕ Добавлено',
  },
  rel_album_empty: {
    uz_Cyrl: 'Hali rasm yo\'q.\nPastdagi tugma orqali rasm qo\'shing.',
    uz_Latn: 'Hali rasm yo\'q.\nPastdagi tugma orqali rasm qo\'shing.',
    ru: 'Фото пока нет.\nДобавьте через кнопку внизу.',
  },
  rel_album_add: {
    uz_Cyrl: 'Rasm qo\'shish',
    uz_Latn: 'Rasm qo\'shish',
    ru: 'Добавить фото',
  },
  rel_album_delete_title: {
    uz_Cyrl: 'Rasmni o\'chirish',
    uz_Latn: 'Rasmni o\'chirish',
    ru: 'Удалить фото',
  },
  rel_album_delete_body: {
    uz_Cyrl: 'Bu rasmni o\'chirasizmi?',
    uz_Latn: 'Bu rasmni o\'chirasizmi?',
    ru: 'Удалить это фото?',
  },
  rel_tree_export_label: {
    uz_Cyrl: 'Eksport:',
    uz_Latn: 'Eksport:',
    ru: 'Экспорт:',
  },
  rel_tree_export_image: {
    uz_Cyrl: 'Rasm',
    uz_Latn: 'Rasm',
    ru: 'Изображение',
  },
  rel_tree_export_share_opened: {
    uz_Cyrl: 'Ulashish oynasi ochildi.',
    uz_Latn: 'Ulashish oynasi ochildi.',
    ru: 'Окно «Поделиться» открыто.',
  },
  rel_tree_export_empty: {
    uz_Cyrl: 'Eksport uchun daraxtda kishi yo\'q.',
    uz_Latn: 'Eksport uchun daraxtda kishi yo\'q.',
    ru: 'В дереве нет людей для экспорта.',
  },
  rel_tree_export_capture_fail: {
    uz_Cyrl: 'Daraxt rasmini olish muvaffaqiyatsiz. Biroz kutib qayta urining.',
    uz_Latn: 'Daraxt rasmini olish muvaffaqiyatsiz. Biroz kutib qayta urining.',
    ru: 'Не удалось сделать снимок дерева. Подождите и попробуйте снова.',
  },
  rel_tree_dup_banner: {
    uz_Cyrl: '{count} ta ehtimoliy takror topildi — birlashtirish uchun bosing',
    uz_Latn: '{count} ta ehtimoliy takror topildi — birlashtirish uchun bosing',
    ru: 'Найдено {count} возможных дубликатов — нажмите для объединения',
  },
  rel_tree_dup_title: {
    uz_Cyrl: 'Ehtimoliy takrorlar',
    uz_Latn: 'Ehtimoliy takrorlar',
    ru: 'Возможные дубликаты',
  },
  rel_tree_dup_hint: {
    uz_Cyrl: 'Ism, tug\'ilgan sana va jins mos kelsa — bir xil odam bo\'lishi mumkin.',
    uz_Latn: 'Ism, tug\'ilgan sana va jins mos kelsa — bir xil odam bo\'lishi mumkin.',
    ru: 'Если совпадают имя, дата рождения и пол — возможно, это один человек.',
  },
  rel_tree_dup_group: {
    uz_Cyrl: '{label} — {count} ta',
    uz_Latn: '{label} — {count} ta',
    ru: '{label} — {count} чел.',
  },
  rel_tree_dup_linked: {
    uz_Cyrl: '✓ ulangan',
    uz_Latn: '✓ ulangan',
    ru: '✓ связан',
  },
  rel_tree_dup_merge: {
    uz_Cyrl: 'Birlashtirish',
    uz_Latn: 'Birlashtirish',
    ru: 'Объединить',
  },
  rel_tree_empty_hint: {
    uz_Cyrl: 'Daraxt bo\'sh.\nQarindoshni tahrirlab «Otasi» yoki «Onasi»ni belgilang.',
    uz_Latn: 'Daraxt bo\'sh.\nQarindoshni tahrirlab «Otasi» yoki «Onasi»ni belgilang.',
    ru: 'Дерево пусто.\nОтредактируйте родственника и укажите «Отец» или «Мать».',
  },
  rel_tree_merge_both_claimed: {
    uz_Cyrl: 'Ikkala tugun ham akkauntga ulangan — birlashtirib bo\'lmaydi.',
    uz_Latn: 'Ikkala tugun ham akkauntga ulangan — birlashtirib bo\'lmaydi.',
    ru: 'Оба узла связаны с аккаунтами — объединить нельзя.',
  },
  rel_tree_merge_title: {
    uz_Cyrl: 'Takrorlarni birlashtirish',
    uz_Latn: 'Takrorlarni birlashtirish',
    ru: 'Объединить дубликаты',
  },
  rel_tree_merge_body: {
    uz_Cyrl: '«{label}» — {count} ta tugun.\n\nBu bir xil odam deb ishonchingiz komilmi?\n«{keep}» saqlanadi, qolganlari o\'chiriladi.',
    uz_Latn: '«{label}» — {count} ta tugun.\n\nBu bir xil odam deb ishonchingiz komilmi?\n«{keep}» saqlanadi, qolganlari o\'chiriladi.',
    ru: '«{label}» — {count} узлов.\n\nВы уверены, что это один человек?\n«{keep}» сохранится, остальные удалятся.',
  },
  rel_tree_merge_success: {
    uz_Cyrl: '{count} ta tugun «{name}» bilan birlashtirildi.',
    uz_Latn: '{count} ta tugun «{name}» bilan birlashtirildi.',
    ru: '{count} узлов объединено с «{name}».',
  },
  rel_tree_merge_partial_error: {
    uz_Cyrl: 'Xato ({done} bajarildi): {error}',
    uz_Latn: 'Xato ({done} bajarildi): {error}',
    ru: 'Ошибка (выполнено {done}): {error}',
  },
  rel_node_claimed: {
    uz_Cyrl: '✓ Akkauntga ulangan',
    uz_Latn: '✓ Akkauntga ulangan',
    ru: '✓ Связан с аккаунтом',
  },
  rel_node_yours: {
    uz_Cyrl: 'Sizning ro\'yxatingiz',
    uz_Latn: 'Sizning ro\'yxatingiz',
    ru: 'Ваш список',
  },
  rel_node_edit_network: {
    uz_Cyrl: 'Tahrirlash (umumiy tarmoq)',
    uz_Latn: 'Tahrirlash (umumiy tarmoq)',
    ru: 'Редактировать (общая сеть)',
  },
  rel_node_edit_sub: {
    uz_Cyrl: 'Ism, sana, ota/ona/turmush o\'rtog\'i',
    uz_Latn: 'Ism, sana, ota/ona/turmush o\'rtog\'i',
    ru: 'Имя, дата, родители/супруг',
  },
  rel_node_link_account: {
    uz_Cyrl: 'Akkauntga ulash (telefon orqali)',
    uz_Latn: 'Akkauntga ulash (telefon orqali)',
    ru: 'Связать с аккаунтом (по телефону)',
  },
  rel_node_link_sub: {
    uz_Cyrl: 'U qabul qilsa, daraxtlar birlashadi',
    uz_Latn: 'U qabul qilsa, daraxtlar birlashadi',
    ru: 'При принятии деревья объединятся',
  },
  rel_node_personal: {
    uz_Cyrl: 'Shaxsiy ma\'lumotlar',
    uz_Latn: 'Shaxsiy ma\'lumotlar',
    ru: 'Личные данные',
  },
  rel_node_personal_sub: {
    uz_Cyrl: 'Telefon, manzil, izoh, fotoalbom',
    uz_Latn: 'Telefon, manzil, izoh, fotoalbom',
    ru: 'Телефон, адрес, заметка, фотоальбом',
  },
  rel_node_add_title: {
    uz_Cyrl: 'Yangi a\'zo qo\'shish',
    uz_Latn: 'Yangi a\'zo qo\'shish',
    ru: 'Добавить участника',
  },
  rel_node_edit_title: {
    uz_Cyrl: 'Tugunni tahrirlash',
    uz_Latn: 'Tugunni tahrirlash',
    ru: 'Редактировать узел',
  },
  rel_link_dialog_title: {
    uz_Cyrl: '«{name}» ni ulash',
    uz_Latn: '«{name}» ni ulash',
    ru: 'Связать «{name}»',
  },
  rel_link_dialog_body: {
    uz_Cyrl: 'Qarindoshingizning ilovadagi telefon raqamini kiriting. U qabul qilsa, daraxtlaringiz birlashadi.',
    uz_Latn: 'Qarindoshingizning ilovadagi telefon raqamini kiriting. U qabul qilsa, daraxtlaringiz birlashadi.',
    ru: 'Введите телефон родственника в приложении. При принятии деревья объединятся.',
  },
  rel_send: {
    uz_Cyrl: 'Yuborish',
    uz_Latn: 'Yuborish',
    ru: 'Отправить',
  },
  rel_link_already_sent: {
    uz_Cyrl: 'Taklif avval yuborilgan.',
    uz_Latn: 'Taklif avval yuborilgan.',
    ru: 'Приглашение уже отправлено.',
  },
  rel_link_sent: {
    uz_Cyrl: 'Taklif yuborildi.',
    uz_Latn: 'Taklif yuborildi.',
    ru: 'Приглашение отправлено.',
  },
};

const langMap = {
  uz_Cyrl: path.join(root, 'assets/lang/uz_Cyrl.json'),
  uz_Latn: path.join(root, 'assets/lang/uz_Latn.json'),
  ru: path.join(root, 'assets/lang/ru.json'),
};

let added = 0;
for (const [locale, filePath] of Object.entries(langMap)) {
  const obj = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  for (const [key, tr] of Object.entries(keys)) {
    if (obj[key] !== undefined) {
      console.warn(`WARN: overwriting ${key} in ${locale}`);
    }
    obj[key] = tr[locale];
    added++;
  }
  fs.writeFileSync(filePath, JSON.stringify(obj, null, 2) + '\n');
}

console.log(`Merged ${Object.keys(keys).length} rel_* keys into 3 locale files.`);

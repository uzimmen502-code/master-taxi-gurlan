/// «Туғилган кунингизни киритинг» ҳафталик эслатмаси (эга 2026-11-28, сервер `functions/birthday_prompt.js`).
///
/// Сервер `notifyUserInApp` орқали юборади: `admin_news.source` = FCM `data.type` = [kBirthdayPromptType],
/// `data.screen` = [kBirthdayPromptScreen]. Push ёки «Хабарлар»даги ёзув босилса — туғилган сана киритиладиган
/// мавжуд экран (`openUserInfoScreen`, бош саҳифа карточкаси ҳам шуни очади) очилади.
library;

const kBirthdayPromptType = 'birthday_prompt';
const kBirthdayPromptScreen = 'user_info';

/// Push data ёки хабар манбаи туғилган сана экранини очадими.
bool opensBirthDateEntry({String type = '', String screen = ''}) =>
    type.trim() == kBirthdayPromptType || screen.trim() == kBirthdayPromptScreen;

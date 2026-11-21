/// «Хабарлар»дан супермаркетга йўналтириш (2-босқич, сервер cd02561a): ҳафталик эслатма хабари
/// (`source: 'sm_weekly_reminder'`, `smListId`) → ўша рўйхат. Етишмовчилик хабари `category: 'order'` + `orderId` —
/// мавжуд буюртма гуруҳи орқали буюртма тафсилотига тушади (алоҳида код керак эмас).
library;

import '../../../models/message_thread_group.dart';
import '../../../models/news_item.dart';

const kSmWeeklyReminderSource = 'sm_weekly_reminder';

/// Инбокс қатори юкламаси ([NewsItem] ёки [MessageThreadGroup]) охирги хабари ҳафталик эслатма бўлса — рўйхат id
/// (номаълум бўлса `''` — рўйхатлар очилади); акс ҳолда `null`.
String? smWeeklyReminderListId(Object? payload) {
  NewsItem? last;
  if (payload is NewsItem) {
    last = payload;
  } else if (payload is MessageThreadGroup && payload.messages.isNotEmpty) {
    last = payload.messages.reduce((a, b) => b.createdAt.isAfter(a.createdAt) ? b : a);
  }
  if (last == null || last.source != kSmWeeklyReminderSource) return null;
  return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(last.smListId) ? last.smListId : '';
}

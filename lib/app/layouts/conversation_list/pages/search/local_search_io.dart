import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:collection/collection.dart';
import 'package:objectbox/src/native/query/query.dart' as obx;

import 'search_models.dart';

/// Native/desktop implementation of local, on-device message search via
/// ObjectBox. Not available on web — see `local_search_web.dart`.
Future<List<SearchResultItem>> runLocalSearch({
  required String term,
  required Chat? selectedChat,
  required Handle? selectedHandle,
  required bool isFromMe,
  required bool isNotFromMe,
  required DateTime? sinceDate,
}) async {
  obx.Condition<Message> condition = Message_.text
      .contains(term, caseSensitive: false)
      .and(Message_.associatedMessageGuid.isNull())
      .and(Message_.dateDeleted.isNull())
      .and(Message_.dateCreated.notNull());

  if (isFromMe) {
    condition = condition.and(Message_.isFromMe.equals(true));
  } else if (isNotFromMe) {
    condition = condition.and(Message_.isFromMe.equals(false));
  } else if (selectedHandle != null) {
    condition = condition.and(Message_.handleId.equals(selectedHandle.originalROWID!));
  }

  if (sinceDate != null) {
    condition = condition.and(Message_.dateCreated.greaterOrEqual(sinceDate.millisecondsSinceEpoch));
  }

  QueryBuilder<Message> qBuilder = Database.messages.query(condition);
  if (selectedChat != null) {
    qBuilder = qBuilder..link(Message_.chat, Chat_.guid.equals(selectedChat.guid));
  }

  final query = qBuilder.order(Message_.dateCreated, flags: Order.descending).build();
  query.limit = 50;
  final results = query.find();
  query.close();

  final messages = results.map((e) {
    e.realAttachments;
    e.fetchAssociatedMessages();
    return e;
  }).toList();
  final chats = results.map((e) => e.chat.target).toList();

  final items = <SearchResultItem>[];
  chats.forEachIndexed((index, chat) {
    if (chat == null) return;
    items.add(SearchResultItem(chat: chat, message: messages[index]));
  });
  return items;
}

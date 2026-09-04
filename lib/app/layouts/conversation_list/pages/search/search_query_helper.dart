import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';

import 'local_search_io.dart' if (dart.library.html) 'local_search_web.dart' as local_search;
import 'search_models.dart';

class SearchQueryHelper {
  static Future<List<SearchResultItem>> runLocal({
    required String term,
    required Chat? selectedChat,
    required Handle? selectedHandle,
    required bool isFromMe,
    required bool isNotFromMe,
    required DateTime? sinceDate,
  }) {
    return local_search.runLocalSearch(
      term: term,
      selectedChat: selectedChat,
      selectedHandle: selectedHandle,
      isFromMe: isFromMe,
      isNotFromMe: isNotFromMe,
      sinceDate: sinceDate,
    );
  }

  static Future<List<SearchResultItem>> runNetwork({
    required String term,
    required Chat? selectedChat,
    required Handle? selectedHandle,
    required bool isFromMe,
    required bool isNotFromMe,
    required DateTime? sinceDate,
  }) async {
    final whereClause = <Map<String, dynamic>>[
      {
        'statement': 'message.text LIKE :term COLLATE NOCASE',
        'args': {'term': "%$term%"}
      },
      {'statement': 'message.associated_message_guid IS NULL', 'args': null}
    ];

    if (selectedChat != null) {
      whereClause.add({
        'statement': 'chat.guid = :guid',
        'args': {'guid': selectedChat.guid}
      });
    }

    if (isFromMe) {
      whereClause.add({
        'statement': 'message.is_from_me = :isFromMe',
        'args': {'isFromMe': 1}
      });
    } else if (isNotFromMe) {
      whereClause.add({
        'statement': 'message.is_from_me = :isFromMe',
        'args': {'isFromMe': 0}
      });
    } else if (selectedHandle != null) {
      whereClause.add({
        'statement': 'handle.id = :addr',
        'args': {'addr': selectedHandle.address}
      });
    }

    final results = await MessagesService.getMessages(
      limit: 50,
      after: sinceDate?.millisecondsSinceEpoch,
      withChats: true,
      withHandles: true,
      withAttachments: true,
      withChatParticipants: true,
      where: whereClause,
    );

    final itemChats = <Chat>[];
    final itemMessages = <Message>[];
    for (final item in results) {
      itemChats.add(Chat.fromMap(item['chats'][0]));
      itemMessages.add(Message.fromMap(item));
    }

    final chatGuids = itemChats.map((e) => e.guid).toList();
    final dbChats = Database.chats.query(Chat_.guid.oneOf(chatGuids)).build().find();

    final items = <SearchResultItem>[];
    for (int i = 0; i < itemChats.length; i++) {
      final chat = dbChats.firstWhereOrNull((e) => e.guid == itemChats[i].guid) ?? itemChats[i];
      items.add(SearchResultItem(chat: chat, message: itemMessages[i]));
    }
    return items;
  }
}

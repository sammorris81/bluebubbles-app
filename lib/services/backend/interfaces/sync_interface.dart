import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/sync_actions.dart';
import 'package:bluebubbles/services/isolates/incremental_sync_isolate.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class SyncInterface {
  /// Unified sync: persists handles, chats, messages, and attachments from raw
  /// API maps. Replaces the three older bulk-sync entry points.
  static Future<({List<Message> messages, List<Chat> chats})> bulkSyncData({
    Map<String, dynamic>? chatData,
    required List<Map<String, dynamic>> messagesData,
  }) async {
    final data = {
      'chatData': chatData,
      'messagesData': messagesData,
    };

    if (kIsWeb) {
      // No local DB to hydrate IDs from on web — SyncActions.bulkSyncData
      // shortcuts to empty ID lists there, so parse straight from the raw
      // maps the caller already has instead of hitting the uninitialized
      // Database.messages/chats boxes (LateInitializationError). The only
      // web caller (MessagesService.loadChunk) only reads `.messages`.
      final messages = messagesData.map((e) => Message.fromMap(e)).toList();
      // Register with Message.findOne's in-memory index — otherwise a later
      // delivery/read receipt for one of these (loaded when the chat was
      // opened, not via the live incoming-message pipeline) can never find
      // its record and buffers forever. See IncomingMessageHandler.
      Message.registerKnown(messages);
      return (
        messages: messages,
        chats: <Chat>[],
      );
    }

    late Map<String, dynamic> result;
    if (isIsolate) {
      result = await SyncActions.bulkSyncData(data);
    } else {
      result = await GetIt.I<GlobalIsolate>().send<Map<String, dynamic>>(IsolateRequestType.bulkSyncData, input: data);
    }

    final messageIds = (result['messageIds'] as List).cast<int>();
    final chatIds = (result['chatIds'] as List).cast<int>();
    return (
      messages: Database.messages.getMany(messageIds).whereType<Message>().toList(),
      chats: Database.chats.getMany(chatIds).whereType<Chat>().toList(),
    );
  }

  /// Performs an incremental sync in the isolate.
  /// Returns the latest [Message] object per synced chat, hydrated from the local DB.
  /// Callers use these messages to update [ChatState] subtitles via [ChatsService].
  static Future<List<Message>> performIncrementalSync({bool useGlobalIsolate = false}) async {
    late List<int> messageIds = [];
    if (isIsolate) {
      messageIds = await SyncActions.performIncrementalSync({});
    } else {
      if (useGlobalIsolate) {
        messageIds =
            await GetIt.I<GlobalIsolate>().send<List<int>>(IsolateRequestType.performIncrementalSync, input: {});
      } else {
        messageIds = await GetIt.I<IncrementalSyncIsolate>()
            .send<List<int>>(IsolateRequestType.performIncrementalSync, input: {});
      }
    }

    return Database.messages.getMany(messageIds).whereType<Message>().toList();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:bluebubbles/services/backend/interfaces/chat_interface.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/html/attachment.dart';
import 'package:bluebubbles/database/html/handle.dart';
import 'package:bluebubbles/database/html/message.dart';
import 'package:bluebubbles/database/html/objectbox.dart';
import 'package:bluebubbles/models/message_save_result.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:faker/faker.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:universal_html/html.dart' as html;

/// Pin/mute/archive are purely local-device settings on every platform —
/// `Chat.saveAsync()` never makes a server call for them, even natively, it
/// only writes to the local ObjectBox DB. Web has no local DB, so without
/// this they silently reset on every page reload. Backed by `localStorage`,
/// scoped to this browser only (matching the fact that these settings are
/// already per-device, not account-wide, on every other platform).
class _WebChatOverrides {
  static const _key = 'bb_web_chat_overrides';

  static Map<String, dynamic> _readAll() {
    final raw = html.window.localStorage[_key];
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      Logger.warn('Failed to parse stored chat overrides, resetting', tag: 'WebChatOverrides');
      return {};
    }
  }

  static void save(Chat chat) {
    final all = _readAll();
    final override = <String, dynamic>{
      if (chat.isPinned == true) 'isPinned': true,
      if (chat.pinIndex != null) 'pinIndex': chat.pinIndex,
      if (chat.isArchived == true) 'isArchived': true,
      if (chat.muteType != null) 'muteType': chat.muteType,
      if (chat.muteArgs != null) 'muteArgs': chat.muteArgs,
    };
    if (override.isEmpty) {
      all.remove(chat.guid);
    } else {
      all[chat.guid] = override;
    }
    html.window.localStorage[_key] = jsonEncode(all);
  }

  static void apply(Chat chat) {
    final override = _readAll()[chat.guid] as Map<String, dynamic>?;
    if (override == null) return;
    chat.isPinned = override['isPinned'] as bool? ?? false;
    chat.pinIndex = override['pinIndex'] as int?;
    chat.isArchived = override['isArchived'] as bool? ?? false;
    chat.muteType = override['muteType'] as String?;
    chat.muteArgs = override['muteArgs'] as String?;
  }
}

String getFullChatTitle(Chat _chat) {
  String? title = "";
  if (isNullOrEmpty(_chat.displayName)) {
    List<String> titles = [];
    for (int i = 0; i < _chat.participants.length; i++) {
      // ignore: argument_type_not_assignable, return_of_invalid_type, invalid_assignment, for_in_of_invalid_element_type
      String? name = _chat.participants[i].displayName;

      if (_chat.participants.length > 1 && !name.isPhoneNumber) {
        name = name.trim().split(" ")[0];
      } else {
        name = name.trim();
      }

      titles.add(name);
    }

    if (titles.isEmpty) {
      title = _chat.chatIdentifier;
    } else if (titles.length == 1) {
      title = titles[0];
    } else if (titles.length <= 4) {
      title = titles.join(", ");
      int pos = title.lastIndexOf(", ");
      if (pos != -1) title = "${title.substring(0, pos)} & ${title.substring(pos + 2)}";
    } else {
      title = titles.sublist(0, 3).join(", ");
      title = "$title & ${titles.length - 3} others";
    }
  } else {
    title = _chat.displayName;
  }

  return title!;
}

class Chat {
  int? id;
  String guid;
  String? chatIdentifier;
  bool? isArchived;
  String? muteType;
  String? muteArgs;
  bool? isPinned;
  bool? hasUnreadMessage;
  String? title;

  String? displayName;
  List<Handle> participants = [];
  bool? autoSendReadReceipts = true;
  bool? autoSendTypingIndicators = true;
  String? textFieldText;
  List<String> textFieldAttachments = [];
  final dbLatestMessage = ToOne<Message>();
  DateTime? dbOnlyLatestMessageDate;

  void setLatestMessage(Message m) {
    dbLatestMessage.target = m;
    dbOnlyLatestMessageDate = m.dateCreated;
  }

  DateTime? dateDeleted;
  int? style;
  bool lockChatName;
  bool lockChatIcon;
  String? lastReadMessageGuid;
  String? customThemeLight;
  String? customThemeDark;

  /// See io/chat.dart — `wallpaperType`/`dynamicWallpaperId`/`dynamicWallpaperConfig`.
  String? wallpaperType;
  String? dynamicWallpaperId;
  String? dynamicWallpaperConfig;

  ChatServiceType get service => ChatServiceType.fromGuid(guid);

  final RxnString _customAvatarPath = RxnString();
  String? get customAvatarPath => _customAvatarPath.value;
  set customAvatarPath(String? s) => _customAvatarPath.value = s;
  void refreshCustomAvatar(String s) {
    _customAvatarPath.value = null;
    _customAvatarPath.value = s;
  }

  final RxnString _customBackgroundPath = RxnString();
  String? get customBackgroundPath => _customBackgroundPath.value;
  set customBackgroundPath(String? s) => _customBackgroundPath.value = s;

  final RxnInt _pinIndex = RxnInt();
  int? get pinIndex => _pinIndex.value;
  set pinIndex(int? i) => _pinIndex.value = i;

  final List<Handle> handles = [];

  RxDouble sendProgress = 0.0.obs;

  String? _fakeName;
  String get fakeName {
    if (_fakeName != null) return _fakeName!;
    final color = faker.color.color();
    final animal = faker.animal.name();
    _fakeName = "${color.capitalize} ${animal.capitalize}";
    return _fakeName!;
  }

  Chat({
    this.id,
    required this.guid,
    this.chatIdentifier,
    this.isArchived = false,
    this.isPinned = false,
    this.muteType,
    this.muteArgs,
    this.hasUnreadMessage = false,
    this.displayName,
    String? customAvatar,
    int? pinnedIndex,
    List<Handle>? participants,
    Message? latestMessage,
    this.autoSendReadReceipts = true,
    this.autoSendTypingIndicators = true,
    this.textFieldText,
    this.textFieldAttachments = const [],
    this.dateDeleted,
    this.style,
    this.lockChatName = false,
    this.lockChatIcon = false,
    this.lastReadMessageGuid,
    this.customThemeLight,
    this.customThemeDark,
    String? customBackground,
    this.wallpaperType,
    this.dynamicWallpaperId,
    this.dynamicWallpaperConfig,
  }) {
    customAvatarPath = customAvatar;
    customBackgroundPath = customBackground;
    pinIndex = pinnedIndex;
    if (textFieldAttachments.isEmpty) textFieldAttachments = [];
    this.participants = participants ?? [];
    // `handles` used to never get populated here, leaving `ChatsSvc.webCachedHandles`
    // (which several Handle lookups rely on) permanently empty on web.
    handles.addAll(this.participants);
    if (latestMessage != null) setLatestMessage(latestMessage);
  }

  factory Chat.fromMap(Map<String, dynamic> json) {
    final message = json['lastMessage'] != null ? Message.fromMap(json['lastMessage']) : null;
    final chat = Chat(
      id: json["ROWID"] ?? json["id"],
      guid: json["guid"],
      chatIdentifier: json["chatIdentifier"],
      isArchived: json['isArchived'] ?? false,
      muteType: json["muteType"],
      muteArgs: json["muteArgs"],
      isPinned: json["isPinned"] ?? false,
      hasUnreadMessage: json["hasUnreadMessage"] ?? false,
      latestMessage: message,
      displayName: json["displayName"],
      customAvatar: json['_customAvatarPath'],
      customBackground: json['_customBackgroundPath'],
      pinnedIndex: json['_pinIndex'],
      participants: (json['participants'] as List? ?? []).map((e) => Handle.fromMap(e)).toList(),
      autoSendReadReceipts: json["autoSendReadReceipts"] ?? true,
      autoSendTypingIndicators: json["autoSendTypingIndicators"] ?? true,
      dateDeleted: parseDate(json["dateDeleted"]),
      style: json["style"],
      lockChatName: json["lockChatName"] ?? false,
      lockChatIcon: json["lockChatIcon"] ?? false,
      lastReadMessageGuid: json["lastReadMessageGuid"],
      customThemeLight: json["customThemeLight"],
      customThemeDark: json["customThemeDark"],
      wallpaperType: json["wallpaperType"],
      dynamicWallpaperId: json["dynamicWallpaperId"],
      dynamicWallpaperConfig: json["dynamicWallpaperConfig"],
    );
    _WebChatOverrides.apply(chat);
    return chat;
  }

  Chat save({
    bool updateMuteType = false,
    bool updateMuteArgs = false,
    bool updateIsPinned = false,
    bool updatePinIndex = false,
    bool updateIsArchived = false,
    bool updateHasUnreadMessage = false,
    bool updateAutoSendReadReceipts = false,
    bool updateAutoSendTypingIndicators = false,
    bool updateCustomAvatarPath = false,
    bool updateTextFieldText = false,
    bool updateTextFieldAttachments = false,
    bool updateDisplayName = false,
    bool updateDateDeleted = false,
    bool updateLockChatName = false,
    bool updateLockChatIcon = false,
    bool updateLastReadMessageGuid = false,
  }) {
    _WebChatOverrides.save(this);
    // ignore: argument_type_not_assignable, return_of_invalid_type, invalid_assignment, for_in_of_invalid_element_type
    WebListeners.notifyChat(this);
    return this;
  }

  /// Mirrors io/chat.dart's `saveAsync`, which itself no-ops on web
  /// (`if (kIsWeb) return this;`) — shared, non-platform-conditional code
  /// calls this on both platforms, so it needs to exist here too.
  Future<Chat> saveAsync({
    bool updateMuteType = false,
    bool updateMuteArgs = false,
    bool updateIsPinned = false,
    bool updatePinIndex = false,
    bool updateIsArchived = false,
    bool updateHasUnreadMessage = false,
    bool updateAutoSendReadReceipts = false,
    bool updateAutoSendTypingIndicators = false,
    bool updateCustomAvatarPath = false,
    bool updateCustomBackgroundPath = false,
    bool updateTextFieldText = false,
    bool updateTextFieldAttachments = false,
    bool updateDisplayName = false,
    bool updateDateDeleted = false,
    bool updateLockChatName = false,
    bool updateLockChatIcon = false,
    bool updateLastReadMessageGuid = false,
    bool updateLatestMessage = false,
    bool updateCustomThemes = false,
    bool updateWallpaperSettings = false,
  }) async {
    _WebChatOverrides.save(this);
    return this;
  }

  Future<Chat> togglePinAsync(bool isPinned) async {
    this.isPinned = isPinned;
    pinIndex = null;
    await saveAsync(updateIsPinned: true, updatePinIndex: true);
    return this;
  }

  Future<Chat> toggleArchivedAsync(bool isArchived) async {
    isPinned = false;
    this.isArchived = isArchived;
    await saveAsync(updateIsPinned: true, updateIsArchived: true);
    return this;
  }

  /// Mirrors io/chat.dart — the DB write is a no-op on web (see [saveAsync]),
  /// but the server notification underneath still applies.
  Future<Chat> toggleMuteAsync(bool isMuted) async {
    muteType = isMuted ? "mute" : null;
    muteArgs = null;
    await saveAsync(updateMuteType: true, updateMuteArgs: true);
    return this;
  }

  Future<Chat> toggleAutoReadAsync(bool? autoSendReadReceipts) async {
    this.autoSendReadReceipts = autoSendReadReceipts;
    await saveAsync(updateAutoSendReadReceipts: true);
    if (autoSendReadReceipts ?? SettingsSvc.settings.privateMarkChatAsRead.value) {
      HttpSvc.chat.markRead(guid);
    }
    return this;
  }

  /// Mirrors io/chat.dart — the DB write is a no-op on web, but the
  /// notification-clearing and server mark-read/unread calls still apply.
  Future<Chat> toggleHasUnreadAsync(bool hasUnread,
      {bool force = false, bool clearLocalNotifications = true, bool privateMark = true}) async {
    if (hasUnreadMessage == hasUnread && !force) return this;
    hasUnreadMessage = hasUnread;
    await saveAsync(updateHasUnreadMessage: true);

    try {
      if (clearLocalNotifications && !hasUnread && id != null) {
        ChatInterface.clearNotificationForChat(
          chatId: id!,
          chatGuid: guid,
        );
      }
      if (privateMark && (autoSendReadReceipts ?? SettingsSvc.settings.privateMarkChatAsRead.value)) {
        ChatInterface.markChatReadUnread(
          chatGuid: guid,
          markAsRead: !hasUnread,
          shouldMarkOnServer: true,
        );
      }
    } catch (e, s) {
      Logger.error("Failed to mark chat as read on message add", error: e, trace: s);
    }

    return this;
  }

  Future<Chat> toggleAutoTypeAsync(bool? autoSendTypingIndicators) async {
    this.autoSendTypingIndicators = autoSendTypingIndicators;
    await saveAsync(updateAutoSendTypingIndicators: true);
    if (!(autoSendTypingIndicators ?? SettingsSvc.settings.privateSendTypingIndicators.value)) {
      unawaited(ChatInterface.stopTyping(chatGuid: guid));
    }
    return this;
  }

  Chat changeName(String? name) {
    displayName = name;
    return this;
  }

  /// Get a chat's title
  String getTitle() {
    if (isNullOrEmpty(displayName)) {
      title = getChatCreatorSubtitle();
    } else {
      title = displayName;
    }
    return title!;
  }

  /// Get a chat's title
  String getChatCreatorSubtitle() {
    // generate names for group chats or DMs
    List<String> titles =
        participants.map((e) => e.displayName.trim().split(isGroup ? " " : String.fromCharCode(65532)).first).toList();
    if (titles.isEmpty) {
      if (chatIdentifier!.startsWith("urn:biz")) {
        return "Business Chat";
      }
      return chatIdentifier!;
    } else if (titles.length == 1) {
      return titles[0];
    } else if (titles.length <= 4) {
      final _title = titles.join(", ");
      int pos = _title.lastIndexOf(", ");
      if (pos != -1) {
        return "${_title.substring(0, pos)} & ${_title.substring(pos + 2)}";
      } else {
        return _title;
      }
    } else {
      final _title = titles.take(3).join(", ");
      return "$_title & ${titles.length - 3} others";
    }
  }

  bool shouldMuteNotification(Message? message) {
    if (SettingsSvc.settings.filterUnknownSenders.value &&
        participants.length == 1 &&
        participants[0].contacts.isEmpty) {
      return true;
    } else if (SettingsSvc.settings.globalTextDetection.value.isNotEmpty) {
      List<String> text = SettingsSvc.settings.globalTextDetection.value.split(",");
      for (String s in text) {
        if (message?.text?.toLowerCase().contains(s.toLowerCase()) ?? false) {
          return false;
        }
      }
      return true;
    } else if (muteType == "mute") {
      return true;
    } else if (muteType == "mute_individuals") {
      List<String> individuals = muteArgs!.split(",");
      return individuals.contains(message?.handle?.address ?? "");
    } else if (muteType == "temporary_mute") {
      DateTime time = DateTime.parse(muteArgs!);
      bool shouldMute = DateTime.now().toLocal().difference(time).inSeconds.isNegative;
      if (!shouldMute) {
        toggleMute(false);
        muteType = null;
        muteArgs = null;
        save();
      }
      return shouldMute;
    } else if (muteType == "text_detection") {
      List<String> text = muteArgs!.split(",");
      for (String s in text) {
        if (message?.text?.toLowerCase().contains(s.toLowerCase()) ?? false) {
          return false;
        }
      }
      return true;
    }
    return !SettingsSvc.settings.notifyReactions.value &&
        ReactionTypes.toList().contains(message?.associatedMessageType ?? "");
  }

  static void unDelete(Chat chat) {
    return;
  }

  static void softDelete(Chat chat) {
    return;
  }

  Chat toggleHasUnread(bool hasUnread,
      {bool force = false, bool clearLocalNotifications = true, bool privateMark = true}) {
    if (hasUnreadMessage == hasUnread && !force) return this;
    if (!ChatsSvc.isChatActive(guid) || !hasUnread || force) {
      hasUnreadMessage = hasUnread;
      save(updateHasUnreadMessage: true);
    }

    try {
      if (privateMark &&
          SettingsSvc.settings.enablePrivateAPI.value &&
          SettingsSvc.settings.privateMarkChatAsRead.value) {
        if (!hasUnread && autoSendReadReceipts!) {
          HttpSvc.chat.markRead(guid);
        } else if (hasUnread) {
          HttpSvc.chat.markUnread(guid);
        }
      }
    } catch (_) {}

    return this;
  }

  Future<MessageSaveResult> addMessage(Message message,
      {bool changeUnreadStatus = true,
      bool checkForMessageText = true,
      bool clearNotificationsIfFromMe = true,
      List<Attachment> attachments = const []}) async {
    // Save the message
    Message? latest = dbLatestMessage.target;
    Message? newMessage;

    try {
      newMessage = message.save(chat: this);
    } catch (ex, stacktrace) {
      newMessage = Message.findOne(guid: message.guid);
      if (newMessage == null) {
        Logger.error("Failed to add message (GUID: ${message.guid}) to chat (GUID: $guid)",
            error: ex, trace: stacktrace);
      }
    }
    bool isNewer = false;

    // If the message was saved correctly, update this chat's latestMessage info,
    // but only if the incoming message's date is newer
    if ((newMessage?.id != null || kIsWeb) && checkForMessageText) {
      isNewer = message.dateCreated!.isAfter(latest?.dateCreated ?? DateTime.fromMillisecondsSinceEpoch(0)) ||
          (message.guid != latest?.guid && message.dateCreated == latest?.dateCreated);
      if (isNewer) {
        setLatestMessage(message);
        dateDeleted = null;
        // ignore: argument_type_not_assignable, return_of_invalid_type, invalid_assignment, for_in_of_invalid_element_type
        await ChatsSvc.addChat(this);
      }
    }

    // Save any attachments
    for (Attachment? attachment in message.attachments) {
      attachment!.save(newMessage);
    }
    for (Attachment attachment in attachments) {
      attachment.save(newMessage);
    }

    // Save the chat.
    // This will update the latestMessage info as well as update some
    // other fields that we want to "mimic" from the server
    save();

    // If the incoming message was newer than the "last" one, set the unread status accordingly
    if (checkForMessageText && changeUnreadStatus && isNewer) {
      // If the message is from me, mark it unread
      // If the message is not from the same chat as the current chat, mark unread
      if (message.isFromMe!) {
        toggleHasUnread(false, clearLocalNotifications: clearNotificationsIfFromMe, force: ChatsSvc.isChatActive(guid));
      } else if (!ChatsSvc.isChatActive(guid)) {
        toggleHasUnread(true);
      }
    }

    // If the message is for adding or removing participants,
    // we need to ensure that all of the chat participants are correct by syncing with the server
    if (message.isParticipantEvent && checkForMessageText) {
      serverSyncParticipants();
    }

    return MessageSaveResult(newMessage ?? message, isNewer);
  }

  void serverSyncParticipants() async {
    // Send message to server to get the participants
    // Send message to server to get the participants
    final chat = await ChatsSvc.fetchChat(guid);
    if (chat != null) {
      await chat.saveAsync();
    }
  }

  static int? count() {
    return null;
  }

  static List<Attachment> getAttachments(Chat chat, {int offset = 0, int limit = 25}) {
    return [];
  }

  Future<List<Attachment>> getAttachmentsAsync() async {
    return [];
  }

  static List<Message> getMessages(Chat chat,
      {int offset = 0, int limit = 25, bool includeDeleted = false, bool getDetails = false}) {
    return [];
  }

  static Future<List<Message>> getMessagesAsync(Chat chat,
      {int offset = 0,
      int limit = 25,
      bool includeDeleted = false,
      int? searchAround,
      Function? onSupplementalDataLoaded}) async {
    // TODO(web): unlike io/chat.dart, this never actually fetches message
    // history — a chat opened on web only ever shows messages that arrive
    // over the socket after it's opened. Calling the callback immediately
    // just keeps callers that wait on "phase 2 complete" from stalling.
    onSupplementalDataLoaded?.call();
    return [];
  }

  void webSyncParticipants() {
    // ignore: argument_type_not_assignable, return_of_invalid_type, invalid_assignment, for_in_of_invalid_element_type
    participants = ChatsSvc.webCachedHandles
        .where((e) => participants.map((e2) => e2.address).contains(e.address))
        .cast<Handle>()
        .toList();
  }

  Chat addParticipant(Handle participant) {
    participants.add(participant);
    _deduplicateParticipants();
    return this;
  }

  Chat removeParticipant(Handle participant) {
    participants.removeWhere((element) => participant.id == element.id);
    _deduplicateParticipants();
    return this;
  }

  void _deduplicateParticipants() {
    if (participants.isEmpty) return;
    final ids = participants.map((e) => e.address).toSet();
    participants.retainWhere((element) => ids.remove(element.address));
  }

  Chat togglePin(bool isPinned) {
    if (id == null) return this;
    this.isPinned = isPinned;
    _pinIndex.value = null;
    save();
    // ignore: argument_type_not_assignable, return_of_invalid_type, invalid_assignment, for_in_of_invalid_element_type
    ChatsSvc.updateChat(this);
    return this;
  }

  Chat toggleMute(bool isMuted) {
    if (id == null) return this;
    muteType = isMuted ? "mute" : null;
    muteArgs = null;
    save();
    // ignore: argument_type_not_assignable, return_of_invalid_type, invalid_assignment, for_in_of_invalid_element_type
    ChatsSvc.updateChat(this);
    return this;
  }

  Chat toggleArchived(bool isArchived) {
    if (id == null) return this;
    this.isArchived = isArchived;
    save();
    // ignore: argument_type_not_assignable, return_of_invalid_type, invalid_assignment, for_in_of_invalid_element_type
    ChatsSvc.updateChat(this);
    return this;
  }

  Chat toggleAutoRead(bool? autoSendReadReceipts) {
    if (id == null) return this;
    this.autoSendReadReceipts = autoSendReadReceipts;
    save(updateAutoSendReadReceipts: true);
    if (autoSendReadReceipts ?? SettingsSvc.settings.privateMarkChatAsRead.value) {
      HttpSvc.chat.markRead(guid);
    }
    return this;
  }

  Chat toggleAutoType(bool? autoSendTypingIndicators) {
    if (id == null) return this;
    this.autoSendTypingIndicators = autoSendTypingIndicators;
    save(updateAutoSendTypingIndicators: true);
    if (!(autoSendTypingIndicators ?? SettingsSvc.settings.privateSendTypingIndicators.value)) {
      unawaited(ChatInterface.stopTyping(chatGuid: guid));
    }
    return this;
  }

  static Future<Chat?> findOneWeb({String? guid, String? chatIdentifier}) async {
    if (guid != null) {
      return ChatsSvc.findChatByGuid(guid) as Chat;
    } else if (chatIdentifier != null) {
      return ChatsSvc.findChatByChatIdentifier(chatIdentifier) as Chat;
    }
    return null;
  }

  static Chat? findOne({String? guid, String? chatIdentifier}) {
    return null;
  }

  static List<Chat> getChats({int limit = 15, int offset = 0}) {
    throw Exception("Use socket to get chats on Web!");
  }

  /// Unlike io/chat.dart (which reads the local ObjectBox DB via an isolate
  /// action), there's no local DB on web — this fetches the same page of
  /// chats directly from the server's `/chat/query` endpoint instead.
  static Future<List<Chat>> getChatsAsync({int limit = 15, int offset = 0, List<int> ids = const []}) async {
    final response = await HttpSvc.chat.query(
      withQuery: const ["participants", "lastmessage"],
      offset: offset,
      limit: limit,
    );
    final List<dynamic> data = response.data['data'] ?? [];
    return data.map((e) => Chat.fromMap(e)).toList();
  }

  static Future<List<Chat>> syncLatestMessages(List<Chat> chats, bool toggleUnread) async {
    return chats;
  }

  static Future<List<Chat>> bulkSyncChats(List<Chat> chats) async {
    return chats;
  }

  static Future<List<Message>> bulkSyncMessages(Chat chat, List<Message> messages) async {
    return messages;
  }

  void clearTranscript() {
    return;
  }

  bool get isTextForwarding => guid.startsWith("SMS");

  bool get isSMS => false;

  bool get isIMessage => !isTextForwarding && !isSMS;

  bool get isGroup => participants.length > 1 || style == 43;

  Chat merge(Chat other) {
    id ??= other.id;
    _customAvatarPath.value ??= other._customAvatarPath.value;
    _pinIndex.value ??= other._pinIndex.value;
    autoSendReadReceipts ??= other.autoSendReadReceipts;
    autoSendTypingIndicators ??= other.autoSendTypingIndicators;
    textFieldText ??= other.textFieldText;
    if (textFieldAttachments.isEmpty) {
      textFieldAttachments.addAll(other.textFieldAttachments);
    }
    chatIdentifier ??= other.chatIdentifier;
    displayName ??= other.displayName;
    if (handles.isEmpty) {
      handles.addAll(other.handles);
    }
    if (participants.isEmpty) {
      participants.addAll(other.participants);
    }
    hasUnreadMessage ??= other.hasUnreadMessage;
    isArchived ??= other.isArchived;
    isPinned ??= other.isPinned;
    if (dbLatestMessage.target == null && other.dbLatestMessage.target != null) {
      setLatestMessage(other.dbLatestMessage.target!);
    }
    muteArgs ??= other.muteArgs;
    title ??= other.title;
    dateDeleted ??= other.dateDeleted;
    style ??= other.style;
    return this;
  }

  static int sort(Chat? a, Chat? b) {
    // If they both are pinned & ordered, reflect the order
    if (a!.isPinned! && b!.isPinned! && a.pinIndex != null && b.pinIndex != null) {
      return a.pinIndex!.compareTo(b.pinIndex!);
    }

    // If b is pinned & ordered, but a isn't either pinned or ordered, return accordingly
    if (b!.isPinned! && b.pinIndex != null && (!a.isPinned! || a.pinIndex == null)) return 1;
    // If a is pinned & ordered, but b isn't either pinned or ordered, return accordingly
    if (a.isPinned! && a.pinIndex != null && (!b.isPinned! || b.pinIndex == null)) return -1;

    // Compare when one is pinned and the other isn't
    if (!a.isPinned! && b.isPinned!) return 1;
    if (a.isPinned! && !b.isPinned!) return -1;

    // Compare the last message dates (negate to sort newest first)
    return -((a.dbOnlyLatestMessageDate ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(b.dbOnlyLatestMessageDate ?? DateTime.fromMillisecondsSinceEpoch(0)));
  }

  static Future<void> getIcon(Chat c, {bool force = false}) async {}

  Map<String, dynamic> toMap() => {
        "ROWID": id,
        "guid": guid,
        "chatIdentifier": chatIdentifier,
        "isArchived": isArchived!,
        "muteType": muteType,
        "muteArgs": muteArgs,
        "isPinned": isPinned!,
        "displayName": displayName,
        "participants": participants.map((item) => item.toMap()).toList(),
        "hasUnreadMessage": hasUnreadMessage!,
        "_customAvatarPath": _customAvatarPath.value,
        "_customBackgroundPath": _customBackgroundPath.value,
        "_pinIndex": _pinIndex.value,
        "autoSendReadReceipts": autoSendReadReceipts!,
        "autoSendTypingIndicators": autoSendTypingIndicators!,
        "dateDeleted": dateDeleted?.millisecondsSinceEpoch,
        "style": style,
        "lockChatName": lockChatName,
        "lockChatIcon": lockChatIcon,
        "lastReadMessageGuid": lastReadMessageGuid,
        "customThemeLight": customThemeLight,
        "customThemeDark": customThemeDark,
        "wallpaperType": wallpaperType,
        "dynamicWallpaperId": dynamicWallpaperId,
        "dynamicWallpaperConfig": dynamicWallpaperConfig,
      };
}

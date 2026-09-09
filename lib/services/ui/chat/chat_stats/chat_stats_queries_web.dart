import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/ui/chat/chat_stats/chat_stats_models.dart';

/// Web stub: Chat Stats queries the local ObjectBox database directly, which
/// doesn't exist on web. The "Chat Stats" menu entry is disabled on web
/// (`enabled: !kIsWeb` in `chat_options.dart`), so none of this should ever
/// actually run there — these all throw rather than fabricate misleading
/// zeroed-out stats.
class ChatStatsQueries {
  static Never _unsupported() => throw Exception('Chat Stats is not supported on web');

  static Map<int, List<int>> timestampsByParticipant(Chat chat, {int? sinceMillis}) => _unsupported();

  static List<int> participantHandleIds(Chat chat, {int? sinceMillis}) => _unsupported();

  static int unattributedCount(Chat chat, {int? sinceMillis}) => _unsupported();

  static List<int> readTimestamps(Chat chat, {int? sinceMillis}) => _unsupported();

  static int totalMessages(Chat chat) => _unsupported();

  static int sentCount(Chat chat) => _unsupported();

  static int receivedCount(Chat chat, {int? participantId}) => _unsupported();

  static int attachmentMessageCount(Chat chat, {int? sinceMillis}) => _unsupported();

  static int editedCount(Chat chat, {bool? fromMe, int? participantId}) => _unsupported();

  static List<({String type, int participantId})> reactions(Chat chat) => _unsupported();

  static List<String> attachmentMimeTypes(Chat chat) => _unsupported();

  static int messageCountForTier(Chat chat) => _unsupported();

  static double textCoverage(Chat chat) => _unsupported();

  static List<String> recentTexts(Chat chat, {required bool fromMe, int? limit, int? participantId}) =>
      _unsupported();

  static Map<int, List<int>> textLengthsByParticipant(Chat chat, {int? sinceMillis, int? limitPerParticipant}) =>
      _unsupported();

  static List<String> expressiveSendStyleIds(Chat chat) => _unsupported();

  static int unsentCount(Chat chat, {bool? fromMe, int? participantId}) => _unsupported();

  static ({int sent, int received, double? playedOfReceived}) audioStats(Chat chat) => _unsupported();

  static List<GroupEventRecord> groupEvents(Chat chat) => _unsupported();

  static ({List<ReactionMatrixRow> reactionRows, Map<String, int> guidToSender}) reactionMatrixData(
    Chat chat, {
    required int sinceMillis,
  }) =>
      _unsupported();

  static int? firstMessageMillis(Chat chat) => _unsupported();

  static ({int count, int latestMillis}) cacheKey(Chat chat) => _unsupported();
}

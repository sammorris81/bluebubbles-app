import 'package:bluebubbles/database/models.dart';

import 'search_models.dart';

/// Web stub: there is no local ObjectBox database on web, so on-device
/// search isn't available. `search_view.dart` hides the "search locally"
/// toggle on web (see its `!kIsWeb` check), so this should never be reached
/// at runtime there.
Future<List<SearchResultItem>> runLocalSearch({
  required String term,
  required Chat? selectedChat,
  required Handle? selectedHandle,
  required bool isFromMe,
  required bool isNotFromMe,
  required DateTime? sinceDate,
}) async {
  return [];
}

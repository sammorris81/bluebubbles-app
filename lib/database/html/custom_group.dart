import 'package:bluebubbles/database/html/chat.dart';
import 'package:bluebubbles/database/html/objectbox.dart';

/// Web stub mirroring `lib/database/io/custom_group.dart`'s public API,
/// backed by an in-memory `ToMany` instead of an ObjectBox relation.
class CustomGroup {
  int? id;
  String name;
  int sortOrder;
  bool showUnreadBadge;

  final chats = ToMany<Chat>();

  CustomGroup({
    this.id,
    required this.name,
    this.sortOrder = 0,
    this.showUnreadBadge = true,
  });

  factory CustomGroup.fromMap(Map<String, dynamic> json) => CustomGroup(
        id: json["id"] as int?,
        name: json["name"] as String,
        sortOrder: json["sortOrder"] as int? ?? 0,
        showUnreadBadge: json["showUnreadBadge"] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        "id": id,
        "name": name,
        "sortOrder": sortOrder,
        "showUnreadBadge": showUnreadBadge,
      };
}

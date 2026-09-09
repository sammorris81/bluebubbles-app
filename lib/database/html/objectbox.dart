// ignore_for_file: camel_case_types
import 'package:bluebubbles/database/html/attachment.dart';
import 'package:bluebubbles/database/html/handle.dart';

/// READ: Dummy file to allow objectbox related code to compile on Web. We use
/// conditional imports at compile time, so any references to objectbox stuff
/// in [database.dart], [main.dart] and [background_isolate.dart] will error if
/// this file is removed. The below classes and methods are the ones that those
/// files use, in case we need to add more objectbox functionality to those files,
/// the new classes/methods must be added here.

/// Configure transaction mode. Used with [Store.runInTransaction()].
enum TxMode {
  read,
  write,
}

/// Box put (write) mode.
enum PutMode {
  /// Insert (if given object's ID is zero) or update an existing object.
  put,

  /// Insert a new object.
  insert,

  /// Update an existing object, fails if the given ID doesn't exist.
  update,
}

class Order {
  /// Reverts the order from ascending (default) to descending.
  static const descending = 1;

  /// Sorts upper case letters (e.g. 'Z') before lower case letters (e.g. 'a').
  /// If not specified, the default is case insensitive for ASCII characters.
  static const caseSensitive = 2;

  /// For integers only: changes the comparison to unsigned. The default is
  /// signed, unless the property is annotated with [@Property(signed: false)].
  static const unsigned = 4;

  /// null values will be put last.
  /// If not specified, by default null values will be put first.
  static const nullsLast = 8;

  /// null values should be treated equal to zero (scalars only).
  static const nullsAsZero = 16;
}

class Box<T> {
  int put(T object, {PutMode mode = PutMode.put}) => throw Exception('Unsupported Platform');

  /// Puts the given [objects] into this Box in a single transaction.
  ///
  /// Returns a list of all IDs of the inserted Objects.
  List<int> putMany(List<T> objects, {PutMode mode = PutMode.put}) => throw Exception('Unsupported Platform');

  /// Retrieves the stored object with the ID [id] from this box's database.
  /// Returns null if an object with the given ID doesn't exist.
  T? get(int id) => throw Exception('Unsupported Platform');

  /// Returns all stored objects in this Box.
  List<T> getAll() => throw Exception('Unsupported Platform');

  /// Returns a list of [ids.length] Objects of type T, each corresponding to
  /// the location of its ID in [ids]. Non-existent IDs become null.
  ///
  /// Pass growableResult: true for the resulting list to be growable.
  List<T?> getMany(List<int> ids, {bool growableResult = false}) => throw Exception('Unsupported Platform');

  /// Removes (deletes) the Object with the given [id]. Returns whether that
  /// ID existed (and thus was removed).
  bool remove(int id) => throw Exception('Unsupported Platform');

  /// Removes (deletes) by ID, returning a list of IDs of all removed Objects.
  int removeMany(List<int> ids) => throw Exception('Unsupported Platform');

  /// Removes (deletes) ALL Objects in a single transaction.
  int removeAll() => throw Exception('Unsupported Platform');

  bool isEmpty() => throw Exception('Unsupported Platform');

  int count() => throw Exception('Unsupported Platform');

  dynamic query([dynamic qc]) => throw Exception('Unsupported Platform');
}

/// Minimal in-memory stand-in for ObjectBox's `ToOne<T>` relation. There's no
/// real DB on web, so this just holds whatever was last assigned — it used to
/// be a pure no-op (`target` always `null`, `target =` discarded), which
/// silently broke every relation that goes through it (e.g.
/// `Attachment.message`, `Message.chat`, `Message.handleRelation`).
class ToOne<EntityT> {
  EntityT? _target;

  EntityT? get target => _target;

  set target(EntityT? object) => _target = object;

  int get targetId => 0;

  bool get hasValue => target != null;
}

/// Minimal in-memory stand-in for ObjectBox's `ToMany<T>` relation list.
/// Unlike the other stubs in this file (which throw, since there's no real
/// DB on web), this actually holds items in memory so shared, non-web-aware
/// UI code that reads a `ToMany` field (e.g. `CustomGroup.chats`) still works.
class ToMany<EntityT> extends Iterable<EntityT> {
  final List<EntityT> _items = [];

  @override
  Iterator<EntityT> get iterator => _items.iterator;

  void add(EntityT item) => _items.add(item);

  void addAll(Iterable<EntityT> items) => _items.addAll(items);

  bool remove(EntityT item) => _items.remove(item);

  void clear() => _items.clear();

  /// No-op on web: there's no DB to persist the relation to.
  void applyToDb() {}
}

class Store {
  static bool isOpen(String directoryPath) => throw Exception('Unsupported Platform');

  Box<T> box<T>() => throw Exception('Unsupported Platform');

  R runInTransaction<R>(TxMode mode, R Function() fn) => throw Exception('Unsupported Platform');

  void close() => throw Exception('Unsupported Platform');

  dynamic get reference => throw Exception('Unsupported Platform');

  Store.fromReference(dynamic _, dynamic _);

  Store.attach(dynamic _, String? directoryPath, {bool queriesCaseSensitiveDefault = true});
}

class Query<T> {
  set offset(int offset) {}

  set limit(int limit) {}

  /// Returns the number of matching Objects.
  int count() {
    return 0;
  }

  /// Close the query and free resources.
  void close() {}

  /// Finds the first object matching the query. Returns null if there are no
  /// results. Note: [offset] and [limit] are respected, if set.
  T? findFirst() {
    return null;
  }

  /// Finds the only object matching the query. Returns null if there are no
  /// results or throws if there are multiple objects matching.
  ///
  /// Note: [offset] and [limit] are respected, if set. Because [limit] affects
  /// the number of matched objects, make sure you leave it at zero or set it
  /// higher than one, otherwise the check for non-unique result won't work.
  T? findUnique() {
    return null;
  }

  /// Finds Objects matching the query.
  List<T> find() {
    return [];
  }
}

/// Stand-in for ObjectBox's `Condition<T>`/`QueryProperty<T>` family. There's
/// no real query engine on web, so every operator just returns `this` for
/// further chaining — actually running a query still throws (`Box.query()`),
/// this only exists so query-building code type-checks.
class Temp {
  dynamic add(dynamic thing) => this;

  dynamic equals(dynamic thing, {bool caseSensitive = true}) => this;

  dynamic notEquals(dynamic thing, {bool caseSensitive = true}) => this;

  dynamic oneOf(dynamic thing, {bool caseSensitive = true}) => this;

  dynamic notOneOf(dynamic thing, {bool caseSensitive = true}) => this;

  dynamic contains(dynamic thing, {bool caseSensitive = true}) => this;

  dynamic startsWith(dynamic thing, {bool caseSensitive = true}) => this;

  dynamic endsWith(dynamic thing, {bool caseSensitive = true}) => this;

  dynamic greaterThan(dynamic thing) => this;

  dynamic lessThan(dynamic thing) => this;

  dynamic greaterOrEqual(dynamic thing) => this;

  dynamic lessOrEqual(dynamic thing) => this;

  dynamic between(dynamic a, dynamic b) => this;

  dynamic isNull() => this;

  dynamic notNull() => this;

  dynamic and(dynamic other) => this;

  dynamic or(dynamic other) => this;

  dynamic operator &(dynamic other) => this;

  dynamic operator |(dynamic other) => this;
}

/// These are real ObjectBox types on native; on web every query property,
/// condition, and query builder just degrades to [Temp] (or dynamic).
typedef Condition<T> = Temp;
typedef QueryIntegerProperty<T> = Temp;
typedef QueryStringProperty<T> = Temp;
typedef QueryBooleanProperty<T> = Temp;
typedef QueryBuilder<T> = dynamic;

class Attachment_ {
  static final id = Temp();

  static final originalROWID = Temp();

  static final guid = Temp();

  static final uti = Temp();

  static final mimeType = Temp();

  static final isOutgoing = Temp();

  static final transferName = Temp();

  static final totalBytes = Temp();

  static final height = Temp();

  static final width = Temp();

  static final hasLivePhoto = Temp();

  static final message = Temp();
}

/// [Chat] entity fields to define ObjectBox queries.
class Chat_ {
  static final id = Temp();

  static final guid = Temp();

  static final dateDeleted = Temp();

  static final hasUnreadMessage = Temp();

  static final muteType = Temp();

  static final dbOnlyLatestMessageDate = Temp();
}

class Contact_ {
  static final displayName = Temp();
}

class ContactV2_ {
  static final nativeContactId = Temp();

  static final displayName = Temp();
}

class Handle_ {
  static final address = Temp();

  static final uniqueAddressAndService = Temp();

  static final originalROWID = Temp();

  static final service = Temp();
}

class ThemeStruct_ {
  static final name = Temp();
}

class Message_ {
  /// see [Message.id]
  static final id = Temp();

  /// see [Message.originalROWID]
  static final originalROWID = Temp();

  /// see [Message.guid]
  static final guid = Temp();

  /// see [Message.handleId]
  static final handleId = Temp();

  /// see [Message.otherHandle]
  static final otherHandle = Temp();

  /// see [Message.text]
  static final text = Temp();

  /// see [Message.subject]
  static final subject = Temp();

  /// see [Message.country]
  static final country = Temp();

  /// see [Message.dateCreated]
  static final dateCreated = Temp();

  /// see [Message.dateRead]
  static final dateRead = Temp();

  /// see [Message.dateDelivered]
  static final dateDelivered = Temp();

  /// see [Message.isFromMe]
  static final isFromMe = Temp();

  /// see [Message.hasDdResults]
  static final hasDdResults = Temp();

  /// see [Message.datePlayed]
  static final datePlayed = Temp();

  /// see [Message.itemType]
  static final itemType = Temp();

  /// see [Message.groupTitle]
  static final groupTitle = Temp();

  /// see [Message.groupActionType]
  static final groupActionType = Temp();

  /// see [Message.balloonBundleId]
  static final balloonBundleId = Temp();

  /// see [Message.associatedMessageGuid]
  static final associatedMessageGuid = Temp();

  /// see [Message.associatedMessageType]
  static final associatedMessageType = Temp();

  /// see [Message.expressiveSendStyleId]
  static final expressiveSendStyleId = Temp();

  /// see [Message.hasAttachments]
  static final hasAttachments = Temp();

  /// see [Message.hasReactions]
  static final hasReactions = Temp();

  /// see [Message.dateDeleted]
  static final dateDeleted = Temp();

  /// see [Message.threadOriginatorGuid]
  static final threadOriginatorGuid = Temp();

  /// see [Message.threadOriginatorPart]
  static final threadOriginatorPart = Temp();

  /// see [Message.bigEmoji]
  static final bigEmoji = Temp();

  /// see [Message.error]
  static final error = Temp();

  /// see [Message.chat]
  static final chat = Temp();

  /// see [Message.handleRelation]
  static final handleRelation = Temp();

  /// see [Message.dbAttributedBody]
  static final dbAttributedBody = Temp();

  /// see [Message.associatedMessagePart]
  static final associatedMessagePart = Temp();

  /// see [Message.hasApplePayloadData]
  static final hasApplePayloadData = Temp();

  /// see [Message.dateEdited]
  static final dateEdited = Temp();

  /// see [Message.dbMessageSummaryInfo]
  static final dbMessageSummaryInfo = Temp();

  /// see [Message.dbPayloadData]
  static final dbPayloadData = Temp();

  /// see [Message.dbMetadata]
  static final dbMetadata = Temp();

  /// see [Message.isBookmarked]
  static final isBookmarked = Temp();
}

Future<Store> openStore(
        {String? directory,
        int? maxDBSizeInKB,
        int? fileMode,
        int? maxReaders,
        bool queriesCaseSensitiveDefault = true,
        String? macosApplicationGroup}) async =>
    throw Exception('Unsupported Platform');

dynamic getObjectBoxModel() => throw Exception('Unsupported Platform');

extension ObjectboxShims on List<Handle> {
  void applyToDb() {}
}

extension ObjectboxAttachmentShims on List<Attachment> {
  void applyToDb() {}
}

/// Real ObjectBox throws this from `Box.put()` on a `@Unique()` conflict.
/// Never actually thrown on web (there's no DB to violate a constraint on),
/// but several shared action files catch it by type.
class UniqueViolationException implements Exception {}

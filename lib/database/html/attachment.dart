import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/html/message.dart';
import 'package:bluebubbles/database/html/objectbox.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:mime_type/mime_type.dart';
import 'package:passkit/passkit.dart';

class Attachment {
  int? id;
  int? originalROWID;
  String? guid;
  String? uti;
  String? mimeType;
  bool? isOutgoing;
  String? transferName;
  int? totalBytes;
  int? height;
  int? width;
  Uint8List? bytes;
  String? webUrl;
  Map<String, dynamic>? metadata;
  Map<String, dynamic>? exif;
  bool hasLivePhoto;
  bool isDownloaded;

  final message = ToOne<Message>();

  Attachment({
    this.id,
    this.originalROWID,
    this.guid,
    this.uti,
    this.mimeType,
    this.isOutgoing,
    this.transferName,
    this.totalBytes,
    this.height,
    this.width,
    this.metadata,
    this.exif,
    this.bytes,
    this.webUrl,
    this.hasLivePhoto = false,
    this.isDownloaded = false,
  });

  static Future<Attachment?> findOneAsync(String guid) async => null;

  static Future<List<Attachment>> findAsync({dynamic queryDescriptor}) async => [];

  /// Mirrors io/attachment.dart, which itself no-ops on web
  /// (`if (kIsWeb) return this/newAttachment;`) — the real behavior is local
  /// DB persistence and filesystem directory renames, neither of which apply.
  Future<Attachment> saveAsync(Message? message) async => this;

  static Future<Attachment> replaceAttachmentAsync(String? oldGuid, Attachment newAttachment) async => newAttachment;

  static Future<void> deleteAsync(String guid) async {}

  String previewPathForQuality(int quality) => "$path.preview.q$quality.jpg";

  factory Attachment.fromMap(Map<String, dynamic> json) {
    String? mimeType = json["mimeType"];
    if (json["uti"] == "com.apple.coreaudio_format" || json['transferName'].toString().endsWith(".caf")) {
      mimeType = "audio/caf";
    }

    // Load the metadata
    var metadata = json["metadata"];
    if (metadata is String && metadata.isNotEmpty) {
      try {
        metadata = jsonDecode(metadata);
      } catch (_) {}
    }

    // exif uses null = never loaded, {} = loaded with no EXIF data
    var exif = json["exif"];
    if (exif is String && exif.isNotEmpty) {
      try {
        exif = jsonDecode(exif);
      } catch (_) {}
    }

    return Attachment(
      id: json["ROWID"] ?? json["id"],
      originalROWID: json["originalROWID"],
      guid: json["guid"],
      uti: json["uti"],
      mimeType: mimeType ?? mime(json['transferName']),
      isOutgoing: json["isOutgoing"] == true,
      transferName: json['transferName'],
      totalBytes: json['totalBytes'] is int ? json['totalBytes'] : 0,
      height: json["height"] ?? 0,
      width: json["width"] ?? 0,
      metadata: metadata is String ? null : metadata,
      exif: exif is String ? null : exif,
      hasLivePhoto: json["hasLivePhoto"] ?? false,
      isDownloaded: json["isDownloaded"] ?? false,
    );
  }

  /// save a new attachment or update an existing attachment on disk
  /// [message] is used to create a link between the attachment and message,
  /// when provided
  Attachment save(Message? message) {
    return this;
  }

  /// Save many attachments at once. [map] is used to establish a link between
  /// the message and its attachments.
  static void bulkSave(Map<Message, List<Attachment>> map) {
    return;
  }

  /// replaces a temporary attachment with the new one from the server
  static Attachment replaceAttachment(String? oldGuid, Attachment newAttachment) {
    return newAttachment;
  }

  /// find an attachment by its guid
  static Attachment? findOne(String guid) {
    return null;
  }

  /// Find all attachments matching a specified condition, or all attachments
  /// if no condition is provided
  static List<Attachment> find({dynamic cond}) {
    return [];
  }

  /// Delete an attachment and remove all instances of that attachment in the DB
  static void delete(String guid) {}

  String getFriendlySize({int decimals = 2}) {
    return (totalBytes ?? 0.0).toDouble().getFriendlySize();
  }

  bool get hasValidSize => (width ?? 0) > 0 && (height ?? 0) > 0;

  double get aspectRatio =>
      hasValidSize ? (_isPortrait && height! < width! ? (height! / width!).abs() : (width! / height!).abs()) : 0.78;

  /// Mirrors the io/ implementation's orientation-swap, using web's plain
  /// `width`/`height` fields (no raw/metadata distinction here).
  int? get displayWidth {
    if (!hasValidSize) return (metadata?['width'] as num?)?.toInt();
    return _isPortrait && height! < width! ? height : width;
  }

  int? get displayHeight {
    if (!hasValidSize) return (metadata?['height'] as num?)?.toInt();
    return _isPortrait && height! < width! ? width : height;
  }

  /// See io/attachment.dart's `displayBox` — the single source of truth for
  /// the box an attachment occupies inline, given the bubble's [maxWidth].
  ({double width, double height}) displayBox(double maxWidth, [double maxHeight = double.infinity]) {
    final fallbackHeight = maxWidth / aspectRatio;
    double width = math.min(displayWidth?.toDouble() ?? maxWidth, maxWidth);
    double height = math.min(displayHeight?.toDouble() ?? fallbackHeight, fallbackHeight);
    if (height > maxHeight) {
      width *= maxHeight / height;
      height = maxHeight;
    }
    return (width: width, height: height);
  }

  String? get mimeStart => mimeType?.split("/").first;

  static String get baseDirectory => FilesystemSvc.attachmentsPath;

  String get directory => "$baseDirectory/$guid";

  String get path => "$directory/$transferName";

  /// Mirrors the io/ implementation — HEIC converts to JPEG, everything else
  /// to PNG. Web is deprecated; kept in sync for consistency only.
  String get convertedExtension => (mimeType?.contains('image/hei') ?? false) ? "jpg" : "png";

  String get convertedPath => "$path.$convertedExtension";

  String get legacyConvertedPath => "$path.png";

  bool get existsOnDisk => false;

  Future<bool> get existsOnDiskAsync async => false;

  bool get canCompress => mimeStart == "image" && !mimeType!.contains("gif");

  /// No filesystem access on web, so a pass can never be loaded from disk.
  PkPass? get pkPass => null;

  bool get isPkPass => false;

  static Attachment merge(Attachment attachment1, Attachment attachment2) {
    attachment1.id ??= attachment2.id;
    attachment1.bytes ??= attachment2.bytes;
    attachment1.guid ??= attachment2.guid;
    attachment1.height ??= attachment2.height;
    attachment1.width ??= attachment2.width;
    attachment1.isOutgoing ??= attachment2.isOutgoing;
    attachment1.mimeType ??= attachment2.mimeType;
    attachment1.totalBytes ??= attachment2.totalBytes;
    attachment1.transferName ??= attachment2.transferName;
    attachment1.uti ??= attachment2.uti;
    attachment1.webUrl ??= attachment2.webUrl;
    attachment1.metadata = mergeTopLevelDicts(attachment1.metadata, attachment2.metadata);
    attachment1.exif = mergeTopLevelDicts(attachment1.exif, attachment2.exif);
    if (attachment2.hasLivePhoto) {
      attachment1.hasLivePhoto = attachment2.hasLivePhoto;
    }
    // Only overwrite isDownloaded if the new attachment is downloaded
    if (!attachment1.isDownloaded && attachment2.isDownloaded) {
      attachment1.isDownloaded = attachment2.isDownloaded;
    }
    return attachment1;
  }

  Map<String, dynamic> toMap() => {
        "ROWID": id,
        "originalROWID": originalROWID,
        "guid": guid,
        "uti": uti,
        "mimeType": mimeType,
        "isOutgoing": isOutgoing!,
        "transferName": transferName,
        "totalBytes": totalBytes,
        "height": height,
        "width": width,
        "metadata": jsonEncode(metadata),
        "exif": jsonEncode(exif),
        "hasLivePhoto": hasLivePhoto,
        "isDownloaded": isDownloaded,
      };

  bool get _isPortrait {
    if (metadata?['orientation'] == '1') return true;
    if (metadata?['orientation'] == 1) return true;
    if (metadata?['orientation'] == 'portrait') return true;
    if (exif?['Image Orientation']?.contains("90") ?? false) return true;
    if (metadata?['Image Orientation']?.contains("90") ?? false) return true;
    return false;
  }
}

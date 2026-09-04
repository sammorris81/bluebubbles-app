import 'package:bluebubbles/models/html/contact_v2.dart';
import 'package:bluebubbles/database/html/objectbox.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/models/models.dart' show HandleLookupKey;
import 'package:bluebubbles/services/services.dart';
import 'package:dice_bear/dice_bear.dart';
import 'package:faker/faker.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class Handle {
  int? id;
  int? originalROWID;
  String uniqueAddressAndService;
  String address;
  String? formattedAddress;
  String service;
  String? country;
  String? defaultEmail;
  String? defaultPhone;
  final String fakeName = faker.person.name();

  Widget? _fakeAvatar;
  Widget get fakeAvatar {
    if (_fakeAvatar != null) return _fakeAvatar!;
    final backgroundColor = randomAvatarBackgroundColors.randomChoice();
    final avatar = DiceBearBuilder(
      seed: address,
      sprite: DiceBearStyle.miniavs,
      backgroundColor: HexColor(backgroundColor),
    ).build();
    _fakeAvatar = avatar.toImage();
    return _fakeAvatar!;
  }

  // Web has no ObjectBox relations; expose empty list for API compatibility.
  List<ContactV2> get contacts => [];

  /// Matches io/handle.dart's `contactsV2` ToMany — not populated by any
  /// ObjectBox backlink on web, so it only ever holds what's explicitly
  /// added to it.
  final contactsV2 = ToMany<ContactV2>();

  String? color;

  String get displayName {
    if (address.startsWith("urn:biz")) return "Business";
    if (contactsV2.isNotEmpty) {
      // Prioritize native contacts, but fall back to any contact if no native ones exist (should be rare)
      final firstNativeContact = contactsV2.where((c) => c.isNative).firstOrNull;
      final nativeNickname = firstNativeContact?.nickname;
      if (!isNullOrEmpty(nativeNickname)) return nativeNickname!;

      final nativeDisplayName = firstNativeContact?.displayName;
      if (!isNullOrEmpty(nativeDisplayName)) return nativeDisplayName!;

      final computedDisplayName = contactsV2.first.computedDisplayName;
      if (!isNullOrEmpty(computedDisplayName)) return computedDisplayName;
    }

    // Formatted address should be filled out by sync. If it's missing,
    // format on demand so UI callers still get a readable phone number.
    return address.contains("@") ? address : (formattedAddress ?? formatPhoneNumber(address));
  }

  String get reactionDisplayName {
    if (address.startsWith("urn:biz")) return "Business";
    if (contactsV2.isNotEmpty) {
      final firstNativeContact = contactsV2.where((c) => c.isNative).firstOrNull;
      final nativeNickname = firstNativeContact?.nickname;
      if (!isNullOrEmpty(nativeNickname)) return nativeNickname!;

      final nativeFirstName = firstNativeContact?.firstName;
      if (!isNullOrEmpty(nativeFirstName)) return nativeFirstName!;

      final nativeComputedDisplayName = firstNativeContact?.computedDisplayName;
      if (!isNullOrEmpty(nativeComputedDisplayName)) return nativeComputedDisplayName!;

      final computedDisplayName = contactsV2.first.computedDisplayName;
      if (!isNullOrEmpty(computedDisplayName)) return computedDisplayName;
    }

    // For reactions, we want to show the formatted address for phone numbers, but the regular address for emails
    return address.contains("@") ? address : (formattedAddress ?? address);
  }

  String get shortName {
    return contactsV2.isNotEmpty ? reactionDisplayName.firstWord : reactionDisplayName;
  }

  String? get initials {
    if (address.startsWith("urn:biz")) return null;

    if (contactsV2.isNotEmpty) {
      final contactV2Initials = contactsV2.first.initials;
      if (contactV2Initials != null) return contactV2Initials;
    }

    final parts = displayName.trim().split(RegExp(r'[ \-_]'));
    if (parts.length == 1) return parts[0].firstAlpha;

    final firstPart = parts.first.firstAlpha ?? '';
    final secondPart = parts[1].firstAlpha ?? '';

    return (firstPart + secondPart).isEmpty ? null : firstPart + secondPart;
  }

  Handle({
    this.id,
    this.originalROWID,
    this.address = "",
    this.service = "iMessage",
    this.uniqueAddressAndService = "",
    this.formattedAddress,
    this.country,
    this.color,
    this.defaultEmail,
    this.defaultPhone,
  }) {
    if (service.isEmpty) {
      service = 'iMessage';
    }
    if (uniqueAddressAndService.isEmpty) {
      uniqueAddressAndService = "$address/$service";
    }
  }

  factory Handle.fromMap(Map<String, dynamic> json) => Handle(
        // Fall back to originalROWID: web has no local ObjectBox row to get an
        // `id` from, and `/chat/query` returns participants carrying only
        // `originalROWID` (no ROWID/id at all). Leaving `id` null there breaks
        // everything keyed on it — `HandleService.getOrCreateHandleState` hands
        // back an uncached, throwaway HandleState for every participant, so
        // contact-sync updates never reach the chat list, and
        // `removeParticipant`'s `id == id` check matches every handle at once.
        // The server's handle ROWID is stable and unique, which is all `id`
        // needs to be on web.
        id: json["ROWID"] ?? json["id"] ?? json["originalROWID"],
        originalROWID: json["originalROWID"],
        address: json["address"],
        service: json["service"] ?? "iMessage",
        uniqueAddressAndService: json["uniqueAddrAndService"] ?? "${json["address"]}/${json["service"] ?? "iMessage"}",
        formattedAddress: json["formattedAddress"],
        country: json["country"],
        color: json["color"],
        defaultPhone: json['defaultPhone'],
      );

  Future<void> updateFormattedAddress() async {
    if (!isNullOrEmpty(formattedAddress)) return;
    if (address.contains('@') || address.startsWith('urn:biz')) {
      formattedAddress = address;
    } else {
      formattedAddress = formatPhoneNumber(address);
    }
  }

  Handle save({bool updateColor = false}) {
    return this;
  }

  /// Handle Audit is a local-DB diagnostic tool, disabled on web (see
  /// `handle_audit_panel.dart`'s `if (kIsWeb) return;` in `_runAudit`) — this
  /// should never actually be reached at runtime there.
  Future<Handle> saveAsync({bool updateColor = false, bool matchOnOriginalROWID = false}) async {
    throw Exception('Unsupported Platform');
  }

  static void delete(int id) {
    throw Exception('Unsupported Platform');
  }

  static List<Handle> bulkSave(List<Handle> handles, {bool matchOnOriginalROWID = false}) {
    return [];
  }

  static Future<List<Handle>> bulkSaveAsync(List<Handle> handles, {bool matchOnOriginalROWID = false}) async {
    return handles;
  }

  Handle updateColor(String? newColor) {
    color = newColor;
    save();
    return this;
  }

  Handle updateDefaultPhone(String newPhone) {
    defaultPhone = newPhone;
    save();
    return this;
  }

  Handle updateDefaultEmail(String newEmail) {
    defaultEmail = newEmail;
    save();
    return this;
  }

  static Handle? findOne({int? id, int? originalROWID, HandleLookupKey? addressAndService}) {
    // ignore: argument_type_not_assignable, return_of_invalid_type, invalid_assignment, for_in_of_invalid_element_type
    return ChatsSvc.webCachedHandles.firstWhereOrNull((e) => originalROWID != null
        ? e.originalROWID == originalROWID
        : e.uniqueAddressAndService == "${addressAndService?.address}/${addressAndService?.service}");
  }

  static List<Handle> find() {
    return [];
  }

  static Handle merge(Handle handle1, Handle handle2) {
    handle1.id ??= handle2.id;
    handle1.originalROWID ??= handle2.originalROWID;
    handle1.color ??= handle2.color;
    handle1.country ??= handle2.country;
    handle1.formattedAddress ??= handle2.formattedAddress;
    if (isNullOrEmpty(handle1.defaultPhone)) {
      handle1.defaultPhone = handle2.defaultPhone;
    }
    if (isNullOrEmpty(handle1.defaultEmail)) {
      handle1.defaultEmail = handle2.defaultEmail;
    }

    return handle1;
  }

  Map<String, dynamic> toMap() {
    return {
      "ROWID": id,
      "originalROWID": originalROWID,
      "address": address,
      "formattedAddress": formattedAddress,
      "service": service,
      "uniqueAddrAndService": uniqueAddressAndService,
      "country": country,
      "color": color,
      "defaultPhone": defaultPhone,
      "defaultEmail": defaultEmail,
    };
  }
}

import 'dart:typed_data';

import 'package:bluebubbles/database/html/handle.dart';
import 'package:bluebubbles/database/html/objectbox.dart';
import 'package:flutter/material.dart';

/// A phone number with an associated label (e.g., "mobile", "work", "home").
/// Mirrors `database/io/contact_v2.dart`'s `ContactPhone`.
class ContactPhone {
  final String number;
  final String label;

  const ContactPhone({required this.number, required this.label});

  Map<String, dynamic> toMap() => {'number': number, 'label': label};

  static ContactPhone fromMap(Map<String, dynamic> m) =>
      ContactPhone(number: m['number'] ?? '', label: m['label'] ?? '');

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ContactPhone && number == other.number && label == other.label);

  @override
  int get hashCode => Object.hash(number, label);
}

/// An email address with an associated label (e.g., "work", "home").
/// Mirrors `database/io/contact_v2.dart`'s `ContactEmail`.
class ContactEmail {
  final String address;
  final String label;

  const ContactEmail({required this.address, required this.label});

  Map<String, dynamic> toMap() => {'address': address, 'label': label};

  static ContactEmail fromMap(Map<String, dynamic> m) =>
      ContactEmail(address: m['address'] ?? '', label: m['label'] ?? '');

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ContactEmail && address == other.address && label == other.label);

  @override
  int get hashCode => Object.hash(address, label);
}

/// Web stub for ContactV2 - minimal implementation for web compatibility
class ContactV2 {
  ContactV2({
    this.id = 0,
    required this.displayName,
    required this.nativeContactId,
    this.isNative = false,
    this.avatarPath,
    this.avatarBytes,
    this.addresses = const [],
    this.nickname,
    this.firstName,
    this.lastName,
    this.middleName,
    this.namePrefix,
    this.nameSuffix,
    this.company,
  });

  int id;
  String displayName;
  String nativeContactId;
  bool isNative;
  String? avatarPath;

  /// In-memory avatar bytes. Web has no filesystem to cache avatars to (unlike
  /// native/desktop, which write to disk and use [avatarPath]), so the decoded
  /// image is held here for the lifetime of the session instead.
  Uint8List? avatarBytes;
  List<String> addresses;
  String? nickname;
  String? firstName;
  String? lastName;
  String? middleName;
  String? namePrefix;
  String? nameSuffix;
  String? company;

  /// Mirrors io/contact_v2.dart's `handles` ToMany backlink (from
  /// `Handle.contactsV2`) — not auto-populated by any ObjectBox relation on
  /// web, so it only ever holds what's explicitly added to it.
  final handles = ToMany<Handle>();
  List<ContactPhone> phoneNumbers = [];
  List<ContactEmail> emailAddresses = [];

  /// Returns the best display name: prefers nickname, then first+last, then raw displayName.
  String get computedDisplayName {
    if (nickname != null && nickname!.isNotEmpty) return nickname!;
    final first = firstName ?? '';
    final last = lastName ?? '';
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    return displayName;
  }

  // Stub properties for web
  Widget? _fakeAvatar;
  Widget get fakeAvatar => _fakeAvatar ?? Container();

  String? get initials {
    final parts = displayName.trim().split(' ');
    if (parts.isEmpty || displayName.isEmpty) return null;

    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : null;
    }

    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.last.isNotEmpty ? parts.last[0] : '';

    return (first + last).isEmpty ? null : (first + last).toUpperCase();
  }

  Future<Uint8List?> loadAvatar() async => avatarBytes;

  static String normalizePhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'[^\d+]'), '');
  }

  static String normalizeEmail(String email) {
    return email.toLowerCase().trim();
  }

  bool hasMatchingAddress(String address) {
    final normalized = address.contains('@') ? normalizeEmail(address) : normalizePhoneNumber(address);

    return addresses.any((contactAddress) {
      final contactNormalized =
          contactAddress.contains('@') ? normalizeEmail(contactAddress) : normalizePhoneNumber(contactAddress);
      return contactNormalized == normalized;
    });
  }

  /// Formats this contact for the server upload API.
  /// Field names match what the server expects (and sends back on fetch).
  Map<String, dynamic> toServerMap() {
    return {
      'displayName': displayName,
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumbers': phoneNumbers.map((e) => e.number).toList(),
      'emails': emailAddresses.map((e) => e.address).toList(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'nativeContactId': nativeContactId,
      'avatarPath': avatarPath,
      'addresses': addresses,
    };
  }

  static ContactV2 fromMap(Map<String, dynamic> map) {
    return ContactV2(
      id: map['id'] ?? 0,
      displayName: map['displayName'] ?? '',
      nativeContactId: map['nativeContactId'] ?? '',
      avatarPath: map['avatarPath'],
      addresses: List<String>.from(map['addresses'] ?? []),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactV2 &&
          runtimeType == other.runtimeType &&
          nativeContactId == other.nativeContactId &&
          displayName == other.displayName);

  @override
  int get hashCode => Object.hash(nativeContactId, displayName);
}

import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/prefs_actions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';

class PrefsInterface {
  static Future<void> saveReplyToMessageState(String chatGuid, String? messageGuid, int? messagePart) async {
    final data = {
      'chatGuid': chatGuid,
      'messageGuid': messageGuid,
      'messagePart': messagePart,
    };

    if (isIsolate) {
      return await PrefsActions.saveReplyToMessageState(data);
    } else {
      return await GetIt.I<GlobalIsolate>().send<void>(IsolateRequestType.saveReplyToMessageState, input: data);
    }
  }

  static Future<Map<String, dynamic>?> loadReplyToMessageState(String chatGuid) async {
    final data = {
      'chatGuid': chatGuid,
    };

    if (isIsolate) {
      return PrefsActions.loadReplyToMessageState(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>?>(IsolateRequestType.loadReplyToMessageState, input: data);
    }
  }

  /// Pushes settings into the GlobalIsolate's copy of [SettingsSvc.settings].
  ///
  /// Both sync methods are no-ops on web: there's no isolate there, so
  /// `GlobalIsolate.send` runs the action on the main thread, and
  /// `PrefsActions.syncAllSettings` then *replaces* the live `SettingsSvc.settings`
  /// object. Every `Obx`/`ever()` bound to the old object's `Rx` fields goes dead —
  /// e.g. after one toggle on a settings page, the other switches stop moving.
  /// The main thread's settings are the only copy on web, so there's nothing to sync.
  static Future<void> syncAllSettings({Map<String, dynamic>? settings}) async {
    if (kIsWeb) return;
    final data = {
      'settings': settings ?? SettingsSvc.settings.toMap(),
    };

    if (isIsolate) {
      return await PrefsActions.syncAllSettings(data);
    } else {
      return await GetIt.I<GlobalIsolate>().send<void>(IsolateRequestType.syncAllSettings, input: data);
    }
  }

  static Future<void> syncSettings(Map<String, dynamic> settings) async {
    if (kIsWeb) return;
    if (isIsolate) {
      return await PrefsActions.syncSettings(settings);
    } else {
      return await GetIt.I<GlobalIsolate>().send<void>(IsolateRequestType.syncSettings, input: settings);
    }
  }
}

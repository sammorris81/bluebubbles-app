import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

bool isIsolateOverride = false;
String? isolateNameOverride;

/// Prefixes the log name (and so the log file) of this engine's isolates without changing [isIsolate]. Set for
/// Android bubble engines, whose root and spawned isolates would otherwise share names with the main engine's.
/// Every bubble shares the one prefix, so its files have several writers (see RotatingFileOutput).
String? logNamePrefix;

bool get isIsolate {
  if (isIsolateOverride) return true;
  // dart:isolate isn't supported on web at all — there's no separate
  // "global isolate" there, so this is always the (only) main context.
  if (kIsWeb) return false;
  final name = isolateNameOverride ?? Isolate.current.debugName;
  return name != null && name != 'main';
}

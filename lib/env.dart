import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

bool isIsolateOverride = false;
String? isolateNameOverride;

bool get isIsolate {
  if (isIsolateOverride) return true;
  // dart:isolate isn't supported on web at all — there's no separate
  // "global isolate" there, so this is always the (only) main context.
  if (kIsWeb) return false;
  final name = isolateNameOverride ?? Isolate.current.debugName;
  return name != null && name != 'main';
}

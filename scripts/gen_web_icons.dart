/// Regenerates the PWA icons in `web/icons/` from the source art in `assets/icon/`.
///
///     dart run scripts/gen_web_icons.dart
///
/// Two sets come out of this, from two different sources:
///
/// * `Icon-<size>.png` (`purpose: "any"`) — `icon.png` resized. Drawn as-is on
///   desktop installs and in the Chrome install prompt, so it keeps its
///   transparent surround.
/// * `Icon-maskable-<size>.png` (`purpose: "maskable"`) — the Android adaptive
///   foreground over the adaptive background colour. The OS crops these to
///   whatever shape it likes (circle, squircle, teardrop), so they have to be
///   full-bleed with the artwork inside the safe zone.
///
/// The maskable pair is why this isn't just `flutter_launcher_icons`: its web
/// generator takes a single `image_path` and emits both purposes from it, and
/// `icon.png` is a transparent bubble running nearly edge to edge — masked, its
/// sides get chopped off. There's deliberately no `web:` block in pubspec's
/// `flutter_icons:` config, so running that tool won't overwrite these.
library;

import 'dart:io';

import 'package:image/image.dart';
import 'package:path/path.dart' as p;

/// Sizes Chrome wants for installability: 192 for the launcher, 512 for the
/// install prompt and splash.
const _sizes = [192, 512];

/// `adaptive_icon_background` from pubspec's `flutter_icons:` config.
final _adaptiveBackground = ColorRgb8(0x49, 0x90, 0xde);

/// Android composites an adaptive icon on a 108dp canvas and shows the middle
/// 72dp of it. Cropping to the same fraction here means the maskable icon reads
/// at the size the Android launcher icon does, rather than as a small mark
/// marooned in the middle of a blue square.
const _adaptiveVisibleFraction = 72 / 108;

void main() {
  final root = p.dirname(p.dirname(p.fromUri(Platform.script)));
  final outDir = Directory(p.join(root, 'web', 'icons'))..createSync(recursive: true);

  final any = _decode(p.join(root, 'assets', 'icon', 'icon.png'));
  final maskable = _maskableSource(_decode(p.join(root, 'assets', 'icon', 'adaptive-foreground.png')));

  for (final size in _sizes) {
    _write(p.join(outDir.path, 'Icon-$size.png'), any, size);
    _write(p.join(outDir.path, 'Icon-maskable-$size.png'), maskable, size);
  }
}

Image _decode(String path) {
  final image = decodePng(File(path).readAsBytesSync());
  if (image == null) throw StateError('Could not decode $path');
  return image;
}

/// Centre-crops [foreground] to the adaptive icon's visible area and composites
/// it over an opaque [_adaptiveBackground] square.
Image _maskableSource(Image foreground) {
  final side = (foreground.width * _adaptiveVisibleFraction).round();
  final cropped = copyCrop(
    foreground,
    x: (foreground.width - side) ~/ 2,
    y: (foreground.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final canvas = Image(width: side, height: side)..clear(_adaptiveBackground);
  return compositeImage(canvas, cropped);
}

void _write(String path, Image source, int size) {
  final resized = copyResize(source, width: size, height: size, interpolation: Interpolation.cubic);
  File(path).writeAsBytesSync(encodePng(resized));
  stdout.writeln('wrote ${p.relative(path)} (${size}x$size)');
}

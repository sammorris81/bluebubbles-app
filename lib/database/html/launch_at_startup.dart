class LaunchAtStartup {
  static Future<bool> enable() async => throw Exception('Not supported on Web!');

  static Future<bool> disable() async => throw Exception('Not supported on Web!');

  static Never setup(String appName, bool minimized) => throw Exception('Not supported on Web!');

  static String? get shortcutPath => null;

  static Future<void> revealShortcut() async => throw Exception('Not supported on Web!');
}

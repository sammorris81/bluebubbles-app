import 'dart:async';

/// Shim for network_tools to allow for web compile. The real package uses
/// dart:io internally, so it's swapped for this on web via the conditional
/// import in `network_tasks.dart`.
Future<void> configureNetworkTools(
  String dbDirectory, {
  bool enableDebugging = false,
  bool rebuildData = false,
}) async {}

class ActiveHost {
  String address = "";
}

abstract class HostScannerService {
  static final HostScannerService instance = _WebHostScannerService();

  Stream<ActiveHost> scanDevicesForSinglePort(
    String subnet,
    int port, {
    int firstHostId = 1,
    int lastHostId = 254,
    Duration timeout = const Duration(milliseconds: 2000),
    dynamic progressCallback,
    bool resultsInAddressAscendingOrder = true,
  });
}

class _WebHostScannerService implements HostScannerService {
  @override
  Stream<ActiveHost> scanDevicesForSinglePort(
    String subnet,
    int port, {
    int firstHostId = 1,
    int lastHostId = 254,
    Duration timeout = const Duration(milliseconds: 2000),
    dynamic progressCallback,
    bool resultsInAddressAscendingOrder = true,
  }) {
    // No subnet scanning on web — a browser can't probe arbitrary LAN hosts.
    return const Stream.empty();
  }
}

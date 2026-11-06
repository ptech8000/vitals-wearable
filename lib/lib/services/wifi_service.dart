import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

class WifiDeviceResult {
  final String name;
  final String ipAddress;
  final int port;
  final String deviceSerial;

  /// True for the built-in demo node that is injected when nothing is found.
  final bool isMock;

  WifiDeviceResult({
    required this.name,
    required this.ipAddress,
    required this.port,
    required this.deviceSerial,
    this.isMock = false,
  });
}

class WifiService {
  /// Injects a demo node when no mDNS devices answer (simulator / testing).
  /// Set to false for release builds that should only list real devices.
  static const bool enableMockFallback = true;

  static const Duration _pollInterval = Duration(seconds: 2);
  static const Duration _requestTimeout = Duration(seconds: 3);

  /// After this many failed polls in a row a real device counts as lost.
  static const int _maxConsecutiveFailures = 4;

  final StreamController<List<WifiDeviceResult>> _discoveredDevicesController =
      StreamController<List<WifiDeviceResult>>.broadcast();
  List<WifiDeviceResult> _lastResults = const [];

  /// Replays the latest results to late listeners, so a sheet that opens just
  /// after devices were found still shows them.
  Stream<List<WifiDeviceResult>> get discoveredDevicesStream async* {
    if (_lastResults.isNotEmpty) yield _lastResults;
    yield* _discoveredDevicesController.stream;
  }

  final ValueNotifier<bool> isScanning = ValueNotifier<bool>(false);

  HttpClient? _httpClient;
  Timer? _pollingTimer;
  StreamController<Map<String, dynamic>>? _telemetryController;

  void _publish(List<WifiDeviceResult> devices) {
    _lastResults = List.unmodifiable(devices);
    if (!_discoveredDevicesController.isClosed) {
      _discoveredDevicesController.add(_lastResults);
    }
  }

  // Scan local network via mDNS for devices advertising '_vitalsync._tcp'
  Future<void> startWifiScan() async {
    if (isScanning.value) return;
    isScanning.value = true;
    _publish(const []);

    final foundDevices = <WifiDeviceResult>[];
    MDnsClient? client;

    try {
      client = MDnsClient();
      await client.start();

      const String serviceType = '_vitalsync._tcp.local';
      final pending = <Future<void>>[];

      // Each device is resolved the moment its pointer record arrives, in
      // parallel, instead of one after another.
      await for (final PtrResourceRecord ptr
          in client.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceType),
            timeout: const Duration(seconds: 3),
          )) {
        pending.add(_resolveDevice(client, ptr, foundDevices));
      }
      await Future.wait(pending);
    } catch (e) {
      debugPrint("Wi-Fi scan error: $e");
    } finally {
      client?.stop();
    }

    // Fallback: a mock local node when nothing is broadcasting.
    if (foundDevices.isEmpty && enableMockFallback) {
      foundDevices.add(
        WifiDeviceResult(
          name: "VitalSync-Node-Pro",
          ipAddress: "192.168.1.50",
          port: 8080,
          deviceSerial: "WIFI_WEAR_99",
          isMock: true,
        ),
      );
      _publish(foundDevices);
    }

    isScanning.value = false;
  }

  Future<void> _resolveDevice(
    MDnsClient client,
    PtrResourceRecord ptr,
    List<WifiDeviceResult> foundDevices,
  ) async {
    try {
      // `.first` stops listening as soon as an answer arrives rather than
      // waiting for the lookup timeout to expire.
      final srv = await client
          .lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: const Duration(seconds: 2),
          )
          .first;
      final ip = await client
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: const Duration(seconds: 2),
          )
          .first;

      final device = WifiDeviceResult(
        name: ptr.domainName.split('.').first,
        ipAddress: ip.address.address,
        port: srv.port,
        deviceSerial: srv.target.replaceAll('.local', ''),
      );

      if (!foundDevices.any((d) => d.ipAddress == device.ipAddress)) {
        foundDevices.add(device);
        _publish(foundDevices);
      }
    } catch (_) {
      // Device did not answer in time; it simply is not listed.
    }
  }

  // Connect to discovered Wi-Fi device and poll telemetry stream.
  // The returned stream emits an error once a real device stops answering.
  Stream<Map<String, dynamic>> connectToWifiDevice(WifiDeviceResult device) {
    disconnect();

    final client = HttpClient()..connectionTimeout = _requestTimeout;
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _httpClient = client;
    _telemetryController = controller;

    final uri = Uri.parse('http://${device.ipAddress}:${device.port}/vitals');
    bool requestInFlight = false;
    int consecutiveFailures = 0;

    Future<void> poll() async {
      // Never stack requests: a slow device would otherwise build a queue.
      if (requestInFlight || controller.isClosed) return;
      requestInFlight = true;
      try {
        final request = await client.getUrl(uri).timeout(_requestTimeout);
        final response = await request.close().timeout(_requestTimeout);
        if (response.statusCode == 200) {
          final contents = await response
              .transform(utf8.decoder)
              .join()
              .timeout(_requestTimeout);
          final decoded = jsonDecode(contents);
          if (decoded is Map && !controller.isClosed) {
            consecutiveFailures = 0;
            controller.add(Map<String, dynamic>.from(decoded));
          }
        } else {
          await response.drain<void>();
          consecutiveFailures++;
        }
      } catch (e) {
        consecutiveFailures++;
        debugPrint("Wi-Fi telemetry poll error: $e");
      } finally {
        requestInFlight = false;
      }

      if (!device.isMock &&
          consecutiveFailures >= _maxConsecutiveFailures &&
          !controller.isClosed) {
        _pollingTimer?.cancel();
        controller.addError(
          const SocketException('Wi-Fi device stopped responding'),
        );
      }
    }

    poll(); // first reading right away instead of after one full interval
    _pollingTimer = Timer.periodic(_pollInterval, (_) => poll());

    return controller.stream;
  }

  void disconnect() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    final controller = _telemetryController;
    _telemetryController = null;
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }

  void dispose() {
    disconnect();
    _discoveredDevicesController.close();
    isScanning.dispose();
  }
}

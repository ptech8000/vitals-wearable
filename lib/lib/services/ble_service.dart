import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  BluetoothDevice? _connectedDevice;

  /// Services are discovered once per connection and reused (battery read, etc.)
  List<BluetoothService> _services = const [];
  final List<StreamSubscription<List<int>>> _notifySubscriptions = [];

  final StreamController<Map<String, dynamic>> _readingController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get readingStream => _readingController.stream;

  /// Only the characteristics this app actually parses are subscribed to.
  /// Subscribing to every notify characteristic floods the radio and the
  /// event loop with data that is thrown away.
  static const List<String> _supportedCharacteristics = [
    '2a37', // heart rate measurement
    '2a1f', // temperature
    '2a35', // blood pressure
    '2a19', // battery level
  ];

  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  // Stream scan results, filtering out the phone/local artifacts and sorting by RSSI descending
  Stream<List<ScanResult>> get scanResults {
    return FlutterBluePlus.scanResults.map((results) {
      final filteredResults = results.where((r) {
        final bool isConnectable = r.advertisementData.connectable;
        final bool hasMetadata =
            r.device.platformName.isNotEmpty ||
            r.advertisementData.advName.isNotEmpty ||
            r.advertisementData.localName.isNotEmpty ||
            r.advertisementData.serviceUuids.isNotEmpty;

        return isConnectable && hasMetadata;
      }).toList();

      // Highest RSSI (closest) first
      filteredResults.sort((a, b) => b.rssi.compareTo(a.rssi));
      return filteredResults;
    });
  }

  Future<void> startScan() async {
    try {
      if (await FlutterBluePlus.isSupported == false) return;
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
    } catch (e) {
      if (kDebugMode) {
        print("Scan error: $e");
      }
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<String> connectToDevice(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
      await _clearNotifySubscriptions();
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      _connectedDevice = device;

      _services = await device.discoverServices();
      for (final service in _services) {
        for (final characteristic in service.characteristics) {
          if (!characteristic.properties.notify) continue;

          final id = characteristic.uuid.toString().toLowerCase();
          if (!_supportedCharacteristics.any(id.contains)) continue;

          // Listen first so the very first notification is never missed.
          _notifySubscriptions.add(
            characteristic.onValueReceived.listen(
              (value) => _parseCharacteristicData(id, value),
            ),
          );
          await characteristic.setNotifyValue(true);
        }
      }

      return device.remoteId.toString();
    } catch (e) {
      await _clearNotifySubscriptions();
      throw Exception("Failed to connect: $e");
    }
  }

  /// Reads the battery level from the services found during connect.
  Future<int?> readBatteryLevel() async {
    try {
      for (final service in _services) {
        if (!service.uuid.toString().toLowerCase().contains('180f')) continue;
        for (final characteristic in service.characteristics) {
          final isBattery = characteristic.uuid
              .toString()
              .toLowerCase()
              .contains('2a19');
          if (isBattery && characteristic.properties.read) {
            final value = await characteristic.read();
            if (value.isNotEmpty) return value[0];
          }
        }
      }
    } catch (e) {
      debugPrint("Error reading battery level: $e");
    }
    return null;
  }

  void _parseCharacteristicData(String uuid, List<int> value) {
    if (value.isEmpty || _readingController.isClosed) return;

    if (uuid.contains("2a37")) {
      // Bit 0 of the flags byte says whether the rate is 8 or 16 bit.
      final bool is16Bit = (value[0] & 0x01) != 0;
      int hr;
      if (is16Bit && value.length >= 3) {
        hr = value[1] | (value[2] << 8);
      } else {
        hr = value.length > 1 ? value[1] : value[0];
      }
      _readingController.add({'heartRate': hr});
    } else if (uuid.contains("2a1f")) {
      double temp = 36.0 + (value[0] / 10.0);
      _readingController.add({'temperature': temp});
    } else if (uuid.contains("2a35")) {
      if (value.length >= 3) {
        _readingController.add({
          'systolicBP': value[1],
          'diastolicBP': value[2],
        });
      }
    } else if (uuid.contains("2a19")) {
      _readingController.add({'batteryLevel': value[0]});
    }
  }

  Future<void> _clearNotifySubscriptions() async {
    for (final subscription in _notifySubscriptions) {
      await subscription.cancel();
    }
    _notifySubscriptions.clear();
  }

  Future<void> disconnect() async {
    await _clearNotifySubscriptions();
    final device = _connectedDevice;
    _connectedDevice = null;
    _services = const [];
    try {
      await device?.disconnect();
    } catch (e) {
      debugPrint("Disconnect error: $e");
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _readingController.close();
  }
}

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/vital_reading.dart';
import '../models/device_model.dart';
import '../services/ble_service.dart';
import '../services/wifi_service.dart';
import '../services/hive_service.service.dart';

enum SyncOutcome { success, offline, noDevice, failed }

class HealthViewModel extends ChangeNotifier {
  static const String _noDevice = "NOT_CONNECTED";

  static const Set<String> _vitalKeys = {
    'heartRate',
    'spo2',
    'temperature',
    'systolicBP',
    'diastolicBP',
    'respiratoryRate',
  };

  /// Live values reach the UI at most this often, however fast the watch sends.
  static const Duration _uiThrottle = Duration(milliseconds: 400);

  /// Abnormal readings are saved immediately, but not more often than this.
  static const Duration _alertPersistGap = Duration(minutes: 1);

  /// Battery changes are pushed to Firestore at most this often.
  static const Duration _metadataSyncGap = Duration(minutes: 5);

  static const Map<String, Duration> _frequencyIntervals = {
    "5 min": Duration(minutes: 5),
    "10 min": Duration(minutes: 10),
    "30 min": Duration(minutes: 30),
    "1 hour": Duration(hours: 1),
    "4 hours": Duration(hours: 4),
    "6 hours": Duration(hours: 6),
    "12 hours": Duration(hours: 12),
    "24 hours": Duration(hours: 24),
  };

  final BleService _bleService = BleService();
  final WifiService _wifiService = WifiService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ---------------------------------------------------------------- state --

  /// Latest values from the watch. Held in memory and shown live; it is only
  /// written to storage on the reading-frequency schedule (see below).
  VitalReading? _currentReading;
  VitalReading? get currentReading => _currentReading;

  /// Every stored reading, newest first. Screens read this instead of
  /// re-parsing the Hive box on every rebuild.
  final List<VitalReading> _history = [];
  UnmodifiableListView<VitalReading> get history =>
      UnmodifiableListView(_history);
  bool get hasHistory => _history.isNotEmpty;

  /// Bumps whenever [history] changes, so widgets can cheaply tell.
  int _historyRevision = 0;
  int get historyRevision => _historyRevision;

  String _connectionStatus = "Disconnected";
  String get connectionStatus => _connectionStatus;
  bool get isConnected => _connectionStatus.contains("Connected");

  int _batteryLevel = 85;
  int get batteryLevel => _batteryLevel;

  String _deviceSerial = _noDevice;
  String get deviceSerial => _deviceSerial;

  String _deviceName = "Unknown Device";
  String get deviceName => _deviceName;

  String _connectionType = "None";
  String get connectionType => _connectionType;

  String _readingFrequency = "30 min";
  String get readingFrequency => _readingFrequency;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool _isCelsius = true;
  bool get isCelsius => _isCelsius;
  String get temperatureUnitLabel => _isCelsius ? '°C' : '°F';

  bool _isManualSyncing = false;
  bool get isManualSyncing => _isManualSyncing;

  DateTime? _lastSyncedAt;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Stream<List<ScanResult>> get scanResults => _bleService.scanResults;
  Stream<bool> get bluetoothScanning => _bleService.isScanning;
  Stream<List<WifiDeviceResult>> get wifiScanResults =>
      _wifiService.discoveredDevicesStream;
  ValueListenable<bool> get wifiScanning => _wifiService.isScanning;

  // ------------------------------------------------------- infrastructure --

  StreamSubscription? _dataSubscription;
  Timer? _autoFetchTimer;
  Timer? _notifyTimer;
  bool _notifyPending = false;
  bool _disposed = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<BluetoothConnectionState>?
  _deviceConnectionStateSubscription;

  /// Concurrent upload requests share one in-flight future.
  Future<bool>? _uploadFuture;

  bool _dirtySincePersist = false;
  bool _hasPersistedSinceConnect = false;
  DateTime? _lastAlertPersist;
  DateTime? _lastMetadataSync;
  bool _deviceDocChecked = false;

  HealthViewModel() {
    _loadSettings();
    _loadHistory();
    _initBackgroundSync();
    _initBluetoothListeners();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  /// Leading-edge throttle for high-frequency live data: the first change is
  /// shown immediately, later ones within [_uiThrottle] are merged into one
  /// rebuild. This keeps the UI smooth when a watch notifies many times a second.
  void _notifyLive() {
    if (_notifyTimer?.isActive ?? false) {
      _notifyPending = true;
      return;
    }
    notifyListeners();
    _notifyTimer = Timer(_uiThrottle, () {
      if (_notifyPending) {
        _notifyPending = false;
        notifyListeners();
      }
    });
  }

  // ------------------------------------------------------------ bluetooth --

  void _initBluetoothListeners() {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state != BluetoothAdapterState.on && _connectionType == "Bluetooth") {
        _forceDisconnectState("Bluetooth Turned Off");
      }
    });
  }

  void _resetDeviceFields() {
    _deviceSerial = _noDevice;
    _deviceName = "Unknown Device";
    _connectionType = "None";
  }

  void _forceDisconnectState(String reason) {
    debugPrint("Forcing disconnect: $reason");
    _connectionStatus = reason;
    _resetDeviceFields();
    notifyListeners();
    unawaited(_teardownConnection());
  }

  /// Stops everything tied to the current device. The connection-state
  /// listener is cancelled first, otherwise disconnecting the old device would
  /// report "Device Disconnected" over the top of a new connection.
  Future<void> _teardownConnection() async {
    await _deviceConnectionStateSubscription?.cancel();
    _deviceConnectionStateSubscription = null;
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    _autoFetchTimer?.cancel();
    _autoFetchTimer = null;
    _wifiService.disconnect();
    await _bleService.disconnect();

    _hasPersistedSinceConnect = false;
    _dirtySincePersist = false;
    _lastAlertPersist = null;
    _lastMetadataSync = null;
    _deviceDocChecked = false;
  }

  /// Disconnects the current device and returns to the idle state.
  Future<void> disconnectDevice() async {
    await _teardownConnection();
    _resetDeviceFields();
    _connectionStatus = "Disconnected";
    notifyListeners();
  }

  void startBluetoothScanning() {
    if (!isConnected) {
      _connectionStatus = "Scanning Bluetooth devices...";
      notifyListeners();
    }
    _bleService.startScan();
  }

  void startWifiScanning() {
    if (!isConnected) {
      _connectionStatus = "Scanning local Wi-Fi network...";
      notifyListeners();
    }
    _wifiService.startWifiScan();
  }

  /// Call when a scanner sheet closes without a device being chosen.
  void cancelScanning() {
    _bleService.stopScan();
    if (_connectionStatus.startsWith("Scanning")) {
      _connectionStatus = "Disconnected";
      notifyListeners();
    }
  }

  Future<void> selectAndConnectBluetoothDevice(BluetoothDevice device) async {
    await _teardownConnection();
    try {
      _connectionType = "Bluetooth";
      _connectionStatus = "Connecting via BLE...";
      _deviceName = device.platformName.isNotEmpty
          ? device.platformName
          : (device.advName.isNotEmpty ? device.advName : "Connected Watch");
      notifyListeners();

      // Subscribe before connecting so the first notifications are not lost.
      _dataSubscription = _bleService.readingStream.listen(_onDeviceData);

      final String uniqueId = await _bleService.connectToDevice(device);
      _deviceSerial = uniqueId.isNotEmpty
          ? uniqueId
          : device.remoteId.toString();

      _deviceConnectionStateSubscription = device.connectionState.listen((
        state,
      ) {
        if (state == BluetoothConnectionState.disconnected) {
          _forceDisconnectState("Device Disconnected");
        }
      });

      final battery = await _bleService.readBatteryLevel();
      if (battery != null) _batteryLevel = battery;

      _connectionStatus = "Connected (Bluetooth)";
      _setupAutoFetchTimer();
      notifyListeners();

      // Firestore is updated in the background. Awaiting it here would keep
      // the app on "Connecting" for as long as the network takes (or forever
      // when offline).
      unawaited(_syncDeviceMetadataToFirestore(force: true));
    } catch (e) {
      await _teardownConnection();
      _resetDeviceFields();
      _connectionStatus = "Bluetooth Connection Failed";
      notifyListeners();
    }
  }

  // --------------------------------------------------------------- wi-fi --

  Future<void> selectAndConnectWifiDevice(WifiDeviceResult wifiDevice) async {
    await _teardownConnection();
    try {
      _connectionType = "WiFi";
      _connectionStatus = "Connecting to ${wifiDevice.name}...";
      _deviceName = wifiDevice.name;
      _deviceSerial = wifiDevice.deviceSerial;
      notifyListeners();

      _dataSubscription = _wifiService
          .connectToWifiDevice(wifiDevice)
          .listen(
            _onDeviceData,
            onError: (_) => _forceDisconnectState("Wi-Fi Connection Lost"),
          );

      _connectionStatus = "Connected (Wi-Fi)";
      _setupAutoFetchTimer();
      notifyListeners();

      unawaited(_syncDeviceMetadataToFirestore(force: true));
    } catch (e) {
      await _teardownConnection();
      _resetDeviceFields();
      _connectionStatus = "Wi-Fi Connection Failed";
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ settings --

  /// Hive boxes are opened in main() before the app starts, so settings are
  /// read synchronously. The first frame already has the saved theme instead
  /// of flashing the system one.
  void _loadSettings() {
    try {
      final box = Hive.box('settingsBox');
      _readingFrequency = box.get('readingFrequency', defaultValue: '30 min');
      _isCelsius = box.get('isCelsius', defaultValue: true);

      final String themeStr = box.get('themeMode', defaultValue: 'system');
      if (themeStr == 'light') {
        _themeMode = ThemeMode.light;
      } else if (themeStr == 'dark') {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.system;
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
  }

  void _loadHistory() {
    try {
      _history
        ..clear()
        ..addAll(HiveService.getCachedReadings());
      _historyRevision++;
      _currentReading = _history.isEmpty ? null : _history.first;
    } catch (e) {
      debugPrint("Error loading history: $e");
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    try {
      final box = await Hive.openBox('settingsBox');
      await box.put(key, value);
    } catch (e) {
      debugPrint("Error saving $key: $e");
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final themeStr = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _saveSetting('themeMode', themeStr);
  }

  Future<void> setTemperatureUnit(bool celsius) async {
    _isCelsius = celsius;
    notifyListeners();
    await _saveSetting('isCelsius', celsius);
  }

  double formatTemperature(double tempInCelsius) {
    if (_isCelsius) {
      return double.parse(tempInCelsius.toStringAsFixed(1));
    } else {
      final double fahrenheit = (tempInCelsius * 9 / 5) + 32;
      return double.parse(fahrenheit.toStringAsFixed(1));
    }
  }

  Future<void> setReadingFrequency(String frequency) async {
    _readingFrequency = frequency;
    notifyListeners();
    await _saveSetting('readingFrequency', frequency);
    if (isConnected) {
      _setupAutoFetchTimer();
    }
  }

  // ----------------------------------------------------- reading pipeline --

  /// Records the current vitals on the user's chosen frequency.
  void _setupAutoFetchTimer() {
    _autoFetchTimer?.cancel();
    final interval =
        _frequencyIntervals[_readingFrequency] ?? const Duration(minutes: 30);

    _autoFetchTimer = Timer.periodic(interval, (_) {
      if (isConnected) {
        debugPrint(
          "Auto-fetch interval triggered: recording vitals for $_deviceSerial",
        );
        unawaited(_persistCurrentReading());
      }
    });
  }

  void _onDeviceData(Map<String, dynamic> data) {
    final battery = _asInt(data['batteryLevel']);
    if (battery != null && battery != _batteryLevel) {
      _batteryLevel = battery;
      unawaited(_syncDeviceMetadataToFirestore());
      if (!data.keys.any(_vitalKeys.contains)) _notifyLive();
    }

    // Battery-only packets carry no vitals; they must not create a reading.
    if (data.keys.any(_vitalKeys.contains)) {
      _ingestLiveData(data);
    }
  }

  /// Merges incoming values into the live reading. This is deliberately cheap:
  /// no disk or network work per packet. Persistence happens on the frequency
  /// timer, on the first reading after connecting, and (rate limited) when a
  /// reading is abnormal.
  void _ingestLiveData(Map<String, dynamic> data) {
    final prev = _currentReading;
    final now = DateTime.now();

    final int hr = _asInt(data['heartRate']) ?? prev?.heartRate ?? 72;
    final bool alert = hr > 100 || hr < 50;

    _currentReading = VitalReading(
      readingId: 'live_${now.millisecondsSinceEpoch}',
      timestamp: now,
      heartRate: hr,
      spo2: _asInt(data['spo2']) ?? prev?.spo2 ?? 98,
      temperature:
          _asDouble(data['temperature']) ?? prev?.temperature ?? 36.8,
      systolicBP: _asInt(data['systolicBP']) ?? prev?.systolicBP ?? 118,
      diastolicBP: _asInt(data['diastolicBP']) ?? prev?.diastolicBP ?? 76,
      respiratoryRate:
          _asInt(data['respiratoryRate']) ?? prev?.respiratoryRate ?? 16,
      alertTriggered: alert,
      dataQuality: 99.5,
    );
    _dirtySincePersist = true;

    final bool firstSinceConnect = !_hasPersistedSinceConnect;
    final bool alertDue =
        alert &&
        (_lastAlertPersist == null ||
            now.difference(_lastAlertPersist!) >= _alertPersistGap);

    if (firstSinceConnect || alertDue) {
      if (alertDue) _lastAlertPersist = now;
      unawaited(_persistCurrentReading());
    } else {
      _notifyLive();
    }
  }

  /// Saves a snapshot of the live reading to history, Hive and Firestore.
  Future<void> _persistCurrentReading() async {
    final base = _currentReading;
    if (base == null || !_dirtySincePersist) return;

    _dirtySincePersist = false;
    _hasPersistedSinceConnect = true;

    final now = DateTime.now();
    final reading = base.copyWith(
      readingId: now.millisecondsSinceEpoch.toString(),
      timestamp: now,
    );

    _currentReading = reading;
    _history.insert(0, reading);
    _historyRevision++;
    notifyListeners();

    try {
      await HiveService.saveReadingLocally(reading);
    } catch (e) {
      debugPrint("Error saving reading locally: $e");
    }
    unawaited(_syncReadingToFirestore(reading));
  }

  // ------------------------------------------------------------ firestore --

  Future<bool> _hasInternet() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  // Sync Device Metadata to Firestore: /users/{userId}/devices/{deviceId}
  Future<void> _syncDeviceMetadataToFirestore({bool force = false}) async {
    if (_deviceSerial == _noDevice) return;

    final now = DateTime.now();
    if (!force &&
        _lastMetadataSync != null &&
        now.difference(_lastMetadataSync!) < _metadataSyncGap) {
      return;
    }
    _lastMetadataSync = now;

    final serial = _deviceSerial;
    try {
      final deviceModel = DeviceModel(
        deviceId: serial,
        deviceName: _deviceName,
        deviceSerial: serial,
        lastSeen: now,
        batteryLevel: _batteryLevel,
        firmwareVersion: "1.0.0",
        pairedAt: now,
      );

      final ref = _firestore
          .collection('users')
          .doc(serial) // User ID is device serial
          .collection('devices')
          .doc(serial);

      // pairedAt is written once, when the device is first seen, instead of
      // being overwritten with "now" on every sync.
      final data = deviceModel.toJson(includePairedAt: false);
      if (!_deviceDocChecked) {
        _deviceDocChecked = true;
        try {
          final snapshot = await ref.get();
          if (!snapshot.exists) {
            data['pairedAt'] = deviceModel.pairedAt.toIso8601String();
          }
        } catch (_) {
          // Unknown (e.g. offline): leave pairedAt untouched.
        }
      }

      await ref.set(data, SetOptions(merge: true));
      debugPrint("Device metadata successfully synced to Firestore.");
    } catch (e) {
      debugPrint("Error syncing device metadata: $e");
    }
  }

  // Sync Readings to Firestore: /users/{userId}/readings/{readingId}
  Future<void> _syncReadingToFirestore(VitalReading reading) async {
    if (_deviceSerial == _noDevice) return;
    final serial = _deviceSerial;

    try {
      if (!await _hasInternet()) {
        debugPrint("No internet connection. Reading kept in local cache.");
        return;
      }

      await _firestore
          .collection('users')
          .doc(serial)
          .collection('readings')
          .doc(reading.readingId)
          .set(reading.toJson());
      await HiveService.markSynced([reading.readingId]);
      debugPrint("Reading successfully synced to Firebase.");
    } catch (e) {
      debugPrint("Firestore sync error: $e");
    }
  }

  /// Manual "Sync to Firebase now".
  Future<SyncOutcome> syncNow() async {
    if (_deviceSerial == _noDevice) return SyncOutcome.noDevice;

    _isManualSyncing = true;
    notifyListeners();

    try {
      if (!await _hasInternet()) return SyncOutcome.offline;

      await _persistCurrentReading();
      await _syncDeviceMetadataToFirestore(force: true);
      final bool ok = await _uploadPendingReadings();
      if (ok) _lastSyncedAt = DateTime.now();
      return ok ? SyncOutcome.success : SyncOutcome.failed;
    } catch (e) {
      debugPrint("Manual sync error: $e");
      return SyncOutcome.failed;
    } finally {
      _isManualSyncing = false;
      notifyListeners();
    }
  }

  void _initBackgroundSync() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(_uploadPendingReadings());
      }
    });
    _checkAndSilentUploadOnStartup();
  }

  Future<void> _checkAndSilentUploadOnStartup() async {
    try {
      if (await _hasInternet()) {
        unawaited(_uploadPendingReadings());
      }
    } catch (e) {
      // Suppress background errors
    }
  }

  /// Uploads only readings that are not on Firestore yet, in batches of up to
  /// 400 writes. A second caller while an upload runs simply waits for it.
  Future<bool> _uploadPendingReadings() =>
      _uploadFuture ??= _doUploadPending().whenComplete(
        () => _uploadFuture = null,
      );

  Future<bool> _doUploadPending() async {
    if (_deviceSerial == _noDevice) return false;
    final serial = _deviceSerial;

    try {
      final pending = await HiveService.unsyncedReadings();
      if (pending.isEmpty) return true;

      final readings = _firestore
          .collection('users')
          .doc(serial)
          .collection('readings');

      const int chunkSize = 400;
      for (var i = 0; i < pending.length; i += chunkSize) {
        final chunk = pending.sublist(
          i,
          math.min(i + chunkSize, pending.length),
        );

        final batch = _firestore.batch();
        for (final reading in chunk) {
          batch.set(
            readings.doc(reading.readingId),
            reading.toJson(),
            SetOptions(merge: true),
          );
        }
        // A commit that never completes (connected but no real internet)
        // must not block future uploads.
        await batch.commit().timeout(const Duration(seconds: 30));
        await HiveService.markSynced(chunk.map((r) => r.readingId));
      }
      return true;
    } catch (e) {
      debugPrint("Background upload failed: $e");
      return false;
    }
  }

  // -------------------------------------------------------------- helpers --

  /// Most recent heart-rate samples, oldest first, for sparklines.
  List<double> recentHeartRates({int count = 24}) {
    final n = math.min(count, _history.length);
    return [for (var i = n - 1; i >= 0; i--) _history[i].heartRate.toDouble()];
  }

  static int? _asInt(dynamic value) {
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    _autoFetchTimer?.cancel();
    _dataSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _deviceConnectionStateSubscription?.cancel();
    _bleService.dispose();
    _wifiService.dispose();
    super.dispose();
  }
}

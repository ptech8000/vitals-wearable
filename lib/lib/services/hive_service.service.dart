import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/vital_reading.dart';

class HiveService {
  static const String boxName = 'health_cache_box';

  /// Tracks which cached readings have already reached Firestore, so the
  /// background sync only uploads what is new instead of the entire cache.
  static const String syncBoxName = 'sync_state_box';

  static Box get _box => Hive.box(boxName);

  static Future<Box> _syncBox() async => Hive.isBoxOpen(syncBoxName)
      ? Hive.box(syncBoxName)
      : await Hive.openBox(syncBoxName);

  static Future<void> saveReadingLocally(VitalReading reading) async {
    await _box.put(reading.readingId, reading.toJson());
  }

  /// All cached readings, newest first.
  static List<VitalReading> getCachedReadings() {
    final readings = <VitalReading>[];

    for (final entry in _box.toMap().entries) {
      final data = entry.value;
      if (data is! Map) continue;
      try {
        readings.add(
          VitalReading.fromJson(
            entry.key.toString(),
            Map<String, dynamic>.from(data),
          ),
        );
      } catch (e) {
        debugPrint('Skipping unreadable cached reading ${entry.key}: $e');
      }
    }

    readings.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return readings;
  }

  /// Cached readings that have not been uploaded yet.
  static Future<List<VitalReading>> unsyncedReadings() async {
    final sync = await _syncBox();
    final pending = <VitalReading>[];

    for (final entry in _box.toMap().entries) {
      final id = entry.key.toString();
      final data = entry.value;
      if (data is! Map || sync.containsKey(id)) continue;
      try {
        pending.add(VitalReading.fromJson(id, Map<String, dynamic>.from(data)));
      } catch (_) {
        // Unreadable entries are skipped; they can never be uploaded anyway.
      }
    }
    return pending;
  }

  static Future<void> markSynced(Iterable<String> ids) async {
    final sync = await _syncBox();
    await sync.putAll({for (final id in ids) id: true});
  }
}

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

String getDeviceDisplayName(ScanResult scanResult) {
  // 1. Check platform local name
  if (scanResult.device.platformName.isNotEmpty) {
    return scanResult.device.platformName;
  }
  // 2. Check advertisement packet local name
  if (scanResult.advertisementData.advName.isNotEmpty) {
    return scanResult.advertisementData.advName;
  }
  // 3. Check complete local name in manufacturer data or service data keys
  if (scanResult.advertisementData.localName.isNotEmpty) {
    return scanResult.advertisementData.localName;
  }

  // Fallback to MAC/UUID if no name is broadcasted
  return "Unknown Wearable (${scanResult.device.remoteId.toString().substring(0, 5)}...)";
}

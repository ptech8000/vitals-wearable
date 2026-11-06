class DeviceModel {
  final String deviceId;
  final String deviceName;
  final String deviceSerial;
  final DateTime lastSeen;
  final int batteryLevel;
  final String firmwareVersion;
  final DateTime pairedAt;

  DeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.deviceSerial,
    required this.lastSeen,
    required this.batteryLevel,
    required this.firmwareVersion,
    required this.pairedAt,
  });

  /// [includePairedAt] lets callers leave `pairedAt` out of merge-writes so an
  /// existing pairing date is never overwritten by a later sync.
  Map<String, dynamic> toJson({bool includePairedAt = true}) => {
    'deviceName': deviceName,
    'deviceSerial': deviceSerial,
    'lastSeen': lastSeen.toIso8601String(),
    'batteryLevel': batteryLevel,
    'firmwareVersion': firmwareVersion,
    if (includePairedAt) 'pairedAt': pairedAt.toIso8601String(),
  };

  factory DeviceModel.fromJson(String deviceId, Map<String, dynamic> json) {
    return DeviceModel(
      deviceId: deviceId,
      deviceName: json['deviceName'] ?? '',
      deviceSerial: json['deviceSerial'] ?? '',
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'])
          : DateTime.now(),
      batteryLevel: json['batteryLevel'] ?? 0,
      firmwareVersion: json['firmwareVersion'] ?? '1.0.0',
      pairedAt: json['pairedAt'] != null
          ? DateTime.parse(json['pairedAt'])
          : DateTime.now(),
    );
  }
}

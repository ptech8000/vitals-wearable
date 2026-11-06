class VitalReading {
  final String readingId;
  final DateTime timestamp;
  final int heartRate;
  final int spo2;
  final double temperature;
  final int systolicBP;
  final int diastolicBP;
  final int respiratoryRate;
  final bool alertTriggered;
  final double dataQuality;

  VitalReading({
    required this.readingId,
    required this.timestamp,
    required this.heartRate,
    required this.spo2,
    required this.temperature,
    required this.systolicBP,
    required this.diastolicBP,
    required this.respiratoryRate,
    required this.alertTriggered,
    required this.dataQuality,
  });

  VitalReading copyWith({
    String? readingId,
    DateTime? timestamp,
    int? heartRate,
    int? spo2,
    double? temperature,
    int? systolicBP,
    int? diastolicBP,
    int? respiratoryRate,
    bool? alertTriggered,
    double? dataQuality,
  }) {
    return VitalReading(
      readingId: readingId ?? this.readingId,
      timestamp: timestamp ?? this.timestamp,
      heartRate: heartRate ?? this.heartRate,
      spo2: spo2 ?? this.spo2,
      temperature: temperature ?? this.temperature,
      systolicBP: systolicBP ?? this.systolicBP,
      diastolicBP: diastolicBP ?? this.diastolicBP,
      respiratoryRate: respiratoryRate ?? this.respiratoryRate,
      alertTriggered: alertTriggered ?? this.alertTriggered,
      dataQuality: dataQuality ?? this.dataQuality,
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'heartRate': heartRate,
    'spo2': spo2,
    'temperature': temperature,
    'systolicBP': systolicBP,
    'diastolicBP': diastolicBP,
    'respiratoryRate': respiratoryRate,
    'alertTriggered': alertTriggered,
    'dataQuality': dataQuality,
  };

  factory VitalReading.fromJson(String readingId, Map<String, dynamic> json) {
    return VitalReading(
      readingId: readingId,
      timestamp: json['timestamp'] != null
          ? (DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now())
          : DateTime.now(),
      heartRate: (json['heartRate'] as num?)?.round() ?? 0,
      spo2: (json['spo2'] as num?)?.round() ?? 0,
      temperature: ((json['temperature'] ?? 0.0) as num).toDouble(),
      systolicBP: (json['systolicBP'] as num?)?.round() ?? 0,
      diastolicBP: (json['diastolicBP'] as num?)?.round() ?? 0,
      respiratoryRate: (json['respiratoryRate'] as num?)?.round() ?? 0,
      alertTriggered: json['alertTriggered'] ?? false,
      dataQuality: ((json['dataQuality'] ?? 100.0) as num).toDouble(),
    );
  }
}

abstract class RecordingExporter {
  String get targetLabel;

  Future<void> start(RecordingManifest manifest);

  void writeEeg(String csvRow);

  void writeQuality(String csvRow);

  void writeMems(String csvRow);

  void writeFpg(String csvRow);

  void writeRingAudio(String csvRow);

  void writeEvent(String csvRow);

  Future<String> finish();

  Future<void> discard();
}

class RecordingManifest {
  RecordingManifest({
    required this.sessionId,
    required this.subjectId,
    required this.protocol,
    required this.operatorName,
    required this.notes,
    required this.deviceName,
    required this.deviceAddress,
    required this.deviceFamily,
    required this.sampleRateHz,
    required this.channelLabels,
    required this.createdAtIso,
    required this.settings,
  });

  final String sessionId;
  final String subjectId;
  final String protocol;
  final String operatorName;
  final String notes;
  final String deviceName;
  final String deviceAddress;
  final String deviceFamily;
  final int sampleRateHz;
  final List<String> channelLabels;
  final String createdAtIso;
  final Map<String, Object?> settings;

  Map<String, Object?> toJson() => {
        'session_id': sessionId,
        'subject_id': subjectId,
        'protocol': protocol,
        'operator': operatorName,
        'notes': notes,
        'device': {
          'name': deviceName,
          'address': deviceAddress,
          'family': deviceFamily,
        },
        'sample_rate_hz': sampleRateHz,
        'channel_labels': channelLabels,
        'created_at_iso': createdAtIso,
        'settings': settings,
      };
}

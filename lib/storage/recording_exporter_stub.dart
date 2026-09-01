import 'recording_exporter_base.dart';

Future<String?> pickRecordingDirectory() async => null;

Future<String> getDefaultRecordingTargetLabel() async => 'Unavailable';

Future<RecordingExporter> buildRecordingExporter({
  required String sessionId,
  String? directoryPath,
}) async =>
    _UnavailableExporter();

class _UnavailableExporter implements RecordingExporter {
  @override
  String get targetLabel => 'Unavailable';

  @override
  Future<void> start(RecordingManifest manifest) async {}

  @override
  void writeEeg(String csvRow) {}

  @override
  void writeQuality(String csvRow) {}

  @override
  void writeMems(String csvRow) {}

  @override
  void writeFpg(String csvRow) {}

  @override
  void writeRingAudio(String csvRow) {}

  @override
  void writeEvent(String csvRow) {}

  @override
  Future<String> finish() async => targetLabel;

  @override
  Future<void> discard() async {}
}

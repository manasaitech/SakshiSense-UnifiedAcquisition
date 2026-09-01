import 'recording_exporter_base.dart';
import 'recording_exporter_stub.dart'
    if (dart.library.io) 'recording_exporter_io.dart'
    if (dart.library.html) 'recording_exporter_web.dart';
export 'recording_exporter_base.dart';

Future<String?> chooseRecordingDirectory() => pickRecordingDirectory();

Future<String> defaultRecordingTargetLabel() =>
    getDefaultRecordingTargetLabel();

Future<RecordingExporter> createRecordingExporter({
  required String sessionId,
  String? directoryPath,
}) =>
    buildRecordingExporter(sessionId: sessionId, directoryPath: directoryPath);

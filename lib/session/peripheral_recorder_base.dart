import '../ring/telemetry_models.dart';

class MicrophoneInput {
  const MicrophoneInput(this.id, this.label);
  final String id;
  final String label;
}

abstract class PeripheralRecorder {
  List<MicrophoneInput> get inputs;
  String? get selectedInputId;
  bool get isRecording;
  double get amplitudeDb;
  List<double> get amplitudeHistory;
  String get status;

  Future<void> refreshInputs();
  Future<void> disconnectInput();
  void selectInput(String? id);
  Future<void> start({required String sessionDirectory});
  Future<void> stop();
  void addRingSample(
    TelemetrySample sample,
    DateTime acquiredAt,
    int hostMonotonicUs,
  );
  Future<void> dispose();
}

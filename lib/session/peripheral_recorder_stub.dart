import '../ring/telemetry_models.dart';
import 'peripheral_recorder_base.dart';

PeripheralRecorder buildPeripheralRecorder(
        {required void Function() onChange}) =>
    _UnsupportedPeripheralRecorder();

class _UnsupportedPeripheralRecorder implements PeripheralRecorder {
  @override
  double get amplitudeDb => -160;
  @override
  List<double> get amplitudeHistory => const [];
  @override
  List<MicrophoneInput> get inputs => const [];
  @override
  bool get isRecording => false;
  @override
  String? get selectedInputId => null;
  @override
  String get status => 'Microphone file capture requires a native build';
  @override
  void addRingSample(
    TelemetrySample sample,
    DateTime acquiredAt,
    int hostMonotonicUs,
  ) {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> refreshInputs() async {}
  @override
  void selectInput(String? id) {}
  @override
  Future<void> start({required String sessionDirectory}) async {}
  @override
  Future<void> stop() async {}
}

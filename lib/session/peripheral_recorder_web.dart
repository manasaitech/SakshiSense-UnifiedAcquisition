// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'package:record/record.dart';

import '../ring/telemetry_models.dart';
import 'peripheral_recorder_base.dart';

PeripheralRecorder buildPeripheralRecorder(
        {required void Function() onChange}) =>
    _WebPeripheralRecorder(onChange);

class _WebPeripheralRecorder implements PeripheralRecorder {
  _WebPeripheralRecorder(this._onChange);

  final void Function() _onChange;
  final AudioRecorder _recorder = AudioRecorder();
  final List<InputDevice> _nativeInputs = [];
  final List<MicrophoneInput> _inputs = [];
  final List<double> _amplitudeHistory = [];
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  String? _selectedInputId;
  bool _isRecording = false;
  double _amplitudeDb = -160;
  String _status = 'Select Connect microphone';

  @override
  List<MicrophoneInput> get inputs => List.unmodifiable(_inputs);
  @override
  String? get selectedInputId => _selectedInputId;
  @override
  bool get isRecording => _isRecording;
  @override
  double get amplitudeDb => _amplitudeDb;
  @override
  List<double> get amplitudeHistory => List.unmodifiable(_amplitudeHistory);
  @override
  String get status => _status;

  @override
  Future<void> refreshInputs() async {
    try {
      if (!await _recorder.hasPermission()) {
        _status = 'Microphone permission denied';
        _onChange();
        return;
      }
      final devices = await _recorder.listInputDevices();
      _nativeInputs
        ..clear()
        ..addAll(devices);
      _inputs
        ..clear()
        ..addAll(devices.map((d) => MicrophoneInput(d.id, d.label)));
      if (_selectedInputId != null &&
          !_inputs.any((item) => item.id == _selectedInputId)) {
        _selectedInputId = null;
      }
      _status = _inputs.isEmpty
          ? 'Connected to browser default microphone'
          : 'Microphone connected • ${_inputs.length} input(s)';
    } catch (error) {
      _status = 'Microphone connection failed: $error';
    }
    _onChange();
  }

  @override
  void selectInput(String? id) {
    _selectedInputId = id;
    _onChange();
  }

  @override
  Future<void> disconnectInput() async {
    if (_isRecording) await stop();
    _selectedInputId = null;
    _amplitudeDb = -160;
    _amplitudeHistory.clear();
    _status = 'Microphone disconnected';
    _onChange();
  }

  @override
  Future<void> start({required String sessionDirectory}) async {
    if (!await _recorder.hasPermission()) {
      _status = 'Microphone permission denied; other sensors still recording';
      _onChange();
      return;
    }
    InputDevice? selected;
    for (final input in _nativeInputs) {
      if (input.id == _selectedInputId) selected = input;
    }
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 48000,
        numChannels: 1,
        device: selected,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
      path: '',
    );
    _isRecording = true;
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((value) {
      _amplitudeDb = value.current;
      _amplitudeHistory.add(value.current);
      if (_amplitudeHistory.length > 180) {
        _amplitudeHistory.removeRange(0, _amplitudeHistory.length - 180);
      }
      _onChange();
    });
    _status = 'Recording live browser microphone (48 kHz mono WAV)';
    _onChange();
  }

  @override
  void addRingSample(
    TelemetrySample sample,
    DateTime acquiredAt,
    int hostMonotonicUs,
  ) {}

  @override
  Future<void> stop() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final url = await _recorder.stop();
    if (url != null) {
      final anchor = html.AnchorElement(href: url)
        ..download = 'microphone.wav'
        ..style.display = 'none';
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
    }
    _status = 'Microphone recording downloaded';
    _onChange();
  }

  @override
  Future<void> dispose() async {
    if (_isRecording) await stop();
    await _recorder.dispose();
  }
}

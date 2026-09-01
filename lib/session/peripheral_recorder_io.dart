import 'dart:async';
import 'dart:io';

import 'package:record/record.dart';

import '../ring/telemetry_models.dart';
import 'peripheral_recorder_base.dart';

PeripheralRecorder buildPeripheralRecorder(
        {required void Function() onChange}) =>
    _IoPeripheralRecorder(onChange);

class _IoPeripheralRecorder implements PeripheralRecorder {
  _IoPeripheralRecorder(this._onChange);

  final void Function() _onChange;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final List<InputDevice> _nativeInputs = [];
  final List<MicrophoneInput> _inputs = [];
  IOSink? _ringSink;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  String? _selectedInputId;
  bool _isRecording = false;
  double _amplitudeDb = -160;
  final List<double> _amplitudeHistory = [];
  String _status = 'Microphone ready';

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
      if (!await _audioRecorder.hasPermission()) {
        _status = 'Microphone permission denied';
        _onChange();
        return;
      }
      final devices = await _audioRecorder.listInputDevices();
      _nativeInputs
        ..clear()
        ..addAll(devices);
      _inputs
        ..clear()
        ..addAll(
            devices.map((device) => MicrophoneInput(device.id, device.label)));
      if (_selectedInputId != null &&
          !_inputs.any((item) => item.id == _selectedInputId)) {
        _selectedInputId = null;
      }
      _status = _inputs.isEmpty
          ? 'System default microphone'
          : '${_inputs.length} microphone input(s)';
    } catch (error) {
      _status = 'Could not list microphones: $error';
    }
    _onChange();
  }

  @override
  void selectInput(String? id) {
    _selectedInputId = id;
    _onChange();
  }

  @override
  Future<void> start({required String sessionDirectory}) async {
    final directory = Directory(sessionDirectory);
    await directory.create(recursive: true);
    final ringFile =
        File('${directory.path}${Platform.pathSeparator}ring_raw.csv');
    _ringSink = ringFile.openWrite();
    _ringSink!.writeln(
      'acquired_iso,host_unix_us,host_monotonic_us,type,sequence,device_ms,red,ir,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw,audio_rms,audio_peak,zero_crossings,audio_samples,marker_label,marker_payload',
    );
    _isRecording = true;

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      _status = 'Microphone permission denied; ring and EEG still recording';
      _onChange();
      return;
    }
    InputDevice? selected;
    for (final input in _nativeInputs) {
      if (input.id == _selectedInputId) {
        selected = input;
        break;
      }
    }
    final audioPath =
        '${directory.path}${Platform.pathSeparator}microphone.wav';
    try {
      await _audioRecorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 48000,
          numChannels: 1,
          device: selected,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: audioPath,
      );
      _amplitudeSubscription = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((value) {
        _amplitudeDb = value.current;
        _amplitudeHistory.add(value.current);
        if (_amplitudeHistory.length > 180) {
          _amplitudeHistory.removeRange(0, _amplitudeHistory.length - 180);
        }
        _onChange();
      });
      _status = 'Recording raw microphone audio (48 kHz mono WAV)';
    } catch (error) {
      _status = 'Microphone failed ($error); ring and EEG still recording';
    }
    _onChange();
  }

  @override
  void addRingSample(
    TelemetrySample sample,
    DateTime acquiredAt,
    int hostMonotonicUs,
  ) {
    // Device audio is exported separately by the acquisition controller.
    if (sample is AudioSample) return;
    if (!_isRecording || _ringSink == null) return;
    _ringSink!.writeln([
      acquiredAt.toUtc().toIso8601String(),
      acquiredAt.microsecondsSinceEpoch,
      hostMonotonicUs,
      ...sample.toCsv(acquiredAt).split(',').skip(1),
    ].join(','));
  }

  @override
  Future<void> stop() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    await _ringSink?.flush();
    await _ringSink?.close();
    _ringSink = null;
    _amplitudeDb = -160;
    _amplitudeHistory.clear();
    _status = 'Recording saved';
    _onChange();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _audioRecorder.dispose();
  }
}

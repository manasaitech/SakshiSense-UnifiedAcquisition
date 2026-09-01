import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'recording_exporter_base.dart';

const _fallbackChannelLabels = ['O1', 'O2', 'T3', 'T4'];
const _eegBaseHeader =
    'session_id,sample_index,packet_num,packet_unwrapped,lost_before_sample,device_marker,app_marker,marker_source,marker_detail,device_elapsed_us,host_monotonic_us,host_unix_us,host_iso';
const _qualityBaseHeader =
    'session_id,kind,packet_num,packet_unwrapped,lost_packets,total_lost_packets,device_elapsed_us,host_monotonic_us,host_unix_us,host_iso';
const _memsHeader =
    'session_id,packet_num,packet_unwrapped,lost_before_sample,host_monotonic_us,host_unix_us,host_iso,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z';
const _fpgHeader =
    'session_id,packet_num,packet_unwrapped,lost_before_sample,host_monotonic_us,host_unix_us,host_iso,ir_amplitude,red_amplitude';
const _eventHeader =
    'session_id,host_monotonic_us,host_unix_us,host_iso,event,detail';
const _ringAudioHeader =
    'session_id,sequence,device_ms,host_monotonic_us,host_unix_us,host_iso,rms,peak,zero_crossings,sample_count';

Future<String?> pickRecordingDirectory() =>
    FilePicker.platform.getDirectoryPath();

Future<String> getDefaultRecordingTargetLabel() async {
  final dir = await _defaultRecordingDirectory();
  return dir.path;
}

Future<RecordingExporter> buildRecordingExporter({
  required String sessionId,
  String? directoryPath,
}) async {
  final root = directoryPath == null || directoryPath.isEmpty
      ? await _defaultRecordingDirectory()
      : Directory(directoryPath);
  final sessionDir =
      Directory('${root.path}${Platform.pathSeparator}$sessionId');
  return _IoRecordingExporter(sessionDir);
}

Future<Directory> _defaultRecordingDirectory() async {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.isNotEmpty) {
    return Directory(
      '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}UnifiedAcquisition',
    );
  }
  final documents = await getApplicationDocumentsDirectory();
  return Directory(
      '${documents.path}${Platform.pathSeparator}UnifiedAcquisition');
}

class _IoRecordingExporter implements RecordingExporter {
  _IoRecordingExporter(this._sessionDir);

  final Directory _sessionDir;
  IOSink? _eeg;
  IOSink? _quality;
  IOSink? _mems;
  IOSink? _fpg;
  IOSink? _events;
  IOSink? _ringAudio;

  @override
  String get targetLabel => _sessionDir.path;

  @override
  Future<void> start(RecordingManifest manifest) async {
    await _sessionDir.create(recursive: true);
    await File('${_sessionDir.path}${Platform.pathSeparator}manifest.json')
        .writeAsString(
            const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
    _eeg = File('${_sessionDir.path}${Platform.pathSeparator}eeg_raw.csv')
        .openWrite();
    _quality = File('${_sessionDir.path}${Platform.pathSeparator}quality.csv')
        .openWrite();
    _mems = File('${_sessionDir.path}${Platform.pathSeparator}mems.csv')
        .openWrite();
    _fpg =
        File('${_sessionDir.path}${Platform.pathSeparator}fpg.csv').openWrite();
    _events = File('${_sessionDir.path}${Platform.pathSeparator}events.csv')
        .openWrite();
    _ringAudio =
        File('${_sessionDir.path}${Platform.pathSeparator}ring_audio.csv')
            .openWrite();
    _eeg!.writeln(_buildEegHeader(manifest.channelLabels));
    _quality!.writeln(_buildQualityHeader(manifest.channelLabels));
    _mems!.writeln(_memsHeader);
    _fpg!.writeln(_fpgHeader);
    _events!.writeln(_eventHeader);
    _ringAudio!.writeln(_ringAudioHeader);
  }

  @override
  void writeEeg(String csvRow) => _eeg?.writeln(csvRow);

  @override
  void writeQuality(String csvRow) => _quality?.writeln(csvRow);

  @override
  void writeMems(String csvRow) => _mems?.writeln(csvRow);

  @override
  void writeFpg(String csvRow) => _fpg?.writeln(csvRow);

  @override
  void writeRingAudio(String csvRow) => _ringAudio?.writeln(csvRow);

  @override
  void writeEvent(String csvRow) => _events?.writeln(csvRow);

  @override
  Future<String> finish() async {
    final sinks = [_eeg, _quality, _mems, _fpg, _events, _ringAudio];
    for (final sink in sinks) {
      await sink?.flush();
      await sink?.close();
    }
    _eeg = null;
    _quality = null;
    _mems = null;
    _fpg = null;
    _events = null;
    _ringAudio = null;
    return _sessionDir.path;
  }

  @override
  Future<void> discard() async {
    await finish();
  }
}

String _buildEegHeader(List<String> channelLabels) {
  final labels = _normalizedChannelLabels(channelLabels);
  return [
    _eegBaseHeader,
    ...labels.map((label) => '${_columnName(label)}_v'),
    ...labels.map((label) => '${_columnName(label)}_uv'),
  ].join(',');
}

String _buildQualityHeader(List<String> channelLabels) {
  final labels = _normalizedChannelLabels(channelLabels);
  return [
    _qualityBaseHeader,
    ...labels.map(_columnName),
    ...List.generate(labels.length, (index) => 'ref${index + 1}'),
  ].join(',');
}

List<String> _normalizedChannelLabels(List<String> channelLabels) {
  final labels = List<String>.from(_fallbackChannelLabels);
  for (var i = 0; i < labels.length && i < channelLabels.length; i++) {
    final value = channelLabels[i].trim();
    if (value.isNotEmpty) labels[i] = value;
  }
  return labels;
}

String _columnName(String label) {
  final normalized = label
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return normalized.isEmpty ? 'channel' : normalized;
}

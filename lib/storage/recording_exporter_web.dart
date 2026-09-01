// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

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

Future<String?> pickRecordingDirectory() async => null;

Future<String> getDefaultRecordingTargetLabel() async => 'Browser downloads';

Future<RecordingExporter> buildRecordingExporter({
  required String sessionId,
  String? directoryPath,
}) async =>
    _WebRecordingExporter(sessionId);

class _WebRecordingExporter implements RecordingExporter {
  _WebRecordingExporter(this._sessionId);

  final String _sessionId;
  final StringBuffer _eeg = StringBuffer();
  final StringBuffer _quality = StringBuffer();
  final StringBuffer _mems = StringBuffer();
  final StringBuffer _fpg = StringBuffer();
  final StringBuffer _events = StringBuffer();
  final StringBuffer _ringAudio = StringBuffer();

  @override
  String get targetLabel => 'Browser downloads';

  @override
  Future<void> start(RecordingManifest manifest) async {
    _download(
      '$_sessionId-manifest.json',
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      'application/json',
    );
    _eeg.writeln(_buildEegHeader(manifest.channelLabels));
    _quality.writeln(_buildQualityHeader(manifest.channelLabels));
    _mems.writeln(_memsHeader);
    _fpg.writeln(_fpgHeader);
    _events.writeln(_eventHeader);
    _ringAudio.writeln(_ringAudioHeader);
  }

  @override
  void writeEeg(String csvRow) => _eeg.writeln(csvRow);

  @override
  void writeQuality(String csvRow) => _quality.writeln(csvRow);

  @override
  void writeMems(String csvRow) => _mems.writeln(csvRow);

  @override
  void writeFpg(String csvRow) => _fpg.writeln(csvRow);

  @override
  void writeRingAudio(String csvRow) => _ringAudio.writeln(csvRow);

  @override
  void writeEvent(String csvRow) => _events.writeln(csvRow);

  @override
  Future<String> finish() async {
    _download('$_sessionId-eeg_raw.csv', _eeg.toString(), 'text/csv');
    _download('$_sessionId-quality.csv', _quality.toString(), 'text/csv');
    _download('$_sessionId-mems.csv', _mems.toString(), 'text/csv');
    _download('$_sessionId-fpg.csv', _fpg.toString(), 'text/csv');
    _download('$_sessionId-events.csv', _events.toString(), 'text/csv');
    _download('$_sessionId-ring_audio.csv', _ringAudio.toString(), 'text/csv');
    return targetLabel;
  }

  @override
  Future<void> discard() async {}

  void _download(String filename, String content, String mimeType) {
    final bytes = utf8.encode(content);
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = filename
      ..click();
    html.Url.revokeObjectUrl(url);
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

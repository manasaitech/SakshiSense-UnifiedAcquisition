import 'dart:typed_data';
import 'dart:convert';

sealed class TelemetrySample {
  const TelemetrySample(this.sequence, this.deviceMs);
  final int sequence;
  final int deviceMs;
  String toCsv(DateTime receivedAt);
}

class PpgSample extends TelemetrySample {
  const PpgSample(super.sequence, super.deviceMs, this.red, this.ir);
  final int red, ir;

  static PpgSample? decode(List<int> bytes) {
    if (bytes.length != 16) return null;
    final b = ByteData.sublistView(Uint8List.fromList(bytes));
    if (b.getUint8(0) != 1 || b.getUint8(1) != 1) return null;
    return PpgSample(
      b.getUint16(2, Endian.little),
      b.getUint32(4, Endian.little),
      b.getUint32(8, Endian.little),
      b.getUint32(12, Endian.little),
    );
  }

  @override
  String toCsv(DateTime at) => [
        at.toIso8601String(),
        'ppg',
        sequence,
        deviceMs,
        red,
        ir,
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
      ].join(',');
}

class ImuSample extends TelemetrySample {
  const ImuSample(
    super.sequence,
    super.deviceMs,
    this.ax,
    this.ay,
    this.az,
    this.gx,
    this.gy,
    this.gz,
  );
  final int ax, ay, az, gx, gy, gz;

  static ImuSample? decode(List<int> bytes) {
    if (bytes.length != 20) return null;
    final b = ByteData.sublistView(Uint8List.fromList(bytes));
    if (b.getUint8(0) != 1 || b.getUint8(1) != 2) return null;
    return ImuSample(
      b.getUint16(2, Endian.little),
      b.getUint32(4, Endian.little),
      b.getInt16(8, Endian.little),
      b.getInt16(10, Endian.little),
      b.getInt16(12, Endian.little),
      b.getInt16(14, Endian.little),
      b.getInt16(16, Endian.little),
      b.getInt16(18, Endian.little),
    );
  }

  @override
  String toCsv(DateTime at) => [
        at.toIso8601String(),
        'imu',
        sequence,
        deviceMs,
        '',
        '',
        ax,
        ay,
        az,
        gx,
        gy,
        gz,
        '',
        '',
        '',
        '',
        '',
        '',
      ].join(',');
}

class AudioSample extends TelemetrySample {
  const AudioSample(
    super.sequence,
    super.deviceMs,
    this.rms,
    this.peak,
    this.zeroCrossings,
    this.sampleCount,
  );
  final int rms, peak, zeroCrossings, sampleCount;

  static AudioSample? decode(List<int> bytes) {
    if (bytes.length != 16) return null;
    final b = ByteData.sublistView(Uint8List.fromList(bytes));
    if (b.getUint8(0) != 1 || b.getUint8(1) != 3) return null;
    return AudioSample(
      b.getUint16(2, Endian.little),
      b.getUint32(4, Endian.little),
      b.getUint16(8, Endian.little),
      b.getUint16(10, Endian.little),
      b.getUint16(12, Endian.little),
      b.getUint16(14, Endian.little),
    );
  }

  @override
  String toCsv(DateTime at) => [
        at.toIso8601String(),
        'audio',
        sequence,
        deviceMs,
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        rms,
        peak,
        zeroCrossings,
        sampleCount,
        '',
        '',
      ].join(',');
}

class RecordedSample {
  const RecordedSample(this.receivedAt, this.sample);
  final DateTime receivedAt;
  final TelemetrySample sample;
}

class NetworkMarker extends TelemetrySample {
  const NetworkMarker({
    required this.label,
    required this.receivedAt,
    this.payload = const {},
    int sequence = 0,
  }) : super(sequence, 0);

  final String label;
  final DateTime receivedAt;
  final Map<String, dynamic> payload;

  @override
  String toCsv(DateTime at) {
    final safeLabel = _csv(label);
    final safePayload = _csv(jsonEncode(payload));
    return [
      at.toIso8601String(),
      'marker',
      sequence,
      0,
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      safeLabel,
      safePayload,
    ].join(',');
  }

  static String _csv(String value) => '"${value.replaceAll('"', '""')}"';
}

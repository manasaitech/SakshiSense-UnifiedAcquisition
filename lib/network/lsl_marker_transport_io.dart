import 'dart:async';
import 'dart:convert';

import 'package:liblsl/lsl.dart';

import 'lsl_marker_transport_base.dart';
import 'marker_transport.dart';

LslMarkerTransport buildLslMarkerTransport() => _NativeLslMarkerTransport();

class _LslInletHandle {
  const _LslInletHandle(this.info, this.inlet);
  final LSLStreamInfo info;
  final LSLInlet<dynamic> inlet;
}

class _NativeLslMarkerTransport implements LslMarkerTransport {
  final _markers = StreamController<IncomingMarker>.broadcast();
  final _inlets = <String, _LslInletHandle>{};
  final _pollers = <Future<void>>[];
  final _sourceBase =
      'unified_acquisition_${DateTime.now().microsecondsSinceEpoch}';

  bool _receiving = false;
  Future<void>? _discoveryFuture;
  LSLOutlet? _stringOutlet;
  LSLOutlet? _intOutlet;
  LSLStreamInfo? _stringInfo;
  LSLStreamInfo? _intInfo;
  String _status = 'LSL idle';

  @override
  Stream<IncomingMarker> get markers => _markers.stream;
  @override
  bool get supportsLsl => true;
  @override
  String get status => _status;

  @override
  Future<void> startReceiver() async {
    await stopReceiver();
    _receiving = true;
    _status = 'LSL resolving marker streams';
    _discoveryFuture = _discoverMarkers();
  }

  Future<void> _discoverMarkers() async {
    while (_receiving) {
      List<LSLStreamInfo> streams = const [];
      try {
        streams = await LSL.resolveStreams(waitTime: 1.0, maxStreams: 32);
        for (final info in streams) {
          if (!_receiving) {
            info.destroy();
            continue;
          }
          if (info.streamType != LSLContentType.markers ||
              info.sourceId.startsWith(_sourceBase)) {
            info.destroy();
            continue;
          }
          final key =
              '${info.sourceId}|${info.streamName}|${info.channelFormat.name}';
          if (_inlets.containsKey(key)) {
            info.destroy();
            continue;
          }
          try {
            final inlet = await LSL.createInlet<dynamic>(
              streamInfo: info,
              maxBuffer: 60,
              recover: true,
              createTimeout: 2.0,
            );
            final handle = _LslInletHandle(info, inlet);
            _inlets[key] = handle;
            _status = 'LSL receiving ${_inlets.length} marker stream(s)';
            _pollers.add(_pollInlet(handle));
          } catch (_) {
            info.destroy();
          }
        }
      } catch (_) {
        _status = 'LSL receiver waiting for marker streams';
      }
      if (_receiving) {
        await Future<void>.delayed(const Duration(milliseconds: 750));
      }
    }
  }

  Future<void> _pollInlet(_LslInletHandle handle) async {
    while (_receiving && !handle.inlet.destroyed) {
      try {
        final sample = await handle.inlet.pullSample(timeout: 0.25);
        if (sample.isEmpty) continue;
        final value = sample.data.first;
        final valueType = value is int ? 'int' : 'string';
        _markers.add(
          IncomingMarker(
            code: value.toString(),
            source: '${handle.info.streamName}/${handle.info.sourceId}',
            detail: jsonEncode({
              'value': value,
              'value_type': valueType,
              'lsl_timestamp': sample.timestamp,
              'stream': handle.info.streamName,
            }),
            receivedAt: DateTime.now().toUtc(),
          ),
        );
      } catch (_) {
        if (_receiving) {
          _status = 'LSL marker inlet interrupted';
        }
        break;
      }
    }
  }

  @override
  Future<void> stopReceiver() async {
    _receiving = false;
    await _discoveryFuture;
    _discoveryFuture = null;
    if (_pollers.isNotEmpty) {
      await Future.wait(_pollers.map((future) => future.catchError((_) {})));
    }
    _pollers.clear();
    for (final handle in _inlets.values) {
      await handle.inlet.destroy();
      handle.info.destroy();
    }
    _inlets.clear();
    _status = _stringOutlet == null ? 'LSL idle' : 'LSL outlet active';
  }

  @override
  Future<void> startOutlet() async {
    await stopOutlet();
    _stringInfo = await LSL.createStreamInfo(
      streamName: 'UnifiedMarkersString',
      streamType: LSLContentType.markers,
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.string,
      sourceId: '${_sourceBase}_string',
    );
    _intInfo = await LSL.createStreamInfo(
      streamName: 'UnifiedMarkersInt',
      streamType: LSLContentType.markers,
      channelCount: 1,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.int32,
      sourceId: '${_sourceBase}_int',
    );
    _stringOutlet = await LSL.createOutlet(
      streamInfo: _stringInfo!,
      chunkSize: 0,
      maxBuffer: 60,
    );
    _intOutlet = await LSL.createOutlet(
      streamInfo: _intInfo!,
      chunkSize: 0,
      maxBuffer: 60,
    );
    _status = 'LSL string/int marker outlets active';
  }

  @override
  void sendMarker(Object value, {String detail = ''}) {
    final numeric = value is int ? value : int.tryParse(value.toString());
    if (numeric != null &&
        numeric >= -2147483648 &&
        numeric <= 2147483647 &&
        _intOutlet != null) {
      unawaited(_intOutlet!.pushSample([numeric]).catchError((_) => -1));
      return;
    }
    if (_stringOutlet != null) {
      unawaited(
        _stringOutlet!.pushSample([value.toString()]).catchError((_) => -1),
      );
    }
  }

  @override
  Future<void> stopOutlet() async {
    await _stringOutlet?.destroy();
    await _intOutlet?.destroy();
    _stringOutlet = null;
    _intOutlet = null;
    _stringInfo?.destroy();
    _intInfo?.destroy();
    _stringInfo = null;
    _intInfo = null;
    _status = _receiving ? 'LSL receiver active' : 'LSL idle';
  }

  @override
  Future<void> dispose() async {
    await stopReceiver();
    await stopOutlet();
    await _markers.close();
  }
}

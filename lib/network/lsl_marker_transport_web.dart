// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'lsl_marker_transport_base.dart';
import 'marker_transport.dart';

LslMarkerTransport buildLslMarkerTransport() => _WebLslBridgeTransport();

class _WebLslBridgeTransport implements LslMarkerTransport {
  final _markers = StreamController<IncomingMarker>.broadcast();
  html.WebSocket? _socket;
  bool _receiver = false;
  bool _outlet = false;
  String _status = 'Local LSL bridge idle';

  @override
  Stream<IncomingMarker> get markers => _markers.stream;
  @override
  bool get supportsLsl => true;
  @override
  String get status => _status;

  Future<void> _connect() async {
    if (_socket?.readyState == html.WebSocket.OPEN) return;
    final socket = html.WebSocket('ws://127.0.0.1:15335');
    _socket = socket;
    final ready = Completer<void>();
    socket.onOpen.first.then((_) {
      _status = 'Connected to local LSL bridge';
      if (!ready.isCompleted) ready.complete();
      _sendConfig();
    });
    socket.onMessage.listen((event) {
      try {
        final data = jsonDecode(event.data.toString()) as Map<String, dynamic>;
        if (data['type'] == 'marker' && _receiver) {
          _markers.add(IncomingMarker(
            code: data['value'].toString(),
            source: data['source']?.toString() ?? 'lsl-bridge',
            detail: jsonEncode(data),
            receivedAt: DateTime.now().toUtc(),
          ));
        } else if (data['type'] == 'status') {
          _status = data['message']?.toString() ?? _status;
        }
      } catch (_) {}
    });
    socket.onError.first.then((_) {
      _status = 'LSL bridge unavailable — run npm start in lsl_bridge';
      if (!ready.isCompleted) ready.completeError(StateError(_status));
    });
    socket.onClose.first.then((_) {
      _socket = null;
      _status = 'Local LSL bridge disconnected';
    });
    await ready.future.timeout(const Duration(seconds: 3));
  }

  void _sendConfig() {
    if (_socket?.readyState != html.WebSocket.OPEN) return;
    _socket!.send(jsonEncode({
      'type': 'configure',
      'receive': _receiver,
      'outlet': _outlet,
    }));
  }

  @override
  Future<void> startReceiver() async {
    _receiver = true;
    await _connect();
    _sendConfig();
    _status = 'LSL bridge receiver active';
  }

  @override
  Future<void> stopReceiver() async {
    _receiver = false;
    _sendConfig();
    _status = _outlet ? 'LSL bridge outlet active' : 'Local LSL bridge idle';
  }

  @override
  Future<void> startOutlet() async {
    _outlet = true;
    await _connect();
    _sendConfig();
    _status = 'LSL bridge marker outlet active';
  }

  @override
  Future<void> stopOutlet() async {
    _outlet = false;
    _sendConfig();
    _status =
        _receiver ? 'LSL bridge receiver active' : 'Local LSL bridge idle';
  }

  @override
  void sendMarker(Object value, {String detail = ''}) {
    if (!_outlet || _socket?.readyState != html.WebSocket.OPEN) return;
    _socket!.send(jsonEncode({
      'type': 'marker',
      'value': value,
      'detail': detail,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
    }));
  }

  @override
  Future<void> dispose() async {
    _socket?.close();
    await _markers.close();
  }
}

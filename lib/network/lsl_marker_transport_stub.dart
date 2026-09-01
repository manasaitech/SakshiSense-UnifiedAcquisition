import 'dart:async';

import 'lsl_marker_transport_base.dart';
import 'marker_transport.dart';

LslMarkerTransport buildLslMarkerTransport() => _UnsupportedLslTransport();

class _UnsupportedLslTransport implements LslMarkerTransport {
  final _markers = StreamController<IncomingMarker>.broadcast();

  @override
  Stream<IncomingMarker> get markers => _markers.stream;
  @override
  bool get supportsLsl => false;
  @override
  String get status => 'LSL unavailable on web';
  @override
  Future<void> startReceiver() async {}
  @override
  Future<void> stopReceiver() async {}
  @override
  Future<void> startOutlet() async {}
  @override
  Future<void> stopOutlet() async {}
  @override
  void sendMarker(Object value, {String detail = ''}) {}
  @override
  Future<void> dispose() => _markers.close();
}

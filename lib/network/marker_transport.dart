import 'marker_transport_stub.dart'
    if (dart.library.io) 'marker_transport_io.dart'
    if (dart.library.html) 'marker_transport_web.dart';

class IncomingMarker {
  IncomingMarker({
    required this.code,
    required this.source,
    required this.detail,
    required this.receivedAt,
  });

  final String code;
  final String source;
  final String detail;
  final DateTime receivedAt;
}

abstract class MarkerTransport {
  Stream<IncomingMarker> get markers;

  bool get supportsNetwork;

  Future<void> startMarkerReceiver(int port);

  Future<void> stopMarkerReceiver();

  Future<void> startOutlet({
    required String host,
    required int port,
  });

  Future<void> stopOutlet();

  void sendEeg(Map<String, Object?> sample);

  void sendEvent(Map<String, Object?> event);

  Future<void> dispose();
}

MarkerTransport createMarkerTransport() => buildMarkerTransport();

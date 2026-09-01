import 'marker_transport.dart';

abstract class LslMarkerTransport {
  Stream<IncomingMarker> get markers;
  bool get supportsLsl;
  String get status;

  Future<void> startReceiver();
  Future<void> stopReceiver();
  Future<void> startOutlet();
  Future<void> stopOutlet();
  void sendMarker(Object value, {String detail = ''});
  Future<void> dispose();
}

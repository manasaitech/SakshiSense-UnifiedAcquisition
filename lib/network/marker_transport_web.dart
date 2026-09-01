import 'marker_transport.dart';

MarkerTransport buildMarkerTransport() => _WebMarkerTransport();

class _WebMarkerTransport implements MarkerTransport {
  @override
  Stream<IncomingMarker> get markers => const Stream.empty();

  @override
  bool get supportsNetwork => false;

  @override
  Future<void> startMarkerReceiver(int port) async {}

  @override
  Future<void> stopMarkerReceiver() async {}

  @override
  Future<void> startOutlet({required String host, required int port}) async {}

  @override
  Future<void> stopOutlet() async {}

  @override
  void sendEeg(Map<String, Object?> sample) {}

  @override
  void sendEvent(Map<String, Object?> event) {}

  @override
  Future<void> dispose() async {}
}

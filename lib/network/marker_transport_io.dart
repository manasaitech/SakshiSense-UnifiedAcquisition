import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'marker_transport.dart';

MarkerTransport buildMarkerTransport() => _UdpMarkerTransport();

class _UdpMarkerTransport implements MarkerTransport {
  final _markerController = StreamController<IncomingMarker>.broadcast();
  RawDatagramSocket? _receiver;
  RawDatagramSocket? _outlet;
  InternetAddress? _outletAddress;
  int? _outletPort;

  @override
  Stream<IncomingMarker> get markers => _markerController.stream;

  @override
  bool get supportsNetwork => true;

  @override
  Future<void> startMarkerReceiver(int port) async {
    await stopMarkerReceiver();
    _receiver = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    _receiver!.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = _receiver!.receive()) != null) {
        final text = utf8.decode(datagram!.data, allowMalformed: true).trim();
        if (text.isEmpty) continue;
        final marker = _decodeMarker(
          text,
          '${datagram.address.address}:${datagram.port}',
        );
        _markerController.add(marker);
      }
    });
  }

  @override
  Future<void> stopMarkerReceiver() async {
    _receiver?.close();
    _receiver = null;
  }

  @override
  Future<void> startOutlet({required String host, required int port}) async {
    await stopOutlet();
    final parsed = InternetAddress.tryParse(host);
    if (parsed != null) {
      _outletAddress = parsed;
    } else {
      final addresses = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      );
      if (addresses.isEmpty) {
        throw SocketException('Host not found: $host');
      }
      _outletAddress = addresses.first;
    }
    _outletPort = port;
    _outlet = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _outlet!.broadcastEnabled = true;
  }

  @override
  Future<void> stopOutlet() async {
    _outlet?.close();
    _outlet = null;
    _outletAddress = null;
    _outletPort = null;
  }

  @override
  void sendEeg(Map<String, Object?> sample) {
    _send({'type': 'eeg', ...sample});
  }

  @override
  void sendEvent(Map<String, Object?> event) {
    _send({'type': 'event', ...event});
  }

  void _send(Map<String, Object?> payload) {
    final socket = _outlet;
    final address = _outletAddress;
    final port = _outletPort;
    if (socket == null || address == null || port == null) return;
    final bytes = utf8.encode('${jsonEncode(payload)}\n');
    socket.send(bytes, address, port);
  }

  IncomingMarker _decodeMarker(String text, String source) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final code = decoded['marker'] ?? decoded['code'] ?? decoded['event'];
        final detail =
            decoded['detail'] ?? decoded['label'] ?? decoded['trial'];
        return IncomingMarker(
          code: (code ?? text).toString(),
          source: source,
          detail: detail?.toString() ?? text,
          receivedAt: DateTime.now().toUtc(),
        );
      }
    } catch (_) {}
    return IncomingMarker(
      code: text,
      source: source,
      detail: text,
      receivedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> dispose() async {
    await stopMarkerReceiver();
    await stopOutlet();
    await _markerController.close();
  }
}

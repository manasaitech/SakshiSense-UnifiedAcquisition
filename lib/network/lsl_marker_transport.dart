import 'lsl_marker_transport_stub.dart'
    if (dart.library.io) 'lsl_marker_transport_io.dart'
    if (dart.library.html) 'lsl_marker_transport_web.dart';
import 'lsl_marker_transport_base.dart';
export 'lsl_marker_transport_base.dart';

LslMarkerTransport createLslMarkerTransport() => buildLslMarkerTransport();

import 'marker_store_stub.dart'
    if (dart.library.io) 'marker_store_io.dart'
    if (dart.library.html) 'marker_store_web.dart';

Future<List<String>> loadMarkerButtons() => loadStoredMarkerButtons();

Future<void> saveMarkerButtons(List<String> markers) =>
    saveStoredMarkerButtons(markers);

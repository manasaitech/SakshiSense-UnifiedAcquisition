import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<List<String>> loadStoredMarkerButtons() async {
  final file = await _markerFile();
  if (!await file.exists()) return const [];
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is List) {
      return decoded
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return const [];
}

Future<void> saveStoredMarkerButtons(List<String> markers) async {
  final file = await _markerFile();
  await file.parent.create(recursive: true);
  final normalized =
      markers.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
  await file
      .writeAsString(const JsonEncoder.withIndent('  ').convert(normalized));
}

Future<File> _markerFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}marker_buttons.json');
}

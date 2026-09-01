// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

const _key = 'brainbit_marker_buttons';

Future<List<String>> loadStoredMarkerButtons() async {
  final value = html.window.localStorage[_key];
  if (value == null || value.isEmpty) return const [];
  try {
    final decoded = jsonDecode(value);
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
  final normalized =
      markers.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
  html.window.localStorage[_key] = jsonEncode(normalized);
}

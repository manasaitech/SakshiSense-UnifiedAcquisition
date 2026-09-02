import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:unified_acquisition_app/ring/signal_processing.dart';
import 'package:unified_acquisition_app/ring/telemetry_models.dart';

List<PpgSample> syntheticPpg({bool inverted = false, int bpm = 72}) {
  const sampleRate = 100;
  const seconds = 30;
  final frequency = bpm / 60;
  final polarity = inverted ? -1.0 : 1.0;
  return List.generate(sampleRate * seconds, (index) {
    final time = index / sampleRate;
    final pulse = polarity *
        (3200 * math.sin(2 * math.pi * frequency * time) +
            720 * math.sin(4 * math.pi * frequency * time + .25));
    final drift = 1000 * math.sin(2 * math.pi * .07 * time);
    final noise = 70 * math.sin(2 * math.pi * 19 * time);
    return PpgSample(
      index & 0xffff,
      index * 10,
      (48000 + pulse * .72 + drift + noise).round(),
      (57000 + pulse + drift + noise).round(),
    );
  });
}

void main() {
  for (final inverted in [false, true]) {
    test('detects pulse with ${inverted ? 'inverted' : 'normal'} polarity', () {
      final result = RingSignalProcessing.analyze(
        syntheticPpg(inverted: inverted),
      );
      expect(result.quality, greaterThanOrEqualTo(35));
      expect(result.heartRate, closeTo(72, 1.5));
      expect(result.beatCount, greaterThan(20));
      expect(result.spo2, isNotNull);
    });
  }

  test('withholds metrics for absent contact', () {
    final samples = List.generate(
      3000,
      (i) => PpgSample(i & 0xffff, i * 10, 40, 45),
    );
    final result = RingSignalProcessing.analyze(samples);
    expect(result.quality, 0);
    expect(result.heartRate, isNull);
    expect(result.spo2, isNull);
  });
}

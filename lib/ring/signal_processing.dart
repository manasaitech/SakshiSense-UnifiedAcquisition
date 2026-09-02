import 'dart:math' as math;

import 'telemetry_models.dart';

/// Motion-aware, sampling-rate-independent PPG analysis for the MAX30102.
///
/// Metrics are deliberately withheld when contact, timing, or beat consistency
/// is poor. A blank value is safer for acquisition work than a plausible but
/// fabricated number.
class RingPpgAnalysis {
  const RingPpgAnalysis({
    required this.filtered,
    required this.heartRate,
    required this.rmssd,
    required this.spo2,
    required this.quality,
    required this.beatCount,
  });

  final List<double> filtered;
  final double? heartRate;
  final double? rmssd;
  final double? spo2;
  final int quality;
  final int beatCount;

  String get qualityLabel => switch (quality) {
        >= 80 => 'Excellent',
        >= 60 => 'Good',
        >= 35 => 'Fair',
        > 0 => 'Poor',
        _ => 'No signal',
      };
}

class _BeatCandidate {
  const _BeatCandidate(this.rr, this.score, this.beatCount);
  final List<double> rr;
  final double score;
  final int beatCount;
}

class RingSignalProcessing {
  static RingPpgAnalysis analyze(
    List<PpgSample> allSamples, {
    Duration window = const Duration(seconds: 30),
  }) {
    if (allSamples.length < 20) return _empty();
    final newest = allSamples.last.deviceMs;
    final samples = allSamples
        .where((sample) => newest - sample.deviceMs <= window.inMilliseconds)
        .toList(growable: false);
    if (samples.length < 20) return _empty();

    final periodMs = _samplePeriodMs(samples);
    final expected = window.inMilliseconds / periodMs;
    final coverage = (samples.length / expected).clamp(0.0, 1.0);
    final ir = samples.map((sample) => sample.ir.toDouble()).toList();
    final red = samples.map((sample) => sample.red.toDouble()).toList();
    final filtered = _filter(ir, periodMs);
    final quality = _quality(ir, filtered, samples, coverage);

    _BeatCandidate? beat;
    if (quality >= 35 && samples.length * periodMs >= 6000) {
      final positive = _beats(samples, filtered, periodMs);
      final negative = _beats(
        samples,
        filtered.map((value) => -value).toList(growable: false),
        periodMs,
      );
      beat = positive == null
          ? negative
          : negative == null || positive.score >= negative.score
              ? positive
              : negative;
    }

    final medianRr = beat == null ? null : _median(beat.rr);
    final heartRate = medianRr == null ? null : 60000 / medianRr;
    double? rmssd;
    if (beat != null && beat.rr.length >= 5) {
      var squareSum = 0.0;
      for (var i = 1; i < beat.rr.length; i++) {
        final delta = beat.rr[i] - beat.rr[i - 1];
        squareSum += delta * delta;
      }
      rmssd = math.sqrt(squareSum / (beat.rr.length - 1));
    }

    return RingPpgAnalysis(
      filtered: filtered,
      heartRate: heartRate?.clamp(35, 220).toDouble(),
      rmssd: rmssd,
      spo2: quality >= 55 ? _spo2(red, ir) : null,
      quality: quality,
      beatCount: beat?.beatCount ?? 0,
    );
  }

  static RingPpgAnalysis _empty() => const RingPpgAnalysis(
        filtered: [],
        heartRate: null,
        rmssd: null,
        spo2: null,
        quality: 0,
        beatCount: 0,
      );

  static List<double> _filter(List<double> input, double periodMs) {
    // A one-pole high pass followed by two low-pass stages gives a stable
    // pulse band across the ring's observed 25–100 Hz sampling rates.
    final baselineAlpha = 1 - math.exp(-periodMs / 1100);
    final smoothAlpha = 1 - math.exp(-periodMs / 45);
    var baseline = input.first;
    var smooth1 = 0.0;
    var smooth2 = 0.0;
    final output = <double>[];
    for (final value in input) {
      baseline += baselineAlpha * (value - baseline);
      smooth1 += smoothAlpha * ((value - baseline) - smooth1);
      smooth2 += smoothAlpha * (smooth1 - smooth2);
      output.add(smooth2);
    }
    final center = _median(output);
    final mad = _median(output.map((v) => (v - center).abs()).toList());
    final scale = math.max(1.0, mad * 1.4826);
    return output
        .map((value) => ((value - center) / scale).clamp(-6.0, 6.0))
        .toList(growable: false);
  }

  static int _quality(
    List<double> raw,
    List<double> filtered,
    List<PpgSample> samples,
    double coverage,
  ) {
    final mean = _mean(raw);
    if (mean < 500 || mean > 260000) return 0;
    final perfusion = _std(raw) / mean;
    final clipped =
        raw.where((v) => v <= 100 || v >= 261000).length / raw.length;
    var timingFaults = 0;
    final period = _samplePeriodMs(samples);
    for (var i = 1; i < samples.length; i++) {
      final delta = samples[i].deviceMs - samples[i - 1].deviceMs;
      if (delta <= 0 || delta > period * 2.5) timingFaults++;
    }
    final timingPenalty = timingFaults / math.max(1, samples.length - 1);
    final dynamic = _std(filtered);
    var score = 20.0;
    score += (perfusion * 12000).clamp(0.0, 48.0);
    score += (dynamic * 12).clamp(0.0, 22.0);
    score -= clipped * 100;
    score -= timingPenalty * 120;
    score *= coverage < .35 ? .55 : 1;
    return score.round().clamp(0, 100);
  }

  static _BeatCandidate? _beats(
    List<PpgSample> samples,
    List<double> y,
    double periodMs,
  ) {
    final minDistance = math.max(2, (300 / periodMs).round());
    final prominenceWidth = math.max(2, (180 / periodMs).round());
    final center = _median(y);
    final sigma = math.max(
      .15,
      _median(y.map((v) => (v - center).abs()).toList()) * 1.4826,
    );
    final threshold = center + math.max(.35, sigma * .4);
    final peaks = <double>[];
    final amplitudes = <double>[];
    for (var i = 2; i < y.length - 2; i++) {
      if (y[i] < threshold || y[i] < y[i - 1] || y[i] <= y[i + 1]) continue;
      var leftMin = y[i - 1];
      var rightMin = y[i + 1];
      for (var j = math.max(0, i - prominenceWidth); j < i; j++) {
        leftMin = math.min(leftMin, y[j]);
      }
      for (var j = i + 1;
          j <= math.min(y.length - 1, i + prominenceWidth);
          j++) {
        rightMin = math.min(rightMin, y[j]);
      }
      if (y[i] - math.max(leftMin, rightMin) < math.max(.3, sigma * .45)) {
        continue;
      }
      final denominator = y[i - 1] - 2 * y[i] + y[i + 1];
      final offset = denominator.abs() < 1e-9
          ? 0.0
          : (0.5 * (y[i - 1] - y[i + 1]) / denominator).clamp(-.5, .5);
      final time = samples[i].deviceMs + offset * periodMs;
      if (peaks.isNotEmpty && time - peaks.last < minDistance * periodMs) {
        if (y[i] > amplitudes.last) {
          peaks[peaks.length - 1] = time;
          amplitudes[amplitudes.length - 1] = y[i];
        }
      } else {
        peaks.add(time);
        amplitudes.add(y[i]);
      }
    }
    if (peaks.length < 5) return null;
    final rr = <double>[];
    for (var i = 1; i < peaks.length; i++) {
      final interval = peaks[i] - peaks[i - 1];
      if (interval >= 300 && interval <= 1715) rr.add(interval);
    }
    if (rr.length < 4) return null;
    final median = _median(rr);
    final mad = _median(rr.map((v) => (v - median).abs()).toList());
    final tolerance = math.max(110.0, math.max(mad * 3.5, median * .18));
    final clean = rr.where((v) => (v - median).abs() <= tolerance).toList();
    if (clean.length < 4) return null;
    final bpm = 60000 / _median(clean);
    if (bpm < 35 || bpm > 220) return null;
    final retained = clean.length / rr.length;
    final score = clean.length + retained * 5 - mad / math.max(1, median) * 10;
    return _BeatCandidate(clean, score, peaks.length);
  }

  static double? _spo2(List<double> red, List<double> ir) {
    final redMean = _mean(red);
    final irMean = _mean(ir);
    if (redMean <= 0 || irMean <= 0) return null;
    final irAc = _robustAc(ir);
    final redAc = _robustAc(red);
    if (irAc <= 1 || redAc <= 1) return null;
    final ratio = (redAc / redMean) / (irAc / irMean);
    if (!ratio.isFinite || ratio < .2 || ratio > 1.8) return null;
    // MAX30102 ratio-of-ratios estimate. It is explicitly an estimate until
    // calibrated against a reference pulse oximeter for this optical stack.
    return (110 - 25 * ratio).clamp(70.0, 100.0);
  }

  static double _robustAc(List<double> values) {
    final center = _median(values);
    return _median(values.map((v) => (v - center).abs()).toList()) * 1.4826;
  }

  static double _samplePeriodMs(List<PpgSample> samples) {
    final deltas = <double>[];
    for (var i = 1; i < samples.length; i++) {
      final delta = samples[i].deviceMs - samples[i - 1].deviceMs;
      if (delta > 0 && delta < 100) deltas.add(delta.toDouble());
    }
    return deltas.isEmpty ? 10 : _median(deltas).clamp(5, 40);
  }

  static double _mean(List<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  static double _std(List<double> values) {
    if (values.length < 2) return 0;
    final mean = _mean(values);
    return math.sqrt(
        values.fold<double>(0, (sum, v) => sum + math.pow(v - mean, 2)) /
            (values.length - 1));
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

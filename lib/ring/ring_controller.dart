import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'telemetry_models.dart';

const ringServiceUuid = '7f510000-1b15-4a80-b6d0-4f4f53414b53';
const ringPpgUuid = '7f510001-1b15-4a80-b6d0-4f4f53414b53';
const ringImuUuid = '7f510002-1b15-4a80-b6d0-4f4f53414b53';
const ringAudioUuid = '7f510003-1b15-4a80-b6d0-4f4f53414b53';

class RingDevice {
  const RingDevice(this.device);
  final BleDevice device;

  String get id => device.deviceId;
  String get name => (device.name?.isNotEmpty ?? false)
      ? device.name!
      : (device.rawName?.isNotEmpty ?? false)
          ? device.rawName!
          : 'SakshiRing';
  int get rssi => device.rssi ?? 0;
}

typedef RingSampleHandler = void Function(
  TelemetrySample sample,
  DateTime acquiredAt,
);

/// Minimal Sakshi Ring acquisition controller used by the unified session.
class RingController extends ChangeNotifier {
  RingController({this.onSample}) {
    UniversalBle.onConnectionChange = _onConnectionChange;
    UniversalBle.onValueChange = _onValueChange;
    _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_dirty) {
        _dirty = false;
        notifyListeners();
      }
    });
  }

  RingSampleHandler? onSample;
  final devices = <RingDevice>[];
  final ppg = <PpgSample>[];
  final imu = <ImuSample>[];
  final audioFeatures = <AudioSample>[];
  final _subscriptions = <({String service, String characteristic})>[];

  BleDevice? connectedDevice;
  bool isScanning = false;
  bool isConnecting = false;
  String status = 'Ring disconnected';
  int packets = 0;
  int ppgPackets = 0;
  int imuPackets = 0;
  int audioPackets = 0;
  DateTime? lastPpgAt;
  DateTime? lastImuAt;
  DateTime? lastAudioAt;
  Timer? _scanTimer;
  Timer? _uiTimer;
  bool _dirty = false;
  int _scanSession = 0;
  int? _lastDeviceMs;
  int _deviceWrapMs = 0;
  int? _deviceToHostOffsetUs;

  bool get isConnected => connectedDevice != null;

  bool streamAlive(DateTime? timestamp) =>
      timestamp != null && DateTime.now().difference(timestamp).inSeconds < 2;

  double get onboardSoundLevelDb {
    final rms = audioFeatures.isEmpty ? 0 : audioFeatures.last.rms;
    return rms <= 0 ? -96 : 20 * math.log(rms / 32768.0) / math.ln10;
  }

  String get onboardSoundClass {
    final db = onboardSoundLevelDb;
    return db < -55
        ? 'Quiet'
        : db < -35
            ? 'Ambient'
            : db < -18
                ? 'Loud'
                : 'Very loud';
  }

  double get motionLevel {
    if (imu.isEmpty) return 0;
    final recent = imu.skip(math.max(0, imu.length - 50));
    var sum = 0.0;
    var count = 0;
    for (final sample in recent) {
      final x = sample.ax * 0.000061;
      final y = sample.ay * 0.000061;
      final z = sample.az * 0.000061;
      final dynamicG = math.max(
        0.0,
        (math.sqrt(x * x + y * y + z * z) - 1).abs(),
      );
      sum += dynamicG * dynamicG;
      count++;
    }
    return count == 0 ? 0 : math.sqrt(sum / count);
  }

  String get activity {
    final motion = motionLevel;
    return motion < 0.035
        ? 'Still'
        : motion < 0.12
            ? 'Light movement'
            : motion < 0.35
                ? 'Active'
                : 'High motion';
  }

  Future<void> scan() async {
    if (isScanning) {
      await _finishScan();
      return;
    }
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
    devices.clear();
    final session = ++_scanSession;
    isScanning = true;
    status = 'Scanning for SakshiRing…';
    notifyListeners();
    UniversalBle.onScanResult = (device) {
      if (!isScanning || session != _scanSession) return;
      final result = RingDevice(device);
      final resultId = _canonicalBleId(result.id);
      var index = devices.indexWhere(
        (item) => _canonicalBleId(item.id) == resultId,
      );
      if (index < 0 &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.windows &&
          _canonicalBleName(result.name) == 'sakshiring') {
        index = devices.indexWhere(
          (item) => _canonicalBleName(item.name) == 'sakshiring',
        );
      }
      index < 0 ? devices.add(result) : devices[index] = result;
      notifyListeners();
    };
    try {
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: const [ringServiceUuid]),
      );
      if (kIsWeb) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (devices.isNotEmpty) {
          isScanning = false;
          UniversalBle.onScanResult = null;
          await connect(devices.first);
          return;
        }
        isScanning = false;
        UniversalBle.onScanResult = null;
        status = 'Bluetooth chooser closed without selecting SakshiRing';
        notifyListeners();
      } else {
        _scanTimer = Timer(const Duration(seconds: 10), _finishScan);
      }
    } catch (error) {
      isScanning = false;
      status = _friendlyScanError(error);
      notifyListeners();
    }
  }

  Future<void> _finishScan() async {
    _scanTimer?.cancel();
    _scanSession++;
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
    UniversalBle.onScanResult = null;
    isScanning = false;
    status = devices.isEmpty ? 'No SakshiRing found' : 'Select a ring';
    notifyListeners();
  }

  String _friendlyScanError(Object error) {
    final detail = error.toString();
    if (kIsWeb) {
      final lower = detail.toLowerCase();
      if (lower.contains('notfounderror') || lower.contains('cancel')) {
        return 'Bluetooth chooser cancelled — scan again and select SakshiRing';
      }
      return 'Web Bluetooth scan failed. Use this HTTPS page in Chrome or '
          'Edge and allow Bluetooth access. ($detail)';
    }
    return 'Ring scan failed: $detail';
  }

  Future<void> connect(RingDevice result) async {
    await _finishScan();
    _subscriptions.clear();
    isConnecting = true;
    status = 'Connecting ring…';
    notifyListeners();
    _resetClock();
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        if (attempt > 1) {
          status = 'Bluetooth link dropped — retrying ($attempt/3)…';
          notifyListeners();
          try {
            await UniversalBle.disconnect(result.id);
          } catch (_) {}
          await Future<void>.delayed(Duration(milliseconds: 450 * attempt));
        }
        await UniversalBle.connect(
          result.id,
          timeout: const Duration(seconds: 15),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final services = await UniversalBle.discoverServices(
          result.id,
          timeout: const Duration(seconds: 10),
        );
        final service = services.firstWhere(
          (item) => item.uuid.toLowerCase() == ringServiceUuid,
        );
        _subscriptions.clear();
        for (final characteristic in service.characteristics) {
          final uuid = characteristic.uuid.toLowerCase();
          if (uuid != ringPpgUuid &&
              uuid != ringImuUuid &&
              uuid != ringAudioUuid) {
            continue;
          }
          await UniversalBle.subscribeNotifications(
            result.id,
            service.uuid,
            characteristic.uuid,
            timeout: const Duration(seconds: 5),
          );
          _subscriptions.add((
            service: service.uuid,
            characteristic: characteristic.uuid,
          ));
        }
        final uuids =
            _subscriptions.map((item) => item.characteristic.toLowerCase());
        if (!uuids.contains(ringPpgUuid) || !uuids.contains(ringImuUuid)) {
          throw StateError('Ring is missing required PPG/IMU characteristics');
        }
        connectedDevice = result.device;
        status = _subscriptions.any(
          (item) => item.characteristic.toLowerCase() == ringAudioUuid,
        )
            ? 'Ring streaming • onboard audio available'
            : 'Ring streaming';
        isConnecting = false;
        notifyListeners();
        return;
      } catch (error) {
        lastError = error;
      }
    }
    status = 'Could not connect to SakshiRing: ${lastError ?? 'unknown error'}';
    try {
      await UniversalBle.disconnect(result.id);
    } catch (_) {}
    isConnecting = false;
    notifyListeners();
  }

  void _onConnectionChange(String deviceId, bool connected, String? error) {
    if (!connected && connectedDevice?.deviceId == deviceId) {
      connectedDevice = null;
      _subscriptions.clear();
      status = error == null ? 'Ring disconnected' : 'Ring lost: $error';
      notifyListeners();
    }
  }

  void _onValueChange(
    String deviceId,
    String characteristicId,
    List<int> bytes,
  ) {
    if (connectedDevice?.deviceId != deviceId) return;
    final uuid = characteristicId.toLowerCase();
    final TelemetrySample? sample = switch (uuid) {
      ringPpgUuid => PpgSample.decode(bytes),
      ringImuUuid => ImuSample.decode(bytes),
      ringAudioUuid => AudioSample.decode(bytes),
      _ => null,
    };
    if (sample == null) return;
    if (sample is PpgSample) {
      _append(ppg, sample, 500);
      ppgPackets++;
      lastPpgAt = DateTime.now();
    } else if (sample is ImuSample) {
      _append(imu, sample, 300);
      imuPackets++;
      lastImuAt = DateTime.now();
    } else if (sample is AudioSample) {
      _append(audioFeatures, sample, 180);
      audioPackets++;
      lastAudioAt = DateTime.now();
    }
    packets++;
    onSample?.call(sample, _acquisitionTime(sample.deviceMs));
    _dirty = true;
  }

  DateTime _acquisitionTime(int deviceMs) {
    final receivedAt = DateTime.now();
    final previous = _lastDeviceMs;
    if (previous != null &&
        deviceMs < previous &&
        previous - deviceMs > 0x80000000) {
      _deviceWrapMs += 0x100000000;
    }
    _lastDeviceMs = deviceMs;
    final deviceUs = (_deviceWrapMs + deviceMs) * 1000;
    final offset = receivedAt.microsecondsSinceEpoch - deviceUs;
    if (_deviceToHostOffsetUs == null || offset < _deviceToHostOffsetUs!) {
      _deviceToHostOffsetUs = offset;
    }
    return DateTime.fromMicrosecondsSinceEpoch(
      deviceUs + _deviceToHostOffsetUs!,
    );
  }

  void _append<T>(List<T> values, T value, int limit) {
    values.add(value);
    if (values.length > limit) values.removeRange(0, values.length - limit);
  }

  void _resetClock() {
    _lastDeviceMs = null;
    _deviceWrapMs = 0;
    _deviceToHostOffsetUs = null;
    packets = 0;
    ppgPackets = 0;
    imuPackets = 0;
    audioPackets = 0;
    lastPpgAt = null;
    lastImuAt = null;
    lastAudioAt = null;
    ppg.clear();
    imu.clear();
    audioFeatures.clear();
  }

  Future<void> disconnect() async {
    final device = connectedDevice;
    if (device != null) {
      for (final subscription in _subscriptions) {
        try {
          await UniversalBle.unsubscribe(
            device.deviceId,
            subscription.service,
            subscription.characteristic,
          );
        } catch (_) {}
      }
      await UniversalBle.disconnect(device.deviceId);
    }
    _subscriptions.clear();
    connectedDevice = null;
    status = 'Ring disconnected';
    notifyListeners();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _uiTimer?.cancel();
    UniversalBle.onScanResult = null;
    UniversalBle.onConnectionChange = null;
    UniversalBle.onValueChange = null;
    final device = connectedDevice;
    if (device != null) unawaited(UniversalBle.disconnect(device.deviceId));
    super.dispose();
  }
}

String _canonicalBleId(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^a-f0-9]'), '');

String _canonicalBleName(String value) => value.trim().toLowerCase();

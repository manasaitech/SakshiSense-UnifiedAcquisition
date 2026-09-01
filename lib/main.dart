import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:neurosdk2/neurosdk2.dart';
import 'package:permission_handler/permission_handler.dart';

import 'network/lsl_marker_transport.dart';
import 'network/marker_transport.dart';
import 'ring/ring_controller.dart';
import 'ring/telemetry_models.dart';
import 'session/peripheral_recorder.dart';
import 'storage/marker_store.dart';
import 'storage/recording_exporter.dart';

void main() {
  runApp(const UnifiedAcquisitionApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const UnifiedAcquisitionApp();
}

const _fallbackChannels = ['O1', 'O2', 'T3', 'T4'];
const _packetModulo = 2048;
const _bands = [
  BandDefinition('Delta', 1, 4, Color(0xff38bdf8)),
  BandDefinition('Theta', 4, 8, Color(0xff818cf8)),
  BandDefinition('Alpha', 8, 13, Color(0xff4ade80)),
  BandDefinition('Beta', 13, 30, Color(0xfff59e0b)),
  BandDefinition('Gamma', 30, 45, Color(0xfff43f5e)),
];
const _channelColors = [
  Color(0xff2563eb),
  Color(0xff16a34a),
  Color(0xffd97706),
  Color(0xffdc2626),
];

class UnifiedAcquisitionApp extends StatelessWidget {
  const UnifiedAcquisitionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff2563eb),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Unified Research Acquisition',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xfff6f7f9),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.black.withAlpha(15)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  Scanner? _scanner;
  StreamSubscription<List<FSensorInfo>>? _scanSub;
  var _isScanning = false;
  var _status = 'Ready';
  var _storageTarget = 'Loading...';
  final List<FSensorInfo> _devices = [];

  @override
  void initState() {
    super.initState();
    _loadStorageTarget();
    _requestPlatformPermissions();
  }

  Future<void> _loadStorageTarget() async {
    final label = await defaultRecordingTargetLabel();
    if (mounted) setState(() => _storageTarget = label);
  }

  Future<void> _requestPlatformPermissions() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    }
  }

  Future<void> _startScan() async {
    if (kIsWeb) {
      // The BrainBit native SDK has no Flutter web implementation.  Open a
      // browser BLE session instead so the Web Bluetooth-capable Sakshi Ring
      // can still be acquired from Chrome/Edge over HTTPS.
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const CollectorScreen(
            deviceInfo: null,
            webBleMode: true,
          ),
        ),
      );
      return;
    }
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _devices.clear();
      _status = 'Scanning for BrainBit devices...';
    });

    try {
      _scanner = await Scanner.create([
        FSensorFamily.leBrainBit,
        FSensorFamily.leBrainBitBlack,
        FSensorFamily.leBrainBit2,
        FSensorFamily.leBrainBitPro,
        FSensorFamily.leBrainBitFlex,
      ]);
      _scanSub = _scanner!.sensorsStream.listen((sensors) {
        if (!mounted) return;
        setState(() {
          _devices
            ..clear()
            ..addAll(sensors);
          _status = sensors.isEmpty
              ? 'Scanning... no devices yet'
              : 'Found ${sensors.length} device${sensors.length == 1 ? '' : 's'}';
        });
      });
      await _scanner!.start();
    } on PlatformException catch (e) {
      await _stopScan();
      _showMessage('Scan failed',
          '${e.code}: ${e.message ?? e.details ?? e.toString()}');
    } catch (e) {
      await _stopScan();
      _showMessage('Scan failed', e.toString());
    }
  }

  Future<void> _stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await _scanner?.stop();
      _scanner?.dispose();
    } catch (_) {
      // The native SDK may already have closed the scanner.
    }
    _scanner = null;
    if (mounted) {
      setState(() {
        _isScanning = false;
        _status = _devices.isEmpty ? 'Ready' : 'Scan stopped';
      });
    }
  }

  Future<void> _openDevice(FSensorInfo info) async {
    await _stopScan();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CollectorScreen(deviceInfo: info),
      ),
    );
  }

  void _openDemo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CollectorScreen(
          deviceInfo: null,
          demoMode: true,
        ),
      ),
    );
  }

  void _showMessage(String title, String body) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unified Research Acquisition'),
        actions: [
          IconButton(
            tooltip: 'Demo mode',
            onPressed: _openDemo,
            icon: const Icon(Icons.science_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Flex(
                direction: wide ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: wide ? 360 : null,
                    child: _ScannerPanel(
                      status: _status,
                      storageTarget: _storageTarget,
                      isScanning: _isScanning,
                      onScan: _isScanning ? _stopScan : _startScan,
                      onDemo: _openDemo,
                    ),
                  ),
                  SizedBox(width: wide ? 16 : 0, height: wide ? 0 : 16),
                  Expanded(
                    child: Card(
                      child: _devices.isEmpty
                          ? const _EmptyDeviceList()
                          : ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: _devices.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final dev = _devices[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    child: const Icon(Icons.sensors),
                                  ),
                                  title: Text(dev.name.isEmpty
                                      ? 'Unnamed BrainBit'
                                      : dev.name),
                                  subtitle: Text(
                                    '${dev.sensFamily.name} | ${dev.address} | RSSI ${dev.rssi}',
                                  ),
                                  trailing: FilledButton.tonal(
                                    onPressed: () => _openDevice(dev),
                                    child: const Text('Connect'),
                                  ),
                                  onTap: () => _openDevice(dev),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ScannerPanel extends StatelessWidget {
  const _ScannerPanel({
    required this.status,
    required this.storageTarget,
    required this.isScanning,
    required this.onScan,
    required this.onDemo,
  });

  final String status;
  final String storageTarget;
  final bool isScanning;
  final VoidCallback onScan;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Acquisition Setup',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'On native builds, choose a BrainBit headset first. In a browser, start a Web Bluetooth session to acquire the Sakshi Ring and microphone.',
            ),
            const SizedBox(height: 12),
            _InfoLine(
                icon: Icons.bluetooth_searching,
                label: 'Scanner',
                value: status),
            const SizedBox(height: 8),
            _InfoLine(
                icon: Icons.folder_outlined,
                label: 'Default export',
                value: storageTarget),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onScan,
              icon: Icon(isScanning ? Icons.stop : Icons.search),
              label: Text(isScanning ? 'Stop Scan' : 'Start Web BLE / Scan'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onDemo,
              icon: const Icon(Icons.show_chart),
              label: const Text('Open Demo Session'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDeviceList extends StatelessWidget {
  const _EmptyDeviceList();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sensors_off_outlined,
                    size: 48, color: Colors.grey.shade500),
                const SizedBox(height: 12),
                Text('No devices listed',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Turn on the headset (native) or open a Web BLE session (browser) to choose a nearby Sakshi Ring.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
}

class CollectorScreen extends StatefulWidget {
  const CollectorScreen({
    super.key,
    required this.deviceInfo,
    this.demoMode = false,
    this.webBleMode = false,
  });

  final FSensorInfo? deviceInfo;
  final bool demoMode;
  /// A browser session acquires Web Bluetooth peripherals (currently the
  /// Sakshi Ring) without attempting the native BrainBit SDK.
  final bool webBleMode;

  @override
  State<CollectorScreen> createState() => _CollectorScreenState();
}

class _CollectorScreenState extends State<CollectorScreen> {
  Sensor? _sensor;
  BrainBit? _brainBit;
  BrainBit2? _brainBit2;
  Timer? _demoTimer;
  Timer? _uiTimer;
  RecordingExporter? _exporter;
  late final LslMarkerTransport _lslTransport;
  late final MarkerTransport _markerTransport;
  late final RingController _ring;
  late final PeripheralRecorder _peripherals;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  StreamSubscription<IncomingMarker>? _incomingMarkerSub;
  StreamSubscription<IncomingMarker>? _incomingLslMarkerSub;
  final _signalClock = PacketClock();
  final _qualityClock = PacketClock();
  final _memsClock = PacketClock();
  final _fpgClock = PacketClock();
  final _streamStopwatch = Stopwatch();
  final _recordStopwatch = Stopwatch();
  final _keyboardFocusNode =
      FocusNode(debugLabel: 'collector-keyboard-markers');
  final _mobileScaffoldKey = GlobalKey<ScaffoldState>();
  final _graphData = List.generate(4, (_) => <FlSpot>[]);
  final _previewFilters = List.generate(4, (_) => PreviewFilterChain());
  final _bandBuffers = List.generate(4, (_) => ListQueue<double>());
  final _bandPowers =
      List.generate(4, (_) => List<double>.filled(_bands.length, 0));
  final _latestUv = List<double>.filled(4, 0);
  final _latestQuality = List<double?>.filled(8, null);
  String _latestMems = 'not started';
  final _pendingMarkers = <PendingMarker>[];
  final _rng = Random(11);
  Set<FSensorCommand>? _supportedCommands;
  List<String> _channelLabels = _fallbackChannels;
  List<Map<String, Object?>> _channelInfoMetadata = const [];
  List<String> _quickMarkers = const ['S1', 'S2', 'R', 'ART'];
  int _demoPacket = 0;

  String _connection = 'Preparing';
  String _status = 'Idle';
  String _batteryStatus = 'Battery unknown';
  String _exportTarget = 'Loading...';
  String? _selectedDirectory;
  String _sessionId = 'preview';
  String _markerStatus = 'Markers idle';
  String _lastMarker = 'none';
  int _battery = 0;
  int _sampleRateHz = 250;
  int _receivedSamples = 0;
  int _memsSamples = 0;
  int _markerCount = 0;
  int _samplesSinceBandUpdate = 0;
  int _markerPort = 15333;
  int _outletPort = 15334;
  String _outletHost = '127.0.0.1';
  int _lostSignalPackets = 0;
  int _droppedBursts = 0;
  double _lastPlotX = 0;
  double _graphScaleUv = 100;
  bool _streaming = false;
  bool _recording = false;
  bool _disconnecting = false;
  bool _markerReceiverEnabled = true;
  bool _networkOutletEnabled = false;
  bool _lslReceiverEnabled = false;
  bool _lslOutletEnabled = false;
  bool _collectResist = true;
  bool _collectMems = false;
  bool _collectFpg = false;
  bool _collectRingAudio = false;
  bool _viewBandPass = false;
  double _viewFMinHz = 0.1;
  double _viewFMaxHz = 45;
  int? _viewNotchHz = 50;
  bool _bandPowerRelative = true;
  bool _checkingImpedance = false;
  bool _impedanceChecked = false;
  bool _preflightComplete = false;
  bool _preflightResistActive = false;
  final double _plotWindowSeconds = 8;
  late RecordingMetadata _metadata;

  @override
  void initState() {
    super.initState();
    _peripherals = createPeripheralRecorder(onChange: _onPeripheralChanged);
    _ring = RingController(onSample: _handleRingSample);
    _peripherals.refreshInputs();
    _markerTransport = createMarkerTransport();
    _incomingMarkerSub = _markerTransport.markers.listen(_handleIncomingMarker);
    _lslTransport = createLslMarkerTransport();
    _incomingLslMarkerSub =
        _lslTransport.markers.listen(_handleIncomingLslMarker);
    _metadata = RecordingMetadata.defaults();
    _loadDefaultTarget();
    _loadMarkerButtons();
    if (widget.demoMode) {
      _connection = 'Demo';
    } else {
      _connect();
    }
  }

  void _onPeripheralChanged() {
    if (mounted) setState(() {});
  }

  void _handleRingSample(TelemetrySample sample, DateTime acquiredAt) {
    if (sample is AudioSample) {
      if (!_collectRingAudio || !_recording) return;
      _exporter?.writeRingAudio([
        _csv(_sessionId),
        sample.sequence,
        sample.deviceMs,
        _streamStopwatch.elapsedMicroseconds,
        acquiredAt.microsecondsSinceEpoch,
        _csv(acquiredAt.toUtc().toIso8601String()),
        sample.rms,
        sample.peak,
        sample.zeroCrossings,
        sample.sampleCount,
      ].join(','));
      return;
    }
    _peripherals.addRingSample(
      sample,
      acquiredAt,
      _streamStopwatch.elapsedMicroseconds,
    );
  }

  Future<void> _loadDefaultTarget() async {
    final label = await defaultRecordingTargetLabel();
    if (mounted) setState(() => _exportTarget = label);
  }

  Future<void> _loadMarkerButtons() async {
    final stored = await loadMarkerButtons();
    if (stored.isEmpty || !mounted) return;
    setState(() => _quickMarkers = stored);
  }

  Future<void> _connect() async {
    final info = widget.deviceInfo;
    if (info == null) {
      if (widget.webBleMode && mounted) {
        setState(() {
          _connection = 'Web BLE ready';
          _status = 'Use Scan ring below to choose a Sakshi Ring';
          _preflightComplete = true;
          _channelLabels = const ['Ring PPG', 'Ring IMU', 'Ring audio', 'Mic'];
        });
      }
      return;
    }
    setState(() {
      _connection = 'Connecting';
      _status = 'Creating sensor';
      _impedanceChecked = false;
      _preflightComplete = false;
    });
    try {
      final scanner = await Scanner.create([info.sensFamily]);
      final sensor = await scanner.createSensor(info);
      scanner.dispose();
      if (sensor == null) {
        setState(() => _connection = 'Sensor unavailable');
        return;
      }

      _sensor = sensor;
      if (sensor is BrainBit) {
        _brainBit = sensor;
        _subscriptions
            .add(sensor.signalDataStream.listen(_handleBrainBitSignal));
        _subscriptions
            .add(sensor.resistDataStream.listen(_handleBrainBitResist));
      } else if (sensor is BrainBit2) {
        _brainBit2 = sensor;
        _subscriptions
            .add(sensor.signalDataStream.listen(_handleBrainBit2Signal));
        _subscriptions
            .add(sensor.resistDataStream.listen(_handleBrainBit2Resist));
        _subscriptions.add(sensor.memsDataStream.listen(_handleMems));
        _subscriptions.add(sensor.fpgStream.listen(_handleFpg));
      }

      _subscriptions.add(sensor.sensorStateStream.listen((state) {
        if (!mounted) return;
        setState(() => _connection = state.name);
      }));
      _subscriptions.add(sensor.batteryPowerStream.listen((value) {
        if (!mounted) return;
        setState(() {
          _battery = value;
          _batteryStatus = _batteryText(value);
        });
      }));

      await sensor.connect();
      await _loadCapabilities(sensor);
      await _configureSensor();
      if (mounted) {
        setState(() {
          _connection = 'Connected';
          _status = 'Starting electrode impedance monitor';
        });
      }
      await _startPreflightImpedanceMonitor();
    } catch (e) {
      if (mounted) {
        setState(() {
          _connection = 'Error';
          _status = e.toString();
        });
      }
    }
  }

  Future<void> _loadCapabilities(Sensor sensor) async {
    try {
      final commands = await sensor.commands.value;
      if (!mounted) return;
      setState(() {
        _supportedCommands = commands;
        _collectResist = false;
        _collectMems = false;
        _collectFpg = false;
      });
    } catch (_) {
      _supportedCommands = null;
    }
  }

  Future<void> _configureSensor() async {
    if (_brainBit != null) {
      try {
        await _brainBit!.gain.set(FSensorGain.gain6);
      } catch (_) {}
    }
    if (_brainBit2 != null) {
      try {
        await _loadBrainBit2ChannelLabels();
      } catch (_) {}
      try {
        await _brainBit2!.amplifierParam.set(
          BrainBit2AmplifierParam(
            chGain: List.filled(4, FSensorGain.gain3),
            chSignalMode: List.filled(4, FBrainBit2ChannelMode.chModeNormal),
            chResistUse: List.filled(4, true),
            current: FGenCurrent.genCurr6nA,
          ),
        );
      } catch (_) {}
      try {
        final frequency = await _brainBit2!.samplingFrequencyResist.value;
        if (frequency == FSensorSamplingFrequency.hz250) _sampleRateHz = 250;
      } catch (_) {}
    }
  }

  Future<void> _loadBrainBit2ChannelLabels() async {
    final infos = await _brainBit2!.supportedChannels.value;
    if (infos.isEmpty) return;
    final usesZeroBased = infos.any((info) => info?.num == 0);
    final labels = List<String>.from(_fallbackChannels);
    final channelInfo = <Map<String, Object?>>[];
    for (final info in infos) {
      if (info == null) continue;
      final index = usesZeroBased ? info.num : info.num - 1;
      channelInfo.add({
        'sdk_num': info.num,
        'sample_index': index,
        'id': info.id.name,
        'name': info.name,
        'type': info.chType.name,
      });
      if (index < 0 || index >= labels.length) continue;
      labels[index] = _eegChannelLabel(info, index);
    }
    if (mounted) {
      setState(() {
        _channelLabels = labels;
        _channelInfoMetadata = channelInfo;
      });
    } else {
      _channelLabels = labels;
      _channelInfoMetadata = channelInfo;
    }
  }

  String _eegChannelLabel(FEEGChannelInfo info, int index) {
    if (info.id != FEEGChannelId.unknown) {
      return _formatChannelId(info.id);
    }
    final name = info.name.trim();
    if (name.isNotEmpty) return name;
    return 'CH${index + 1}';
  }

  String _formatChannelId(FEEGChannelId id) {
    switch (id) {
      case FEEGChannelId.o1:
        return 'O1';
      case FEEGChannelId.o2:
        return 'O2';
      case FEEGChannelId.t3:
        return 'T3';
      case FEEGChannelId.t4:
        return 'T4';
      case FEEGChannelId.p3:
        return 'P3';
      case FEEGChannelId.c3:
        return 'C3';
      case FEEGChannelId.f3:
        return 'F3';
      case FEEGChannelId.fp1:
        return 'Fp1';
      case FEEGChannelId.t5:
        return 'T5';
      case FEEGChannelId.f7:
        return 'F7';
      case FEEGChannelId.f8:
        return 'F8';
      case FEEGChannelId.t6:
        return 'T6';
      case FEEGChannelId.fp2:
        return 'Fp2';
      case FEEGChannelId.f4:
        return 'F4';
      case FEEGChannelId.c4:
        return 'C4';
      case FEEGChannelId.p4:
        return 'P4';
      case FEEGChannelId.oZ:
        return 'Oz';
      case FEEGChannelId.pZ:
        return 'Pz';
      case FEEGChannelId.cZ:
        return 'Cz';
      case FEEGChannelId.fZ:
        return 'Fz';
      case FEEGChannelId.fpZ:
        return 'Fpz';
      case FEEGChannelId.d1:
        return 'D1';
      case FEEGChannelId.d2:
        return 'D2';
      case FEEGChannelId.d3:
        return 'D3';
      case FEEGChannelId.unknown:
        return 'Unknown';
    }
  }

  Future<void> _chooseDirectory() async {
    final path = await chooseRecordingDirectory();
    if (path == null || path.isEmpty) return;
    setState(() {
      _selectedDirectory = path;
      _exportTarget = path;
    });
  }

  Future<void> _editMetadata() async {
    final updated = await showDialog<RecordingMetadata>(
      context: context,
      builder: (_) => MetadataDialog(initial: _metadata),
    );
    if (updated != null && mounted) {
      setState(() => _metadata = updated);
    }
  }

  Future<void> _configureUdp() async {
    final host = TextEditingController(text: _outletHost);
    final receivePort = TextEditingController(text: '$_markerPort');
    final sendPort = TextEditingController(text: '$_outletPort');
    final result = await showDialog<(String, int, int)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('UDP marker network'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: host,
                decoration: const InputDecoration(
                  labelText: 'Send to host / IP',
                  hintText: '192.168.1.50 or 255.255.255.255',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: receivePort,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Receive port'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: sendPort,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Send port'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'The receiver binds to all IPv4 interfaces, so markers can arrive from other computers on the network.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final rx = int.tryParse(receivePort.text);
              final tx = int.tryParse(sendPort.text);
              if (host.text.trim().isEmpty ||
                  rx == null ||
                  tx == null ||
                  rx < 1 ||
                  rx > 65535 ||
                  tx < 1 ||
                  tx > 65535) {
                return;
              }
              Navigator.pop(context, (host.text.trim(), rx, tx));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    host.dispose();
    receivePort.dispose();
    sendPort.dispose();
    if (result != null && mounted) {
      setState(() {
        _outletHost = result.$1;
        _markerPort = result.$2;
        _outletPort = result.$3;
      });
    }
  }

  Future<void> _toggleStream() async {
    if (_streaming) {
      await _stopStream();
    } else {
      await _startStream();
    }
  }

  Future<void> _startStream() async {
    final webBle = widget.webBleMode && kIsWeb;
    if (!widget.demoMode && !webBle && !_preflightComplete) {
      setState(() => _status = 'Complete electrode impedance preflight first');
      return;
    }
    await _stopPreflightImpedanceMonitor();
    _resetRunState();
    _streamStopwatch.start();
    final warnings = <String>[];
    await _startMarkerNetworking(warnings);
    if (widget.demoMode) {
      _demoTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        final batch = List.generate(5, (_) => _nextDemoSample());
        _handleSamples(batch);
      });
    } else if (!webBle) {
      try {
        await _startSignalCommands(warnings);
      } catch (e) {
        final message = 'Signal start failed: ${_formatSdkError(e)}';
        if (mounted) {
          setState(() => _status = message);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
        }
        _streamStopwatch.stop();
        return;
      }
      if (_brainBit2 != null && _collectMems) {
        await _tryOptionalCommand(
          FSensorCommand.startMEMS,
          'Motion data',
          warnings,
        );
      }
      if (_brainBit2 != null && _collectFpg) {
        await _tryOptionalCommand(
          FSensorCommand.startFPG,
          'FPG/PPG data',
          warnings,
        );
      }
    }
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
    setState(() {
      _streaming = true;
      _status = widget.demoMode
          ? 'Streaming'
          : webBle
              ? 'Web BLE streaming (ring + microphone)'
          : (warnings.isEmpty
              ? 'Streaming'
              : 'Streaming; ${warnings.join('; ')}');
    });
  }

  Future<void> _stopStream() async {
    if (_recording) await _stopRecording();
    _demoTimer?.cancel();
    _demoTimer = null;
    if (!widget.demoMode) {
      try {
        await _stopSignalCommands();
        if (_brainBit2 != null && _collectMems) {
          await _brainBit2!.execute(FSensorCommand.stopMEMS);
        }
        if (_brainBit2 != null && _collectFpg) {
          await _brainBit2!.execute(FSensorCommand.stopFPG);
        }
      } catch (_) {}
    }
    await _markerTransport.stopMarkerReceiver();
    await _markerTransport.stopOutlet();
    await _lslTransport.stopReceiver();
    await _lslTransport.stopOutlet();
    _streamStopwatch.stop();
    _uiTimer?.cancel();
    _uiTimer = null;
    if (mounted) {
      setState(() {
        _streaming = false;
        _status = 'Stopped';
      });
    }
  }

  Future<void> _disconnectAndLeave() async {
    if (_disconnecting) return;
    setState(() {
      _disconnecting = true;
      _status = 'Disconnecting';
    });
    try {
      if (_streaming || _recording) {
        await _stopStream();
      }
      await _stopPreflightImpedanceMonitor();
      await _markerTransport.stopMarkerReceiver();
      await _markerTransport.stopOutlet();
      await _lslTransport.stopReceiver();
      await _lslTransport.stopOutlet();
      await _ring.disconnect();
      for (final sub in _subscriptions) {
        await sub.cancel();
      }
      _subscriptions.clear();
      await _sensor?.disconnect();
      await _sensor?.dispose();
      _sensor = null;
      _brainBit = null;
      _brainBit2 = null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disconnect warning: ${_formatSdkError(e)}')),
        );
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _startSignalCommands(List<String> warnings) async {
    if (_sensor == null) {
      throw StateError('Sensor is not ready');
    }
    if (!_isCommandSupported(FSensorCommand.startSignal)) {
      throw StateError('startSignal is not supported by this headset');
    }
    await _sensor?.execute(FSensorCommand.startSignal);
    if (_collectResist && _brainBit2 != null) {
      warnings.add('contact quality paused during EEG stream');
    } else if (_collectResist &&
        _isCommandSupported(FSensorCommand.startResist)) {
      try {
        await _sensor?.execute(FSensorCommand.startResist);
      } catch (e) {
        warnings.add('contact quality unavailable (${_formatSdkError(e)})');
      }
    }
  }

  Future<void> _stopSignalCommands() async {
    await _sensor?.execute(FSensorCommand.stopSignal);
    if (_collectResist && _brainBit2 == null) {
      await _sensor?.execute(FSensorCommand.stopResist);
    }
  }

  Future<void> _tryOptionalCommand(
    FSensorCommand command,
    String label,
    List<String> warnings,
  ) async {
    if (!_isCommandSupported(command) && command != FSensorCommand.startMEMS) {
      warnings.add('$label unsupported');
      return;
    }
    try {
      await _sensor?.execute(command);
    } catch (e) {
      final message = '$label unavailable (${_formatSdkError(e)})';
      warnings.add(message);
      if (command == FSensorCommand.startMEMS && mounted) {
        setState(() {
          _collectMems = false;
          _latestMems = 'unavailable';
        });
      }
    }
  }

  bool _isCommandSupported(FSensorCommand command) =>
      _supportedCommands == null || _supportedCommands!.contains(command);

  String _formatSdkError(Object error) {
    if (error is PlatformException) {
      final parts = [
        if (error.code.isNotEmpty) error.code,
        if (error.message != null && error.message!.isNotEmpty) error.message,
        if (error.details != null) error.details.toString(),
      ];
      return parts.join(': ');
    }
    return error.toString();
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final sessionId =
        'unified_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
    _sessionId = sessionId;
    final exporter = await createRecordingExporter(
      sessionId: sessionId,
      directoryPath: _selectedDirectory,
    );
    final info = widget.deviceInfo;
    final manifest = RecordingManifest(
      sessionId: sessionId,
      subjectId: _metadata.subjectId,
      protocol: _metadata.protocol,
      operatorName: _metadata.operatorName,
      notes: _metadata.notes,
      deviceName: widget.demoMode ? 'Demo BrainBit' : (info?.name ?? ''),
      deviceAddress: widget.demoMode ? 'demo' : (info?.address ?? ''),
      deviceFamily: widget.demoMode ? 'demo' : (info?.sensFamily.name ?? ''),
      sampleRateHz: _sampleRateHz,
      channelLabels: _channelLabels,
      createdAtIso: DateTime.now().toUtc().toIso8601String(),
      settings: {
        'channel_label_source': _brainBit2 == null
            ? 'BrainBit fixed fields'
            : 'BrainBit2.supportedChannels.num',
        'channel_info': _channelInfoMetadata,
        'collect_resistance': _collectResist,
        'collect_mems': _collectMems,
        'collect_fpg': _collectFpg,
        'collect_ring_audio': _collectRingAudio,
        'display_bandpass_enabled': _viewBandPass,
        'display_bandpass_low_hz': _viewFMinHz,
        'display_bandpass_high_hz': _viewFMaxHz,
        'display_notch_hz': _viewNotchHz,
        'display_band_power_mode': _bandPowerRelative ? 'relative' : 'db',
        'graph_scale_uv': _graphScaleUv,
        'marker_udp_receive': _markerReceiverEnabled,
        'marker_udp_port': _markerPort,
        'udp_outlet_enabled': _networkOutletEnabled,
        'udp_outlet_port': _outletPort,
        'udp_outlet_host': _outletHost,
        'lsl_supported': _lslTransport.supportsLsl,
        'lsl_marker_receive': _lslReceiverEnabled,
        'lsl_marker_outlet': _lslOutletEnabled,
        'session_number': _metadata.sessionNumber,
        'study_day': _metadata.day,
        'custom_questions': _metadata.customQuestions,
        'ring_device': _ring.connectedDevice?.deviceId,
        'microphone_input': _peripherals.selectedInputId ?? 'system_default',
      },
    );
    await exporter.start(manifest);
    _exporter = exporter;
    try {
      await _peripherals.start(sessionDirectory: exporter.targetLabel);
      _writeEvent('peripheral_recording', _peripherals.status);
    } catch (error) {
      _writeEvent('microphone_start_failed', _formatSdkError(error));
    }
    _recordStopwatch
      ..reset()
      ..start();
    _writeEvent('recording_started', exporter.targetLabel);
    setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    _writeEvent('recording_stopped',
        'samples=$_receivedSamples,lost=$_lostSignalPackets');
    final exporter = _exporter;
    _exporter = null;
    _recordStopwatch.stop();
    await _peripherals.stop();
    final target = await exporter?.finish();
    if (!mounted) return;
    setState(() => _recording = false);
    if (target != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recording saved: $target')),
      );
    }
  }

  void _resetRunState() {
    _signalClock.reset();
    _qualityClock.reset();
    _memsClock.reset();
    _fpgClock.reset();
    _streamStopwatch
      ..reset()
      ..stop();
    _recordStopwatch
      ..reset()
      ..stop();
    _demoPacket = 0;
    _receivedSamples = 0;
    _memsSamples = 0;
    _markerCount = 0;
    _lastMarker = 'none';
    _lostSignalPackets = 0;
    _droppedBursts = 0;
    _lastPlotX = 0;
    _latestMems = 'not started';
    _samplesSinceBandUpdate = 0;
    for (final line in _graphData) {
      line.clear();
    }
    for (final filter in _previewFilters) {
      filter.reset();
    }
    for (final buffer in _bandBuffers) {
      buffer.clear();
    }
    for (final channelPowers in _bandPowers) {
      for (var i = 0; i < channelPowers.length; i++) {
        channelPowers[i] = 0;
      }
    }
    for (var i = 0; i < 4; i++) {
      _latestUv[i] = 0;
    }
  }

  DemoSample _nextDemoSample() {
    final t = _demoPacket / _sampleRateHz;
    final packet = _demoPacket % _packetModulo;
    if (_rng.nextDouble() < 0.0008) {
      _demoPacket += 1 + _rng.nextInt(3);
    }
    _demoPacket++;
    final alpha = sin(2 * pi * 10 * t);
    final theta = sin(2 * pi * 6 * t + 0.8);
    double noise() => (_rng.nextDouble() - 0.5) * 10;
    return DemoSample(
      packet: packet,
      marker: 0,
      values: [
        (40 * alpha + 12 * theta + noise()) / 1000000,
        (35 * alpha + noise()) / 1000000,
        (18 * theta + noise()) / 1000000,
        (14 * sin(2 * pi * 14 * t) + noise()) / 1000000,
      ],
    );
  }

  void _handleBrainBitSignal(List<BrainBitSignalData> data) {
    _handleSamples(data
        .map(
          (sample) => DemoSample(
            packet: sample.packNum,
            marker: sample.marker,
            values: [sample.o1, sample.o2, sample.t3, sample.t4],
          ),
        )
        .toList());
  }

  void _handleBrainBit2Signal(List<SignalChannelsData> data) {
    _handleSamples(data
        .map(
          (sample) => DemoSample(
            packet: sample.packNum,
            marker: sample.marker,
            values: _fourChannels(sample.samples),
          ),
        )
        .toList());
  }

  void _handleSamples(List<DemoSample> batch) {
    if (batch.isEmpty) return;
    final callbackWallUs = DateTime.now().microsecondsSinceEpoch;
    final callbackMonoUs = _streamStopwatch.elapsedMicroseconds;
    final periodUs = 1000000 ~/ _sampleRateHz;

    for (var i = 0; i < batch.length; i++) {
      final sample = batch[i];
      final stamp = _signalClock.accept(sample.packet);
      _lostSignalPackets = _signalClock.totalLost;
      if (stamp.lostBefore > 0) _droppedBursts++;
      final hostMonoUs =
          max(0, callbackMonoUs - ((batch.length - 1 - i) * periodUs));
      final hostUnixUs = callbackWallUs - ((batch.length - 1 - i) * periodUs);
      final deviceElapsedUs = stamp.unwrappedPacket * periodUs;
      final appMarker = _popMarkerForSample();
      final xSeconds =
          (stamp.unwrappedPacket / _sampleRateHz) % _plotWindowSeconds;
      if (xSeconds < _lastPlotX) {
        for (final line in _graphData) {
          line.clear();
        }
      }
      _lastPlotX = xSeconds;

      for (var c = 0; c < 4; c++) {
        final uv = sample.values[c] * 1000000;
        final previewUv = _previewFilters[c].apply(
          uv,
          sampleRateHz: _sampleRateHz,
          bandPassEnabled: _viewBandPass,
          fMinHz: _viewFMinHz,
          fMaxHz: _viewFMaxHz,
          notchHz: _viewNotchHz,
        );
        _latestUv[c] = previewUv;
        _appendBandSample(c, previewUv);
        final plotted = _clipPreviewValue(previewUv);
        _graphData[c].add(FlSpot(xSeconds, plotted));
        if (_graphData[c].length > _sampleRateHz * _plotWindowSeconds) {
          _graphData[c].removeAt(0);
        }
      }
      _samplesSinceBandUpdate++;
      if (_samplesSinceBandUpdate >= max(1, _sampleRateHz ~/ 2)) {
        _samplesSinceBandUpdate = 0;
        _updateBandPowers();
      }

      if (_recording) {
        _exporter?.writeEeg([
          _csv(_sessionId),
          stamp.unwrappedPacket,
          sample.packet,
          stamp.unwrappedPacket,
          stamp.lostBefore,
          sample.marker,
          _csv(appMarker?.code ?? ''),
          _csv(appMarker?.source ?? ''),
          _csv(appMarker?.detail ?? ''),
          deviceElapsedUs,
          hostMonoUs,
          hostUnixUs,
          _csv(_isoFromUnixUs(hostUnixUs)),
          ...sample.values,
          ...sample.values.map((v) => v * 1000000),
        ].join(','));
      }
      if (_networkOutletEnabled) {
        _markerTransport.sendEeg({
          'session_id': _sessionId,
          'sample_index': stamp.unwrappedPacket,
          'packet_num': sample.packet,
          'device_marker': sample.marker,
          'app_marker': appMarker?.code,
          'host_unix_us': hostUnixUs,
          'channels_uv': sample.values.map((v) => v * 1000000).toList(),
        });
      }
      _receivedSamples++;
    }
    if (mounted && _receivedSamples % 10 == 0) setState(() {});
  }

  void _handleBrainBitResist(BrainBitResistData data) {
    _latestQuality
      ..[0] = data.o1
      ..[1] = data.o2
      ..[2] = data.t3
      ..[3] = data.t4;
    _refreshPreflightReadiness();
    _writeQuality(
      kind: 'resistance',
      packet: null,
      values: [data.o1, data.o2, data.t3, data.t4],
      referents: const [],
    );
  }

  void _handleBrainBit2Resist(List<ResistRefChannelsData> data) {
    for (final item in data) {
      final values = _fourChannels(item.samples);
      final refs = _fourChannels(item.referents);
      for (var i = 0; i < 4; i++) {
        _latestQuality[i] = values[i];
        _latestQuality[i + 4] = refs[i];
      }
      _writeQuality(
        kind: 'resistance',
        packet: item.packNum,
        values: values,
        referents: refs,
      );
    }
    _refreshPreflightReadiness();
  }

  void _handleMems(List<MEMSData> data) {
    for (final item in data) {
      _memsSamples++;
      _latestMems =
          'A ${item.accelerometer.x.toStringAsFixed(2)}, ${item.accelerometer.y.toStringAsFixed(2)}, ${item.accelerometer.z.toStringAsFixed(2)}';
      final stamp = _memsClock.accept(item.packNum);
      if (_recording) {
        _exporter?.writeMems([
          _csv(_sessionId),
          item.packNum,
          stamp.unwrappedPacket,
          stamp.lostBefore,
          _streamStopwatch.elapsedMicroseconds,
          DateTime.now().microsecondsSinceEpoch,
          _csv(DateTime.now().toUtc().toIso8601String()),
          item.accelerometer.x,
          item.accelerometer.y,
          item.accelerometer.z,
          item.gyroscope.x,
          item.gyroscope.y,
          item.gyroscope.z,
        ].join(','));
      }
    }
    if (mounted) setState(() {});
  }

  void _handleFpg(List<FPGData> data) {
    if (!_recording) return;
    for (final item in data) {
      final stamp = _fpgClock.accept(item.packNum);
      _exporter?.writeFpg([
        _csv(_sessionId),
        item.packNum,
        stamp.unwrappedPacket,
        stamp.lostBefore,
        _streamStopwatch.elapsedMicroseconds,
        DateTime.now().microsecondsSinceEpoch,
        _csv(DateTime.now().toUtc().toIso8601String()),
        item.irAmplitude,
        item.redAmplitude,
      ].join(','));
    }
  }

  void _writeQuality({
    required String kind,
    required int? packet,
    required List<double> values,
    required List<double> referents,
  }) {
    if (!_recording) return;
    PacketStamp? stamp;
    if (packet != null) stamp = _qualityClock.accept(packet);
    final now = DateTime.now();
    final refs = [...referents, 0, 0, 0, 0].take(4);
    _exporter?.writeQuality([
      _csv(_sessionId),
      _csv(kind),
      packet ?? '',
      stamp?.unwrappedPacket ?? '',
      stamp?.lostBefore ?? 0,
      _qualityClock.totalLost,
      stamp == null ? '' : stamp.unwrappedPacket * (1000000 ~/ _sampleRateHz),
      _streamStopwatch.elapsedMicroseconds,
      now.microsecondsSinceEpoch,
      _csv(now.toUtc().toIso8601String()),
      ...values,
      ...refs,
    ].join(','));
  }

  void _writeEvent(String event, String detail) {
    final now = DateTime.now();
    _exporter?.writeEvent([
      _csv(_sessionId),
      _streamStopwatch.elapsedMicroseconds,
      now.microsecondsSinceEpoch,
      _csv(now.toUtc().toIso8601String()),
      _csv(event),
      _csv(detail),
    ].join(','));
  }

  Future<void> _startMarkerNetworking(List<String> warnings) async {
    final active = <String>[];
    if (_markerTransport.supportsNetwork && _markerReceiverEnabled) {
      try {
        await _markerTransport.startMarkerReceiver(_markerPort);
        active.add('UDP receive :$_markerPort');
      } catch (e) {
        warnings.add('marker UDP receive unavailable (${_formatSdkError(e)})');
      }
    }
    if (_markerTransport.supportsNetwork && _networkOutletEnabled) {
      try {
        await _markerTransport.startOutlet(
          host: _outletHost,
          port: _outletPort,
        );
        active.add('UDP send $_outletHost:$_outletPort');
      } catch (e) {
        warnings.add('UDP outlet unavailable (${_formatSdkError(e)})');
      }
    }
    if (_lslTransport.supportsLsl && _lslReceiverEnabled) {
      try {
        await _lslTransport.startReceiver();
        active.add('LSL receive');
      } catch (e) {
        warnings.add('LSL receive unavailable (${_formatSdkError(e)})');
      }
    }
    if (_lslTransport.supportsLsl && _lslOutletEnabled) {
      try {
        await _lslTransport.startOutlet();
        active.add('LSL string/int outlets');
      } catch (e) {
        warnings.add('LSL outlet unavailable (${_formatSdkError(e)})');
      }
    }
    _markerStatus = active.isEmpty
        ? 'Network markers disabled or unavailable'
        : active.join(' • ');
  }

  void _handleIncomingMarker(IncomingMarker marker) {
    _insertMarker(
      marker.code,
      source: 'udp:${marker.source}',
      detail: marker.detail,
    );
  }

  void _handleIncomingLslMarker(IncomingMarker marker) {
    _insertMarker(
      marker.code,
      source: 'lsl:${marker.source}',
      detail: marker.detail,
    );
  }

  void _insertMarker(
    String code, {
    required String source,
    String detail = '',
  }) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now();
    final marker = PendingMarker(
      code: trimmed,
      source: source,
      detail: detail,
      hostUnixUs: now.microsecondsSinceEpoch,
      hostMonotonicUs: _streamStopwatch.elapsedMicroseconds,
    );
    _pendingMarkers.add(marker);
    _markerCount++;
    _lastMarker = '$trimmed ($source)';
    _writeEvent(
      'marker',
      'code=$trimmed,source=$source,detail=$detail,next_sample=$_receivedSamples',
    );
    _markerTransport.sendEvent({
      'event': 'marker',
      'code': trimmed,
      'value': int.tryParse(trimmed) ?? trimmed,
      'value_type': int.tryParse(trimmed) == null ? 'string' : 'int',
      'source': source,
      'detail': detail,
      'host_unix_us': marker.hostUnixUs,
      'next_sample': _receivedSamples,
    });
    if (_lslOutletEnabled && !source.startsWith('lsl:')) {
      _lslTransport.sendMarker(
        int.tryParse(trimmed) ?? trimmed,
        detail: detail,
      );
    }
    if (mounted) setState(() {});
  }

  PendingMarker? _popMarkerForSample() {
    if (_pendingMarkers.isEmpty) return null;
    return _pendingMarkers.removeAt(0);
  }

  void _quickMarker(String code) {
    _insertMarker(code, source: 'manual');
    _keyboardFocusNode.requestFocus();
  }

  KeyEventResult _handleKeyboardMarker(KeyEvent event) {
    if (event is! KeyDownEvent || !_streaming) {
      return KeyEventResult.ignored;
    }
    final marker = _markerForKeyEvent(event);
    if (marker == null) return KeyEventResult.ignored;
    _insertMarker(
      marker,
      source: 'keyboard',
      detail: 'key=${event.logicalKey.keyLabel}',
    );
    return KeyEventResult.handled;
  }

  String? _markerForKeyEvent(KeyDownEvent event) {
    final candidates = <String>{
      if (event.character != null && event.character!.trim().isNotEmpty)
        event.character!,
      if (event.logicalKey.keyLabel.trim().isNotEmpty)
        event.logicalKey.keyLabel,
    };
    for (final key in candidates) {
      final normalizedKey = key.trim().toLowerCase();
      if (normalizedKey.length != 1) continue;
      for (final marker in _quickMarkers) {
        final normalizedMarker = marker.trim().toLowerCase();
        if (normalizedMarker.length == 1 && normalizedMarker == normalizedKey) {
          return marker;
        }
      }
    }
    return null;
  }

  Future<void> _customMarker() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insert Marker'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Marker code',
            hintText: 'stimulus_A',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Insert'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;
    final marker = code.trim();
    await _addMarkerButton(marker);
    if (_streaming) {
      _insertMarker(marker, source: 'manual-custom');
    } else {
      setState(() {
        _lastMarker = 'added $marker';
      });
    }
    _keyboardFocusNode.requestFocus();
  }

  Future<void> _addMarkerButton(String marker) async {
    final normalized = marker.trim();
    if (normalized.isEmpty || _quickMarkers.contains(normalized)) return;
    final updated = [..._quickMarkers, normalized];
    setState(() => _quickMarkers = updated);
    await saveMarkerButtons(updated);
  }

  Future<void> _checkImpedance() async {
    await _startPreflightImpedanceMonitor(restart: true);
  }

  Future<void> _startPreflightImpedanceMonitor({bool restart = false}) async {
    if (_streaming || _sensor == null || _checkingImpedance) return;
    if (widget.demoMode || _preflightComplete) return;
    if (_preflightResistActive && !restart) return;
    if (!_isCommandSupported(FSensorCommand.startResist)) {
      setState(() => _status = 'Impedance command unsupported by this device');
      return;
    }
    setState(() {
      _checkingImpedance = true;
      _impedanceChecked = false;
      _preflightComplete = false;
      _status = 'Checking electrode impedance';
      for (var i = 0; i < _latestQuality.length; i++) {
        _latestQuality[i] = null;
      }
    });
    try {
      if (_preflightResistActive || restart) {
        try {
          await _sensor!.execute(FSensorCommand.stopResist);
        } catch (_) {}
      }
      await _sensor!.execute(FSensorCommand.startResist);
      if (mounted) {
        setState(() {
          _preflightResistActive = true;
          _status = 'Monitoring impedance - adjust electrodes';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _impedanceChecked = false;
          _preflightResistActive = false;
          _status = 'Impedance unavailable: ${_formatSdkError(e)}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _checkingImpedance = false);
      }
    }
  }

  Future<void> _stopPreflightImpedanceMonitor() async {
    if (!_preflightResistActive || _sensor == null) return;
    try {
      await _sensor!.execute(FSensorCommand.stopResist);
    } catch (_) {
      // Some SDK states report resistance already stopped.
    }
    if (mounted) {
      setState(() => _preflightResistActive = false);
    } else {
      _preflightResistActive = false;
    }
  }

  void _refreshPreflightReadiness() {
    if (!mounted) return;
    if (_preflightComplete || widget.demoMode) {
      setState(() {});
      return;
    }
    final ready = _hasUsableImpedance();
    setState(() {
      _impedanceChecked = ready;
      _status = ready
          ? 'All electrodes green - continue to data collection'
          : 'Monitoring impedance - improve contact if possible';
    });
  }

  bool _hasUsableImpedance() {
    for (var i = 0; i < 4; i++) {
      if (electrodeStatus(_latestQuality[i]) != ElectrodeStatus.good) {
        return false;
      }
    }
    return true;
  }

  Future<void> _continueToAcquisition() async {
    await _stopPreflightImpedanceMonitor();
    setState(() {
      _preflightComplete = true;
      _status = _impedanceChecked
          ? 'Ready to stream'
          : 'Ready to stream - impedance not all green';
    });
  }

  String _batteryText(int value) {
    if (value <= 0) return 'Battery unknown';
    if (value <= 15) return '$value% - low';
    return '$value%';
  }

  double _clipPreviewValue(double uv) {
    if (!uv.isFinite) return 0;
    final limit = _graphScaleUv * 0.98;
    return uv.clamp(-limit, limit).toDouble();
  }

  void _appendBandSample(int channel, double uv) {
    final buffer = _bandBuffers[channel];
    buffer.add(uv.isFinite ? uv : 0);
    final maxSamples = max(_sampleRateHz * 4, _sampleRateHz);
    while (buffer.length > maxSamples) {
      buffer.removeFirst();
    }
  }

  void _updateBandPowers() {
    for (var channel = 0; channel < _bandBuffers.length; channel++) {
      final buffer = _bandBuffers[channel];
      if (buffer.length < _sampleRateHz) continue;
      final samples = buffer.toList(growable: false);
      final rawPowers = List<double>.filled(_bands.length, 0);
      for (var i = 0; i < _bands.length; i++) {
        rawPowers[i] = _bandPower(samples, _bands[i]);
      }
      final total = rawPowers.fold<double>(0, (sum, value) => sum + value);
      if (_bandPowerRelative) {
        if (total <= 0 || !total.isFinite) continue;
        for (var i = 0; i < _bands.length; i++) {
          _bandPowers[channel][i] =
              (rawPowers[i] / total * 100).clamp(0, 100).toDouble();
        }
      } else {
        for (var i = 0; i < _bands.length; i++) {
          final power = max(rawPowers[i], 1e-12);
          _bandPowers[channel][i] = 10 * log(power) / ln10;
        }
      }
    }
  }

  double _bandPower(List<double> samples, BandDefinition band) {
    final n = samples.length;
    if (n < 2) return 0;
    final sampleRate = _sampleRateHz.toDouble();
    final startBin = max(1, (band.lowHz * n / sampleRate).ceil());
    final endBin = min(n ~/ 2, (band.highHz * n / sampleRate).floor());
    if (endBin < startBin) return 0;
    final mean = samples.reduce((a, b) => a + b) / n;
    var power = 0.0;
    for (var k = startBin; k <= endBin; k++) {
      final omega = 2 * pi * k / n;
      final coeff = 2 * cos(omega);
      var q0 = 0.0;
      var q1 = 0.0;
      var q2 = 0.0;
      for (final sample in samples) {
        q0 = coeff * q1 - q2 + (sample - mean);
        q2 = q1;
        q1 = q0;
      }
      power += q1 * q1 + q2 * q2 - coeff * q1 * q2;
    }
    return power / ((endBin - startBin + 1) * n * n);
  }

  void _resetDisplayProcessing() {
    for (final line in _graphData) {
      line.clear();
    }
    for (final filter in _previewFilters) {
      filter.reset();
    }
    for (final buffer in _bandBuffers) {
      buffer.clear();
    }
    for (final channelPowers in _bandPowers) {
      for (var i = 0; i < channelPowers.length; i++) {
        channelPowers[i] = 0;
      }
    }
    _lastPlotX = 0;
    _samplesSinceBandUpdate = 0;
  }

  void _setBandPassEnabled(bool value) {
    setState(() {
      _viewBandPass = value;
      _resetDisplayProcessing();
    });
  }

  void _setViewFMin(double value) {
    setState(() {
      _viewFMinHz = min(value, _viewFMaxHz - 1);
      _resetDisplayProcessing();
    });
  }

  void _setViewFMax(double value) {
    setState(() {
      _viewFMaxHz = max(value, _viewFMinHz + 1);
      _resetDisplayProcessing();
    });
  }

  void _setViewNotch(int? value) {
    setState(() {
      _viewNotchHz = value;
      _resetDisplayProcessing();
    });
  }

  void _setBandPowerRelative(bool value) {
    setState(() {
      _bandPowerRelative = value;
      _updateBandPowers();
    });
  }

  List<double> _fourChannels(List<double> values) {
    return List.generate(4, (i) => i < values.length ? values[i] : 0);
  }

  String _elapsedText(Stopwatch clock) {
    final duration = clock.elapsed;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _uiTimer?.cancel();
    _keyboardFocusNode.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _incomingMarkerSub?.cancel();
    _incomingLslMarkerSub?.cancel();
    _markerTransport.dispose();
    _lslTransport.dispose();
    _ring.dispose();
    _peripherals.dispose();
    if (!_disconnecting) {
      _sensor?.disconnect();
      _sensor?.dispose();
    }
    _exporter?.discard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceTitle = widget.demoMode
        ? 'Demo BrainBit'
        : widget.webBleMode
            ? 'Web BLE session'
        : (widget.deviceInfo?.name.isNotEmpty == true
            ? widget.deviceInfo!.name
            : 'BrainBit device');
    final isConnected = widget.demoMode ||
        widget.webBleMode ||
        _connection == 'Connected' ||
        _connection == 'inRange';
    final readyForAcquisition = widget.demoMode ||
        widget.webBleMode || (isConnected && _preflightComplete);
    final compactLayout = MediaQuery.sizeOf(context).width < 900;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _disconnectAndLeave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Disconnect',
            onPressed: _disconnecting ? null : _disconnectAndLeave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text('Unified Acquisition • $deviceTitle'),
          actions: [
            if (compactLayout)
              IconButton(
                tooltip: 'Open session controls',
                onPressed: () => _mobileScaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.tune),
              ),
            IconButton(
              tooltip: 'UDP marker network settings',
              onPressed: _streaming ? null : _configureUdp,
              icon: const Icon(Icons.lan_outlined),
            ),
            IconButton(
              tooltip: 'Disconnect',
              onPressed: _disconnecting ? null : _disconnectAndLeave,
              icon: const Icon(Icons.power_settings_new),
            ),
            IconButton(
              tooltip: 'Session metadata',
              onPressed: _recording || _disconnecting ? null : _editMetadata,
              icon: const Icon(Icons.assignment_outlined),
            ),
            IconButton(
              tooltip: 'Export folder',
              onPressed: _recording || _disconnecting ? null : _chooseDirectory,
              icon: const Icon(Icons.folder_open_outlined),
            ),
          ],
        ),
        body: KeyboardListener(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyboardMarker,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                if (!widget.demoMode && !widget.webBleMode &&
                    !_preflightComplete) {
                  final preflight = _ImpedancePreflightPage(
                    connection: _connection,
                    status: _status,
                    batteryStatus: _batteryStatus,
                    channelLabels: _channelLabels,
                    latestQuality: _latestQuality,
                    checkingImpedance: _checkingImpedance,
                    monitoringImpedance: _preflightResistActive,
                    canCheck: isConnected && !_disconnecting,
                    canContinue: isConnected && !_disconnecting,
                    onCheckImpedance: _checkImpedance,
                    onContinue: () => _continueToAcquisition(),
                  );
                  if (wide) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: preflight,
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [preflight],
                  );
                }
                final lostPercent = _receivedSamples + _lostSignalPackets == 0
                    ? 0.0
                    : _lostSignalPackets /
                        (_receivedSamples + _lostSignalPackets) *
                        100;
                final controlPanel = _ControlPanel(
                  connection: _connection,
                  status: _status,
                  battery: _battery,
                  batteryStatus: _batteryStatus,
                  sampleRateHz: _sampleRateHz,
                  exportTarget: _exportTarget,
                  markerStatus: _markerStatus,
                  lastMarker: _lastMarker,
                  markerCount: _markerCount,
                  udpSupported: _markerTransport.supportsNetwork,
                  markerReceiverEnabled: _markerReceiverEnabled,
                  networkOutletEnabled: _networkOutletEnabled,
                  lslSupported: _lslTransport.supportsLsl,
                  lslReceiverEnabled: _lslReceiverEnabled,
                  lslOutletEnabled: _lslOutletEnabled,
                  lslStatus: _lslTransport.status,
                  markerPort: _markerPort,
                  outletPort: _outletPort,
                  outletHost: _outletHost,
                  quickMarkers: _quickMarkers,
                  metadata: _metadata,
                  streaming: _streaming,
                  recording: _recording,
                  canStream: readyForAcquisition,
                  elapsed: _elapsedText(_streamStopwatch),
                  recordElapsed: _elapsedText(_recordStopwatch),
                  receivedSamples: _receivedSamples,
                  lostPackets: _lostSignalPackets,
                  droppedBursts: _droppedBursts,
                  collectResist: _collectResist,
                  collectMems: _collectMems,
                  collectFpg: _collectFpg,
                  viewBandPass: _viewBandPass,
                  viewFMinHz: _viewFMinHz,
                  viewFMaxHz: _viewFMaxHz,
                  viewNotchHz: _viewNotchHz,
                  checkingImpedance: _checkingImpedance,
                  onStream: _toggleStream,
                  onRecord: _streaming ? _toggleRecording : null,
                  onResistChanged: _streaming
                      ? null
                      : (v) => setState(() => _collectResist = v),
                  onMemsChanged: _streaming
                      ? null
                      : (v) => setState(() => _collectMems = v),
                  onFpgChanged: _streaming
                      ? null
                      : (v) => setState(() => _collectFpg = v),
                  onBandPassChanged: _setBandPassEnabled,
                  onFMinChanged: _setViewFMin,
                  onFMaxChanged: _setViewFMax,
                  onNotchChanged: _setViewNotch,
                  onChooseDirectory: _recording ? null : _chooseDirectory,
                  onQuickMarker: _streaming ? _quickMarker : null,
                  onCustomMarker: _customMarker,
                  onCheckImpedance:
                      isConnected && !_streaming && !widget.demoMode
                          ? _checkImpedance
                          : null,
                  onMarkerReceiverChanged:
                      _streaming || !_markerTransport.supportsNetwork
                          ? null
                          : (v) => setState(() => _markerReceiverEnabled = v),
                  onNetworkOutletChanged:
                      _streaming || !_markerTransport.supportsNetwork
                          ? null
                          : (v) => setState(() => _networkOutletEnabled = v),
                  onLslReceiverChanged: _streaming || !_lslTransport.supportsLsl
                      ? null
                      : (v) => setState(() => _lslReceiverEnabled = v),
                  onLslOutletChanged: _streaming || !_lslTransport.supportsLsl
                      ? null
                      : (v) => setState(() => _lslOutletEnabled = v),
                );
                final overview = _OverviewPanels(
                  channelLabels: _channelLabels,
                  latestQuality: _latestQuality,
                  memsSamples: _memsSamples,
                  latestMems: _latestMems,
                  lostPercent: lostPercent,
                  bandPowers: _bandPowers,
                  bandPowerRelative: _bandPowerRelative,
                  onBandPowerModeChanged: _setBandPowerRelative,
                );
                final charts = _SignalCharts(
                  data: _graphData,
                  channelLabels: _channelLabels,
                  scaleUv: _graphScaleUv,
                  windowSeconds: _plotWindowSeconds,
                  onScaleChanged: (value) =>
                      setState(() => _graphScaleUv = value),
                );
                final peripherals = ListenableBuilder(
                  listenable: _ring,
                  builder: (context, _) => _PeripheralPanel(
                    ring: _ring,
                    recorder: _peripherals,
                    recording: _recording,
                    ringAudioEnabled: _collectRingAudio,
                    onRingAudioChanged: _streaming
                        ? null
                        : (value) => setState(() => _collectRingAudio = value),
                  ),
                );

                if (!wide) {
                  return Scaffold(
                    key: _mobileScaffoldKey,
                    drawer: Drawer(
                      child: SafeArea(child: controlPanel),
                    ),
                    body: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        SizedBox(height: 440, child: peripherals),
                        const SizedBox(height: 12),
                        SizedBox(height: 420, child: overview),
                        const SizedBox(height: 8),
                        SizedBox(height: 820, child: charts),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 340, child: controlPanel),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: max(520, constraints.maxWidth - 376),
                          child: Column(
                            children: [
                              SizedBox(height: 440, child: peripherals),
                              const SizedBox(height: 10),
                              SizedBox(height: 230, child: overview),
                              const SizedBox(height: 10),
                              SizedBox(height: 820, child: charts),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PeripheralPanel extends StatelessWidget {
  const _PeripheralPanel({
    required this.ring,
    required this.recorder,
    required this.recording,
    required this.ringAudioEnabled,
    required this.onRingAudioChanged,
  });

  final RingController ring;
  final PeripheralRecorder recorder;
  final bool recording;
  final bool ringAudioEnabled;
  final ValueChanged<bool>? onRingAudioChanged;

  @override
  Widget build(BuildContext context) {
    final ppg = ring.ppg;
    final imu = ring.imu;
    final deviceAudio = ring.audioFeatures;
    final ppgMetrics = _PpgMetrics.fromSamples(ppg);
    final amplitude = ((recorder.amplitudeDb + 60) / 60).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Sakshi Ring + Microphone',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Chip(
                  avatar: Icon(
                    ring.isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth,
                    size: 16,
                  ),
                  label: Text(ring.status),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed:
                      ring.isConnecting || ring.isConnected ? null : ring.scan,
                  icon: ring.isScanning
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar),
                  label: Text(ring.isScanning ? 'Stop scan' : 'Scan ring'),
                ),
                const SizedBox(width: 8),
                if (ring.isConnected)
                  OutlinedButton(
                    onPressed: recording ? null : ring.disconnect,
                    child: const Text('Disconnect'),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(recorder.selectedInputId),
                    initialValue: recorder.selectedInputId ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Microphone input',
                      prefixIcon: Icon(Icons.mic_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('System default (wired/wireless)'),
                      ),
                      ...recorder.inputs.map(
                        (input) => DropdownMenuItem<String>(
                          value: input.id,
                          child: Text(
                            input.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: recording
                        ? null
                        : (value) => recorder.selectInput(
                              value == null || value.isEmpty ? null : value,
                            ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh microphone inputs',
                  onPressed: recording ? null : recorder.refreshInputs,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (ring.devices.isNotEmpty && !ring.isConnected)
              SizedBox(
                height: 45,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ring.devices.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final device = ring.devices[index];
                    return ActionChip(
                      avatar: const Icon(Icons.watch, size: 16),
                      label: Text('${device.name}  ${device.rssi} dBm'),
                      onPressed: () => ring.connect(device),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.watch_outlined),
              title: const Text('SakshiSense onboard audio'),
              subtitle: Text(ringAudioEnabled
                  ? 'Recording separately to ring_audio.csv'
                  : 'Disabled by default'),
              value: ringAudioEnabled,
              onChanged: onRingAudioChanged,
            ),
            SizedBox(
              height: 118,
              child: Row(
                children: [
                  Expanded(
                    child: _MiniSignal(
                      label: 'Ring PPG raw • ${ring.packets} packets',
                      values: ppg.map((item) => item.ir.toDouble()).toList(),
                      color: const Color(0xffdc2626),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniSignal(
                      label: 'Ring accelerometer X raw',
                      values: imu.map((item) => item.ax.toDouble()).toList(),
                      color: const Color(0xff2563eb),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniSignal(
                      label:
                          'Laptop/mobile mic • ${recorder.amplitudeDb.toStringAsFixed(1)} dBFS',
                      values: recorder.amplitudeHistory,
                      color: const Color(0xff16a34a),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 76,
              child: Row(
                children: [
                  Expanded(
                    child: _MiniSignal(
                      label: ringAudioEnabled
                          ? 'SakshiSense audio • ${deviceAudio.length} packets'
                          : 'SakshiSense audio • disabled',
                      values: ringAudioEnabled
                          ? deviceAudio
                              .map((item) => item.rms.toDouble())
                              .toList()
                          : const [],
                      color: const Color(0xfff97316),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _PpgMetricsCard(metrics: ppgMetrics)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child:
                      LinearProgressIndicator(value: amplitude, minHeight: 8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recorder.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PpgMetrics {
  const _PpgMetrics(
      {this.hr, this.spo2, this.rmssd, required this.sampleCount});

  final double? hr;
  final double? spo2;
  final double? rmssd;
  final int sampleCount;

  factory _PpgMetrics.fromSamples(List<PpgSample> allSamples) {
    if (allSamples.isEmpty) return const _PpgMetrics(sampleCount: 0);
    final newest = allSamples.last.deviceMs;
    final samples = allSamples
        .where((sample) => newest - sample.deviceMs <= 30000)
        .toList(growable: false);
    if (samples.length < 8) {
      return _PpgMetrics(sampleCount: samples.length);
    }
    final ir = samples.map((sample) => sample.ir.toDouble()).toList();
    final red = samples.map((sample) => sample.red.toDouble()).toList();
    final irMean = _mean(ir);
    final redMean = _mean(red);
    final irAc = _rmsAround(ir, irMean);
    final redAc = _rmsAround(red, redMean);
    final ratio = (redAc / max(1, redMean)) / (irAc / max(1, irMean));
    final spo2 =
        ratio.isFinite ? (110 - 25 * ratio).clamp(70, 100).toDouble() : null;

    final range = ir.reduce(max) - ir.reduce(min);
    final threshold = ir.reduce(min) + range * 0.55;
    final peaks = <int>[];
    for (var i = 1; i < ir.length - 1; i++) {
      final enoughSeparation = peaks.isEmpty ||
          samples[i].deviceMs - samples[peaks.last].deviceMs >= 250;
      if (enoughSeparation &&
          ir[i] >= threshold &&
          ir[i] >= ir[i - 1] &&
          ir[i] > ir[i + 1]) {
        peaks.add(i);
      }
    }
    final intervalsMs = <double>[];
    for (var i = 1; i < peaks.length; i++) {
      final interval =
          (samples[peaks[i]].deviceMs - samples[peaks[i - 1]].deviceMs)
              .toDouble();
      if (interval >= 300 && interval <= 2000) intervalsMs.add(interval);
    }
    if (intervalsMs.isEmpty) {
      return _PpgMetrics(sampleCount: samples.length, spo2: spo2);
    }
    final meanInterval = _mean(intervalsMs);
    final hr = 60000 / meanInterval;
    double? rmssd;
    if (intervalsMs.length >= 2) {
      var sum = 0.0;
      for (var i = 1; i < intervalsMs.length; i++) {
        final difference = intervalsMs[i] - intervalsMs[i - 1];
        sum += difference * difference;
      }
      rmssd = sqrt(sum / (intervalsMs.length - 1));
    }
    return _PpgMetrics(
      sampleCount: samples.length,
      hr: hr.isFinite ? hr : null,
      spo2: spo2,
      rmssd: rmssd,
    );
  }

  static double _mean(List<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  static double _rmsAround(List<double> values, double mean) {
    if (values.isEmpty) return 0;
    final sum = values.fold<double>(0, (total, value) {
      final delta = value - mean;
      return total + delta * delta;
    });
    return sqrt(sum / values.length);
  }
}

class _PpgMetricsCard extends StatelessWidget {
  const _PpgMetricsCard({required this.metrics});

  final _PpgMetrics metrics;

  @override
  Widget build(BuildContext context) {
    String value(double? metric, String suffix) =>
        metric == null ? '--' : '${metric.toStringAsFixed(1)}$suffix';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xfff8fafc),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x22334155)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 16,
        runSpacing: 4,
        children: [
          _MetricValue(label: 'HR · 30 s', value: value(metrics.hr, ' bpm')),
          _MetricValue(label: 'SpO₂ · 30 s', value: value(metrics.spo2, '%')),
          _MetricValue(
              label: 'RMSSD · 30 s', value: value(metrics.rmssd, ' ms')),
        ],
      ),
    );
  }
}

class _MetricValue extends StatelessWidget {
  const _MetricValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      );
}

class _MiniSignal extends StatelessWidget {
  const _MiniSignal({
    required this.label,
    required this.values,
    required this.color,
  });
  final String label;
  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Expanded(
            child: CustomPaint(
              painter: _MiniSignalPainter(values, color),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      );
}

class _MiniSignalPainter extends CustomPainter {
  _MiniSignalPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xfff8fafc));
    if (values.length < 2) return;
    final start = max(0, values.length - 180);
    final visible = values.sublist(start);
    var low = visible.first;
    var high = visible.first;
    for (final value in visible) {
      low = min(low, value);
      high = max(high, value);
    }
    final span = max(1.0, high - low);
    final path = Path();
    for (var i = 0; i < visible.length; i++) {
      final x = i * size.width / (visible.length - 1);
      final y = size.height - ((visible[i] - low) / span * size.height);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniSignalPainter oldDelegate) => true;
}

enum ElectrodeStatus { unknown, good, adjust, poor }

double? impedanceKohm(double? value) {
  if (value == null || !value.isFinite) return null;
  final absolute = value.abs();
  return absolute > 1000 ? absolute / 1000 : absolute;
}

ElectrodeStatus electrodeStatus(double? value) {
  final kohm = impedanceKohm(value);
  if (kohm == null) {
    return value != null && value.isInfinite
        ? ElectrodeStatus.poor
        : ElectrodeStatus.unknown;
  }
  if (kohm <= 250) return ElectrodeStatus.good;
  if (kohm <= 1000) return ElectrodeStatus.adjust;
  return ElectrodeStatus.poor;
}

Color electrodeColor(ElectrodeStatus status) {
  switch (status) {
    case ElectrodeStatus.good:
      return const Color(0xff16a34a);
    case ElectrodeStatus.adjust:
      return const Color(0xffd97706);
    case ElectrodeStatus.poor:
      return const Color(0xffdc2626);
    case ElectrodeStatus.unknown:
      return const Color(0xff6b7280);
  }
}

String electrodeStatusLabel(ElectrodeStatus status) {
  switch (status) {
    case ElectrodeStatus.good:
      return 'Good';
    case ElectrodeStatus.adjust:
      return 'Adjust';
    case ElectrodeStatus.poor:
      return 'Poor';
    case ElectrodeStatus.unknown:
      return 'Waiting';
  }
}

String impedanceLabel(double? value) {
  if (value == null) return 'n/a';
  if (value.isInfinite) return 'open';
  if (value.isNaN) return 'invalid';
  final kohm = impedanceKohm(value);
  if (kohm == null) return 'n/a';
  final decimals = kohm < 10 ? 1 : 0;
  return '${kohm.toStringAsFixed(decimals)} kOhm';
}

String _labelAt(List<String> labels, int index) {
  if (index >= 0 && index < labels.length && labels[index].trim().isNotEmpty) {
    return labels[index].trim();
  }
  final safeIndex = index.clamp(0, _fallbackChannels.length - 1).toInt();
  return _fallbackChannels[safeIndex];
}

Offset _electrodePosition(String label) {
  switch (label.trim().toUpperCase()) {
    case 'O1':
      return const Offset(0.38, 0.70);
    case 'O2':
      return const Offset(0.62, 0.70);
    case 'T3':
    case 'T5':
    case 'F7':
      return const Offset(0.20, 0.50);
    case 'T4':
    case 'T6':
    case 'F8':
      return const Offset(0.80, 0.50);
    case 'FP1':
    case 'F3':
      return const Offset(0.38, 0.28);
    case 'FP2':
    case 'F4':
      return const Offset(0.62, 0.28);
    case 'C3':
    case 'P3':
      return const Offset(0.34, 0.50);
    case 'C4':
    case 'P4':
      return const Offset(0.66, 0.50);
    case 'OZ':
    case 'PZ':
    case 'CZ':
    case 'FZ':
    case 'FPZ':
      return const Offset(0.50, 0.50);
    default:
      return const Offset(0.50, 0.56);
  }
}

class _ImpedancePreflightPage extends StatelessWidget {
  const _ImpedancePreflightPage({
    required this.connection,
    required this.status,
    required this.batteryStatus,
    required this.channelLabels,
    required this.latestQuality,
    required this.checkingImpedance,
    required this.monitoringImpedance,
    required this.canCheck,
    required this.canContinue,
    required this.onCheckImpedance,
    required this.onContinue,
  });

  final String connection;
  final String status;
  final String batteryStatus;
  final List<String> channelLabels;
  final List<double?> latestQuality;
  final bool checkingImpedance;
  final bool monitoringImpedance;
  final bool canCheck;
  final bool canContinue;
  final VoidCallback onCheckImpedance;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final goodCount = List.generate(
      4,
      (index) => electrodeStatus(latestQuality[index]),
    ).where((status) => status == ElectrodeStatus.good).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880;
        final summary = _PreflightSummary(
          connection: connection,
          status: status,
          batteryStatus: batteryStatus,
          goodCount: goodCount,
          checkingImpedance: checkingImpedance,
          monitoringImpedance: monitoringImpedance,
          canCheck: canCheck,
          canContinue: canContinue,
          onCheckImpedance: onCheckImpedance,
          onContinue: onContinue,
        );
        final map = _ElectrodeMapPanel(
          channelLabels: channelLabels,
          latestQuality: latestQuality,
        );

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              const SizedBox(height: 12),
              map,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 360, child: summary),
            const SizedBox(width: 12),
            Expanded(child: map),
          ],
        );
      },
    );
  }
}

class _PreflightSummary extends StatelessWidget {
  const _PreflightSummary({
    required this.connection,
    required this.status,
    required this.batteryStatus,
    required this.goodCount,
    required this.checkingImpedance,
    required this.monitoringImpedance,
    required this.canCheck,
    required this.canContinue,
    required this.onCheckImpedance,
    required this.onContinue,
  });

  final String connection;
  final String status;
  final String batteryStatus;
  final int goodCount;
  final bool checkingImpedance;
  final bool monitoringImpedance;
  final bool canCheck;
  final bool canContinue;
  final VoidCallback onCheckImpedance;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Electrode Impedance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(
                  label: Text(connection),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoLine(
              icon: Icons.info_outline,
              label: 'Status',
              value: status,
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.battery_std,
              label: 'Battery',
              value: batteryStatus,
            ),
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.check_circle_outline,
              label: 'Ready',
              value: '$goodCount / 4 green',
            ),
            const Divider(height: 30),
            _LegendDot(
              color: electrodeColor(ElectrodeStatus.good),
              label: 'Good',
              detail: '<= 250 kOhm',
            ),
            const SizedBox(height: 8),
            _LegendDot(
              color: electrodeColor(ElectrodeStatus.adjust),
              label: 'Adjust',
              detail: '250 kOhm-1 MOhm',
            ),
            const SizedBox(height: 8),
            _LegendDot(
              color: electrodeColor(ElectrodeStatus.poor),
              label: 'Poor/open',
              detail: '> 1 MOhm',
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: checkingImpedance || !canCheck || monitoringImpedance
                  ? null
                  : onCheckImpedance,
              icon: const Icon(Icons.electrical_services_outlined),
              label: Text(checkingImpedance
                  ? 'Starting Monitor'
                  : monitoringImpedance
                      ? 'Monitoring Live'
                      : 'Start Monitoring'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: canContinue ? onContinue : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue to Data Collection'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.detail,
  });

  final Color color;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(detail, style: TextStyle(color: Colors.grey.shade700)),
      ],
    );
  }
}

class _ElectrodeMapPanel extends StatelessWidget {
  const _ElectrodeMapPanel({
    required this.channelLabels,
    required this.latestQuality,
  });

  final List<String> channelLabels;
  final List<double?> latestQuality;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Headset Fit', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SizedBox(
              height: 380,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: AspectRatio(
                    aspectRatio: 1.35,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xfff8fafc),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(painter: _HeadOutlinePainter()),
                        ),
                        for (var i = 0; i < 4; i++)
                          _PositionedElectrode(
                            label: _labelAt(channelLabels, i),
                            value: latestQuality[i],
                            x: _electrodePosition(_labelAt(channelLabels, i))
                                .dx,
                            y: _electrodePosition(_labelAt(channelLabels, i))
                                .dy,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < 4; i++)
                  _ElectrodeTile(
                    label: _labelAt(channelLabels, i),
                    value: latestQuality[i],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PositionedElectrode extends StatelessWidget {
  const _PositionedElectrode({
    required this.label,
    required this.value,
    required this.x,
    required this.y,
  });

  final String label;
  final double? value;
  final double x;
  final double y;

  @override
  Widget build(BuildContext context) {
    final status = electrodeStatus(value);
    final color = electrodeColor(status);

    return Align(
      alignment: Alignment((x * 2) - 1, (y * 2) - 1),
      child: Tooltip(
        message: '$label ${impedanceLabel(value)}',
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: color.withAlpha(34),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(35),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                electrodeStatusLabel(status),
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ElectrodeTile extends StatelessWidget {
  const _ElectrodeTile({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final status = electrodeStatus(value);
    final color = electrodeColor(status);
    final icon = status == ElectrodeStatus.good
        ? Icons.check_circle
        : status == ElectrodeStatus.adjust
            ? Icons.warning_amber_rounded
            : status == ElectrodeStatus.poor
                ? Icons.error
                : Icons.radio_button_unchecked;

    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(130)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  impedanceLabel(value),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = const Color(0xff334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final guide = Paint()
      ..color = const Color(0x1f334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final center = Offset(size.width / 2, size.height / 2);
    final headRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.52,
      height: size.height * 0.78,
    );
    canvas.drawOval(headRect, outline);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.2, size.height * 0.5),
        width: size.width * 0.13,
        height: size.height * 0.2,
      ),
      -pi / 2,
      pi,
      false,
      outline,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.8, size.height * 0.5),
        width: size.width * 0.13,
        height: size.height * 0.2,
      ),
      pi / 2,
      pi,
      false,
      outline,
    );
    canvas.drawLine(
      Offset(center.dx, headRect.top + 24),
      Offset(center.dx, headRect.bottom - 24),
      guide,
    );
    canvas.drawLine(
      Offset(headRect.left + 22, center.dy),
      Offset(headRect.right - 22, center.dy),
      guide,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.connection,
    required this.status,
    required this.battery,
    required this.batteryStatus,
    required this.sampleRateHz,
    required this.exportTarget,
    required this.markerStatus,
    required this.lastMarker,
    required this.markerCount,
    required this.udpSupported,
    required this.markerReceiverEnabled,
    required this.networkOutletEnabled,
    required this.lslSupported,
    required this.lslReceiverEnabled,
    required this.lslOutletEnabled,
    required this.lslStatus,
    required this.markerPort,
    required this.outletPort,
    required this.outletHost,
    required this.quickMarkers,
    required this.metadata,
    required this.streaming,
    required this.recording,
    required this.canStream,
    required this.elapsed,
    required this.recordElapsed,
    required this.receivedSamples,
    required this.lostPackets,
    required this.droppedBursts,
    required this.collectResist,
    required this.collectMems,
    required this.collectFpg,
    required this.viewBandPass,
    required this.viewFMinHz,
    required this.viewFMaxHz,
    required this.viewNotchHz,
    required this.checkingImpedance,
    required this.onStream,
    required this.onRecord,
    required this.onResistChanged,
    required this.onMemsChanged,
    required this.onFpgChanged,
    required this.onBandPassChanged,
    required this.onFMinChanged,
    required this.onFMaxChanged,
    required this.onNotchChanged,
    required this.onChooseDirectory,
    required this.onQuickMarker,
    required this.onCustomMarker,
    required this.onCheckImpedance,
    required this.onMarkerReceiverChanged,
    required this.onNetworkOutletChanged,
    required this.onLslReceiverChanged,
    required this.onLslOutletChanged,
  });

  final String connection;
  final String status;
  final int battery;
  final String batteryStatus;
  final int sampleRateHz;
  final String exportTarget;
  final String markerStatus;
  final String lastMarker;
  final int markerCount;
  final bool udpSupported;
  final bool markerReceiverEnabled;
  final bool networkOutletEnabled;
  final bool lslSupported;
  final bool lslReceiverEnabled;
  final bool lslOutletEnabled;
  final String lslStatus;
  final int markerPort;
  final int outletPort;
  final String outletHost;
  final List<String> quickMarkers;
  final RecordingMetadata metadata;
  final bool streaming;
  final bool recording;
  final bool canStream;
  final String elapsed;
  final String recordElapsed;
  final int receivedSamples;
  final int lostPackets;
  final int droppedBursts;
  final bool collectResist;
  final bool collectMems;
  final bool collectFpg;
  final bool viewBandPass;
  final double viewFMinHz;
  final double viewFMaxHz;
  final int? viewNotchHz;
  final bool checkingImpedance;
  final VoidCallback onStream;
  final VoidCallback? onRecord;
  final ValueChanged<bool>? onResistChanged;
  final ValueChanged<bool>? onMemsChanged;
  final ValueChanged<bool>? onFpgChanged;
  final ValueChanged<bool> onBandPassChanged;
  final ValueChanged<double> onFMinChanged;
  final ValueChanged<double> onFMaxChanged;
  final ValueChanged<int?> onNotchChanged;
  final VoidCallback? onChooseDirectory;
  final ValueChanged<String>? onQuickMarker;
  final VoidCallback? onCustomMarker;
  final VoidCallback? onCheckImpedance;
  final ValueChanged<bool>? onMarkerReceiverChanged;
  final ValueChanged<bool>? onNetworkOutletChanged;
  final ValueChanged<bool>? onLslReceiverChanged;
  final ValueChanged<bool>? onLslOutletChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Session Control',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              if (recording)
                const _RecordingPill()
              else
                Chip(
                    label: Text(connection),
                    visualDensity: VisualDensity.compact),
            ],
          ),
          const SizedBox(height: 12),
          _InfoLine(
            icon: Icons.info_outline,
            label: 'Status',
            value: status,
            maxLines: 5,
          ),
          const SizedBox(height: 8),
          _InfoLine(
              icon: Icons.speed, label: 'EEG rate', value: '$sampleRateHz Hz'),
          const SizedBox(height: 8),
          _InfoLine(
              icon: Icons.battery_std,
              label: 'Battery',
              value: battery == 0 ? batteryStatus : batteryStatus),
          const SizedBox(height: 8),
          _InfoLine(
              icon: Icons.folder_outlined,
              label: 'Export',
              value: exportTarget),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onChooseDirectory,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Change Export Folder'),
          ),
          const Divider(height: 28),
          _InfoLine(
              icon: Icons.badge_outlined,
              label: 'Subject',
              value: metadata.subjectId),
          const SizedBox(height: 8),
          _InfoLine(
              icon: Icons.route_outlined,
              label: 'Protocol',
              value: metadata.protocol),
          const SizedBox(height: 8),
          _InfoLine(
            icon: Icons.event_note_outlined,
            label: 'Session / day',
            value: '${metadata.sessionNumber} / ${metadata.day}',
          ),
          if (metadata.customQuestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.quiz_outlined,
              label: 'Questions',
              value: '${metadata.customQuestions.length} answered',
            ),
          ],
          const Divider(height: 28),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Resistance/contact quality'),
            value: collectResist,
            onChanged: onResistChanged,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Motion data'),
            value: collectMems,
            onChanged: onMemsChanged,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('FPG/PPG data'),
            value: collectFpg,
            onChanged: onFpgChanged,
          ),
          _DisplayFilterControls(
            bandPassEnabled: viewBandPass,
            fMinHz: viewFMinHz,
            fMaxHz: viewFMaxHz,
            notchHz: viewNotchHz,
            onBandPassChanged: onBandPassChanged,
            onFMinChanged: onFMinChanged,
            onFMaxChanged: onFMaxChanged,
            onNotchChanged: onNotchChanged,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: checkingImpedance ? null : onCheckImpedance,
            icon: const Icon(Icons.electrical_services_outlined),
            label: Text(checkingImpedance
                ? 'Checking Impedance'
                : 'Check Electrode Impedance'),
          ),
          const Divider(height: 28),
          _InfoLine(
            icon: Icons.flag_outlined,
            label: 'Markers',
            value: markerStatus,
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          _InfoLine(
            icon: Icons.history,
            label: 'Last',
            value: '$lastMarker ($markerCount)',
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in quickMarkers)
                OutlinedButton(
                  onPressed:
                      onQuickMarker == null ? null : () => onQuickMarker!(code),
                  child: Text(code),
                ),
              OutlinedButton.icon(
                onPressed: onCustomMarker,
                icon: const Icon(Icons.add),
                label: const Text('Custom'),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('UDP marker receiver :$markerPort'),
            subtitle: udpSupported ? null : const Text('Unavailable on web'),
            value: udpSupported && markerReceiverEnabled,
            onChanged: onMarkerReceiverChanged,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('UDP outlet $outletHost:$outletPort'),
            subtitle: udpSupported ? null : const Text('Unavailable on web'),
            value: udpSupported && networkOutletEnabled,
            onChanged: onNetworkOutletChanged,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('LSL marker receiver'),
            subtitle: Text(lslSupported ? lslStatus : 'Unavailable on web'),
            value: lslSupported && lslReceiverEnabled,
            onChanged: onLslReceiverChanged,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('LSL string/int marker outlets'),
            subtitle: const Text(
              'UnifiedMarkersString and UnifiedMarkersInt',
            ),
            value: lslSupported && lslOutletEnabled,
            onChanged: onLslOutletChanged,
          ),
          const Divider(height: 28),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Counter(label: 'Stream', value: elapsed),
              _Counter(
                  label: 'Record', value: recording ? recordElapsed : '00:00'),
              _Counter(
                  label: 'Samples',
                  value: NumberFormat.compact().format(receivedSamples)),
              _Counter(label: 'Lost', value: lostPackets.toString()),
              _Counter(label: 'Gaps', value: droppedBursts.toString()),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: canStream ? onStream : null,
            icon: Icon(streaming ? Icons.stop : Icons.play_arrow),
            label: Text(streaming ? 'Stop Stream' : 'Start Stream'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: onRecord,
            icon: Icon(recording
                ? Icons.stop_circle_outlined
                : Icons.fiber_manual_record),
            label: Text(recording ? 'Stop Recording' : 'Record Raw Data'),
          ),
        ],
      ),
    );
  }
}

class _DisplayFilterControls extends StatelessWidget {
  const _DisplayFilterControls({
    required this.bandPassEnabled,
    required this.fMinHz,
    required this.fMaxHz,
    required this.notchHz,
    required this.onBandPassChanged,
    required this.onFMinChanged,
    required this.onFMaxChanged,
    required this.onNotchChanged,
  });

  final bool bandPassEnabled;
  final double fMinHz;
  final double fMaxHz;
  final int? notchHz;
  final ValueChanged<bool> onBandPassChanged;
  final ValueChanged<double> onFMinChanged;
  final ValueChanged<double> onFMaxChanged;
  final ValueChanged<int?> onNotchChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: true,
      title: const Text('Display filters'),
      subtitle: Text(
        'View only: ${bandPassEnabled ? '${fMinHz.toStringAsFixed(1)}-${fMaxHz.round()} Hz' : 'wideband'}, notch ${notchHz == null ? 'off' : '$notchHz Hz'}',
      ),
      childrenPadding: EdgeInsets.zero,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Band-pass preview'),
          value: bandPassEnabled,
          onChanged: onBandPassChanged,
        ),
        _FilterSlider(
          label: 'Low edge',
          value: fMinHz,
          min: 0.1,
          max: 10,
          divisions: 99,
          suffix: 'Hz',
          onChanged: bandPassEnabled ? onFMinChanged : null,
        ),
        _FilterSlider(
          label: 'High edge',
          value: fMaxHz,
          min: 20,
          max: 100,
          divisions: 16,
          suffix: 'Hz',
          onChanged: bandPassEnabled ? onFMaxChanged : null,
        ),
        Row(
          children: [
            const Expanded(child: Text('Notch')),
            DropdownButton<int?>(
              value: notchHz,
              items: const [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Off'),
                ),
                DropdownMenuItem<int?>(
                  value: 50,
                  child: Text('50 Hz'),
                ),
                DropdownMenuItem<int?>(
                  value: 60,
                  child: Text('60 Hz'),
                ),
              ],
              onChanged: onNotchChanged,
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterSlider extends StatelessWidget {
  const _FilterSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = value < 10 ? value.toStringAsFixed(1) : value.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('$shown $suffix',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max),
          label: '$shown $suffix',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _OverviewPanels extends StatelessWidget {
  const _OverviewPanels({
    required this.channelLabels,
    required this.latestQuality,
    required this.memsSamples,
    required this.latestMems,
    required this.lostPercent,
    required this.bandPowers,
    required this.bandPowerRelative,
    required this.onBandPowerModeChanged,
  });

  final List<String> channelLabels;
  final List<double?> latestQuality;
  final int memsSamples;
  final String latestMems;
  final double lostPercent;
  final List<List<double>> bandPowers;
  final bool bandPowerRelative;
  final ValueChanged<bool> onBandPowerModeChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final quality = _SignalStatusPanel(
          channelLabels: channelLabels,
          latestQuality: latestQuality,
          memsSamples: memsSamples,
          latestMems: latestMems,
          lostPercent: lostPercent,
        );
        final bands = _BandPowerPanel(
          channelLabels: channelLabels,
          bandPowers: bandPowers,
          relativeMode: bandPowerRelative,
          onModeChanged: onBandPowerModeChanged,
        );
        if (!wide) {
          return Column(
            children: [
              Expanded(child: quality),
              const SizedBox(height: 8),
              Expanded(child: bands),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: quality),
            const SizedBox(width: 8),
            Expanded(child: bands),
          ],
        );
      },
    );
  }
}

class _SignalStatusPanel extends StatelessWidget {
  const _SignalStatusPanel({
    required this.channelLabels,
    required this.latestQuality,
    required this.memsSamples,
    required this.latestMems,
    required this.lostPercent,
  });

  final List<String> channelLabels;
  final List<double?> latestQuality;
  final int memsSamples;
  final String latestMems;
  final double lostPercent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Signal Status',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < 4; i++)
                  _QualityChip(
                    label: _labelAt(channelLabels, i),
                    value: latestQuality[i],
                  ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: _SmallStatus(
                    label: 'Loss',
                    value: '${lostPercent.toStringAsFixed(3)}%',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SmallStatus(
                    label: 'IMU',
                    value:
                        '${NumberFormat.compact().format(memsSamples)} samples',
                    detail: latestMems,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final status = electrodeStatus(value);
    final color = electrodeColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(130)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 7),
          Text(impedanceLabel(value)),
        ],
      ),
    );
  }
}

class _SmallStatus extends StatelessWidget {
  const _SmallStatus({
    required this.label,
    required this.value,
    this.detail = '',
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withAlpha(13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (detail.isNotEmpty)
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _BandPowerPanel extends StatelessWidget {
  const _BandPowerPanel({
    required this.channelLabels,
    required this.bandPowers,
    required this.relativeMode,
    required this.onModeChanged,
  });

  final List<String> channelLabels;
  final List<List<double>> bandPowers;
  final bool relativeMode;
  final ValueChanged<bool> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final finite = bandPowers
        .expand((channelPowers) => channelPowers)
        .where((value) => value.isFinite)
        .toList();
    final minPower = finite.isEmpty ? 0.0 : finite.reduce(min);
    final maxPower = finite.isEmpty ? 0.0 : finite.reduce(max);
    final minY = relativeMode
        ? 0.0
        : min(-10.0, (minPower / 10).floor() * 10).toDouble();
    final maxY = relativeMode
        ? 100.0
        : max(10.0, (maxPower / 10).ceil() * 10).toDouble();
    final interval = relativeMode ? 50.0 : 10.0;
    final suffix = relativeMode ? '%' : 'dB';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    relativeMode ? 'Relative Band Power' : 'Band Power (dB)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('%'),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('dB'),
                    ),
                  ],
                  selected: {relativeMode},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (selection) =>
                      onModeChanged(selection.first),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (var i = 0; i < channelLabels.length && i < 4; i++)
                  _BandLegendDot(
                    label: _labelAt(channelLabels, i),
                    color: _channelColors[i],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: BarChart(
                BarChartData(
                  minY: minY,
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(enabled: false),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: relativeMode ? 25 : 10,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: Color(0x14000000),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: interval,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.round()}$suffix',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= _bands.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _bands[index].shortLabel,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var band = 0; band < _bands.length; band++)
                      BarChartGroupData(
                        x: band,
                        barsSpace: 2,
                        barRods: [
                          for (var channel = 0; channel < 4; channel++)
                            BarChartRodData(
                              toY: _channelBandPower(channel, band),
                              fromY: relativeMode ? 0.0 : minY,
                              width: 7,
                              color: _channelColors[channel],
                              borderRadius: BorderRadius.circular(3),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _channelBandPower(int channel, int band) {
    if (channel < 0 || channel >= bandPowers.length) return 0;
    final channelPowers = bandPowers[channel];
    if (band < 0 || band >= channelPowers.length) return 0;
    final value = channelPowers[band];
    return value.isFinite ? value : 0;
  }
}

class _BandLegendDot extends StatelessWidget {
  const _BandLegendDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _SignalCharts extends StatelessWidget {
  const _SignalCharts({
    required this.data,
    required this.channelLabels,
    required this.scaleUv,
    required this.windowSeconds,
    required this.onScaleChanged,
  });

  final List<List<FlSpot>> data;
  final List<String> channelLabels;
  final double scaleUv;
  final double windowSeconds;
  final ValueChanged<double> onScaleChanged;

  @override
  Widget build(BuildContext context) {
    const minX = 0.0;
    final maxX = windowSeconds;
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('EEG signal preview • recording is always raw',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                SizedBox(
                  width: 220,
                  child: Row(
                    children: [
                      const Icon(Icons.height, size: 18),
                      Expanded(
                        child: Slider(
                          min: 25,
                          max: 500,
                          divisions: 19,
                          value: scaleUv.clamp(25, 500),
                          label: '+/- ${scaleUv.round()} uV',
                          onChanged: onScaleChanged,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: 4,
              itemBuilder: (context, index) {
                return SizedBox(
                  height: 150,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xff101418),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 42,
                            child: Center(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Text(
                                  _labelAt(channelLabels, index),
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
                              child: LineChart(
                                LineChartData(
                                  clipData: const FlClipData.all(),
                                  minX: minX,
                                  maxX: maxX,
                                  minY: -scaleUv,
                                  maxY: scaleUv,
                                  lineTouchData:
                                      const LineTouchData(enabled: false),
                                  titlesData: FlTitlesData(
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 42,
                                        interval: scaleUv,
                                        getTitlesWidget: (value, meta) {
                                          if (value.abs() < 0.001) {
                                            return const Text(
                                              '0',
                                              style: TextStyle(
                                                color: Colors.white54,
                                                fontSize: 10,
                                              ),
                                            );
                                          }
                                          return Text(
                                            value.round().toString(),
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 10,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 22,
                                        interval: 2,
                                        getTitlesWidget: (value, meta) {
                                          if (value == 0 ||
                                              value >= windowSeconds) {
                                            return const SizedBox.shrink();
                                          }
                                          return Text(
                                            '${value.round()}s',
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 10,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: true,
                                    horizontalInterval: scaleUv / 2,
                                    getDrawingHorizontalLine: (_) =>
                                        const FlLine(
                                      color: Color(0x22ffffff),
                                      strokeWidth: 1,
                                    ),
                                    getDrawingVerticalLine: (_) => const FlLine(
                                      color: Color(0x12ffffff),
                                      strokeWidth: 1,
                                    ),
                                  ),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: data[index],
                                      color: const Color(0xff4ade80),
                                      barWidth: 1.2,
                                      isCurved: false,
                                      dotData: const FlDotData(show: false),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MetadataDialog extends StatefulWidget {
  const MetadataDialog({super.key, required this.initial});

  final RecordingMetadata initial;

  @override
  State<MetadataDialog> createState() => _MetadataDialogState();
}

class _MetadataDialogState extends State<MetadataDialog> {
  late final TextEditingController _subject;
  late final TextEditingController _protocol;
  late final TextEditingController _operator;
  late final TextEditingController _notes;
  late final TextEditingController _sessionNumber;
  late final TextEditingController _day;
  final List<(TextEditingController, TextEditingController)> _questions = [];

  @override
  void initState() {
    super.initState();
    _subject = TextEditingController(text: widget.initial.subjectId);
    _protocol = TextEditingController(text: widget.initial.protocol);
    _operator = TextEditingController(text: widget.initial.operatorName);
    _notes = TextEditingController(text: widget.initial.notes);
    _sessionNumber = TextEditingController(text: widget.initial.sessionNumber);
    _day = TextEditingController(text: widget.initial.day);
    for (final entry in widget.initial.customQuestions.entries) {
      _questions.add((
        TextEditingController(text: entry.key),
        TextEditingController(text: entry.value),
      ));
    }
  }

  @override
  void dispose() {
    _subject.dispose();
    _protocol.dispose();
    _operator.dispose();
    _notes.dispose();
    _sessionNumber.dispose();
    _day.dispose();
    for (final (question, answer) in _questions) {
      question.dispose();
      answer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Session Metadata'),
      content: SizedBox(
        width: 520,
        height: 560,
        child: ListView(
          children: [
            TextField(
                controller: _subject,
                decoration: const InputDecoration(labelText: 'Subject ID')),
            const SizedBox(height: 10),
            TextField(
                controller: _protocol,
                decoration: const InputDecoration(labelText: 'Protocol')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sessionNumber,
                    decoration:
                        const InputDecoration(labelText: 'Session number'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _day,
                    decoration: const InputDecoration(labelText: 'Day'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
                controller: _operator,
                decoration: const InputDecoration(labelText: 'Operator')),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Custom questions',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _questions.add(
                        (TextEditingController(), TextEditingController()));
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('Add question'),
                ),
              ],
            ),
            for (var i = 0; i < _questions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _questions[i].$1,
                        decoration:
                            const InputDecoration(labelText: 'Question'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _questions[i].$2,
                        decoration: const InputDecoration(labelText: 'Answer'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove question',
                      onPressed: () => setState(() {
                        final removed = _questions.removeAt(i);
                        removed.$1.dispose();
                        removed.$2.dispose();
                      }),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              RecordingMetadata(
                subjectId: _subject.text.trim().isEmpty
                    ? 'anonymous'
                    : _subject.text.trim(),
                protocol: _protocol.text.trim().isEmpty
                    ? 'resting-state'
                    : _protocol.text.trim(),
                operatorName: _operator.text.trim(),
                notes: _notes.text.trim(),
                sessionNumber: _sessionNumber.text.trim(),
                day: _day.text.trim(),
                customQuestions: {
                  for (final (question, answer) in _questions)
                    if (question.text.trim().isNotEmpty)
                      question.text.trim(): answer.text.trim(),
                },
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class BandDefinition {
  const BandDefinition(this.label, this.lowHz, this.highHz, this.color);

  final String label;
  final double lowHz;
  final double highHz;
  final Color color;

  String get shortLabel => label.substring(0, 1);
}

class PreviewFilterChain {
  BiquadFilter? _highPass;
  BiquadFilter? _lowPass;
  BiquadFilter? _notch;
  int? _sampleRateHz;
  bool? _bandPassEnabled;
  double? _fMinHz;
  double? _fMaxHz;
  int? _notchHz;

  double apply(
    double value, {
    required int sampleRateHz,
    required bool bandPassEnabled,
    required double fMinHz,
    required double fMaxHz,
    required int? notchHz,
  }) {
    _configureIfNeeded(
      sampleRateHz: sampleRateHz,
      bandPassEnabled: bandPassEnabled,
      fMinHz: fMinHz,
      fMaxHz: fMaxHz,
      notchHz: notchHz,
    );

    var next = value;
    if (bandPassEnabled) {
      next = _highPass?.process(next) ?? next;
      next = _lowPass?.process(next) ?? next;
    }
    next = _notch?.process(next) ?? next;
    return next;
  }

  void _configureIfNeeded({
    required int sampleRateHz,
    required bool bandPassEnabled,
    required double fMinHz,
    required double fMaxHz,
    required int? notchHz,
  }) {
    if (_sampleRateHz == sampleRateHz &&
        _bandPassEnabled == bandPassEnabled &&
        _fMinHz == fMinHz &&
        _fMaxHz == fMaxHz &&
        _notchHz == notchHz) {
      return;
    }
    _sampleRateHz = sampleRateHz;
    _bandPassEnabled = bandPassEnabled;
    _fMinHz = fMinHz;
    _fMaxHz = fMaxHz;
    _notchHz = notchHz;

    final nyquist = sampleRateHz / 2;
    final highEdge = fMaxHz.clamp(1, nyquist - 1).toDouble();
    final lowEdge = fMinHz.clamp(0.1, highEdge - 0.5).toDouble();
    _highPass = bandPassEnabled
        ? BiquadFilter.highPass(sampleRateHz.toDouble(), lowEdge)
        : null;
    _lowPass = bandPassEnabled
        ? BiquadFilter.lowPass(sampleRateHz.toDouble(), highEdge)
        : null;
    _notch = notchHz == null
        ? null
        : BiquadFilter.notch(sampleRateHz.toDouble(), notchHz.toDouble());
  }

  void reset() {
    _highPass?.reset();
    _lowPass?.reset();
    _notch?.reset();
    _sampleRateHz = null;
  }
}

class BiquadFilter {
  BiquadFilter._({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  factory BiquadFilter.highPass(double sampleRate, double frequency) {
    return BiquadFilter._fromCookbook(
      sampleRate: sampleRate,
      frequency: frequency,
      q: sqrt1_2,
      kind: _BiquadKind.highPass,
    );
  }

  factory BiquadFilter.lowPass(double sampleRate, double frequency) {
    return BiquadFilter._fromCookbook(
      sampleRate: sampleRate,
      frequency: frequency,
      q: sqrt1_2,
      kind: _BiquadKind.lowPass,
    );
  }

  factory BiquadFilter.notch(double sampleRate, double frequency) {
    return BiquadFilter._fromCookbook(
      sampleRate: sampleRate,
      frequency: frequency,
      q: 30,
      kind: _BiquadKind.notch,
    );
  }

  factory BiquadFilter._fromCookbook({
    required double sampleRate,
    required double frequency,
    required double q,
    required _BiquadKind kind,
  }) {
    final omega = 2 * pi * frequency / sampleRate;
    final cosw = cos(omega);
    final alpha = sin(omega) / (2 * q);
    late double b0;
    late double b1;
    late double b2;
    late double a0;
    late double a1;
    late double a2;

    switch (kind) {
      case _BiquadKind.highPass:
        b0 = (1 + cosw) / 2;
        b1 = -(1 + cosw);
        b2 = (1 + cosw) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosw;
        a2 = 1 - alpha;
        break;
      case _BiquadKind.lowPass:
        b0 = (1 - cosw) / 2;
        b1 = 1 - cosw;
        b2 = (1 - cosw) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosw;
        a2 = 1 - alpha;
        break;
      case _BiquadKind.notch:
        b0 = 1;
        b1 = -2 * cosw;
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2 * cosw;
        a2 = 1 - alpha;
        break;
    }

    return BiquadFilter._(
      b0: b0 / a0,
      b1: b1 / a0,
      b2: b2 / a0,
      a1: a1 / a0,
      a2: a2 / a0,
    );
  }

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;
  double _x1 = 0;
  double _x2 = 0;
  double _y1 = 0;
  double _y2 = 0;

  double process(double x0) {
    final y0 = (b0 * x0) + (b1 * _x1) + (b2 * _x2) - (a1 * _y1) - (a2 * _y2);
    _x2 = _x1;
    _x1 = x0;
    _y2 = _y1;
    _y1 = y0;
    return y0.isFinite ? y0 : 0;
  }

  void reset() {
    _x1 = 0;
    _x2 = 0;
    _y1 = 0;
    _y2 = 0;
  }
}

enum _BiquadKind { highPass, lowPass, notch }

class RecordingMetadata {
  RecordingMetadata({
    required this.subjectId,
    required this.protocol,
    required this.operatorName,
    required this.notes,
    required this.sessionNumber,
    required this.day,
    required this.customQuestions,
  });

  factory RecordingMetadata.defaults() => RecordingMetadata(
        subjectId: 'anonymous',
        protocol: 'resting-state',
        operatorName: '',
        notes: '',
        sessionNumber: '1',
        day: '1',
        customQuestions: const {},
      );

  final String subjectId;
  final String protocol;
  final String operatorName;
  final String notes;
  final String sessionNumber;
  final String day;
  final Map<String, String> customQuestions;
}

class DemoSample {
  DemoSample({
    required this.packet,
    required this.marker,
    required this.values,
  });

  final int packet;
  final int marker;
  final List<double> values;
}

class PendingMarker {
  PendingMarker({
    required this.code,
    required this.source,
    required this.detail,
    required this.hostUnixUs,
    required this.hostMonotonicUs,
  });

  final String code;
  final String source;
  final String detail;
  final int hostUnixUs;
  final int hostMonotonicUs;
}

class PacketClock {
  int? _lastPacket;
  int _wraps = 0;
  int _totalLost = 0;
  int _generatedPacket = 0;

  int get totalLost => _totalLost;

  void reset() {
    _lastPacket = null;
    _wraps = 0;
    _totalLost = 0;
    _generatedPacket = 0;
  }

  int peekNextPacket() => _generatedPacket % _packetModulo;

  int peekNextIndex() => _generatedPacket;

  void skipPackets(int count) {
    _generatedPacket += count;
  }

  PacketStamp accept(int packet) {
    if (_lastPacket != null &&
        packet < _lastPacket! &&
        (_lastPacket! - packet) > (_packetModulo ~/ 2)) {
      _wraps++;
    }
    var lost = 0;
    if (_lastPacket != null) {
      final expected = (_lastPacket! + 1) % _packetModulo;
      lost = (packet - expected) % _packetModulo;
      if (lost < 0) lost += _packetModulo;
      if (lost > _packetModulo ~/ 2) lost = 0;
      _totalLost += lost;
    }
    _lastPacket = packet;
    final unwrapped = (_wraps * _packetModulo) + packet;
    _generatedPacket = max(_generatedPacket + 1, unwrapped + 1);
    return PacketStamp(
      unwrappedPacket: unwrapped,
      lostBefore: lost,
      totalLost: _totalLost,
    );
  }
}

class PacketStamp {
  PacketStamp({
    required this.unwrappedPacket,
    required this.lostBefore,
    required this.totalLost,
  });

  final int unwrappedPacket;
  final int lostBefore;
  final int totalLost;
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.maxLines = 2,
  });

  final IconData icon;
  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        SizedBox(
          width: 94,
          child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withAlpha(13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _RecordingPill extends StatelessWidget {
  const _RecordingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: Colors.red.shade600),
          const SizedBox(width: 6),
          Text('REC',
              style: TextStyle(
                  color: Colors.red.shade700, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

String _csv(Object? value) {
  final text = (value ?? '').toString();
  if (!text.contains(',') && !text.contains('"') && !text.contains('\n')) {
    return text;
  }
  return '"${text.replaceAll('"', '""')}"';
}

String _isoFromUnixUs(int unixUs) =>
    DateTime.fromMicrosecondsSinceEpoch(unixUs, isUtc: true).toIso8601String();

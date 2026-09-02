# Unified Research Acquisition

Flutter app for synchronized research acquisition from:

- a 4-channel BrainBit headset through `neurosdk2`;
- Sakshi Ring PPG, IMU, and audio-feature BLE characteristics;
- a selectable system, wired, or wireless microphone.

The acquisition screen shows raw EEG, ring PPG/IMU, separate onboard and
laptop/mobile microphone traces, rolling 30-second HR/SpO₂/RMSSD estimates,
impedance, packet health, and recording state. One session recording produces:

- `manifest.json` — participant, session/day, custom questions, devices, and settings;
- `eeg_raw.csv`, `quality.csv`, `mems.csv`, `fpg.csv` — BrainBit streams;
- `ring_raw.csv` — synchronized Sakshi Ring PPG/IMU packets;
- `ring_audio.csv` — optional SakshiSense onboard audio features (disabled by default);
- `microphone.wav` — 48 kHz mono raw microphone recording;
- `events.csv` — recording events and manual/network markers.

Files default to `~/Documents/UnifiedAcquisition/<session_id>` on desktop.

## UDP markers

Open the LAN icon before starting a stream to configure receive port, target
host/IP, and send port. The receiver binds to all IPv4 interfaces, not only
localhost. Plain text, integer text, and JSON messages are accepted:

```text
stimulus_A
42
{"marker":"trial_start","detail":"trial 3"}
{"marker":7,"detail":"response"}
```

Manual values that parse as integers are transmitted with JSON `value_type`
`int`; other values use `string`. Quick/custom marker buttons and incoming UDP
markers share the session clock and are written to `events.csv` and attached to
the next EEG sample.

## LSL markers

LSL is an optional second marker transport on macOS, Windows, Android, Linux,
and iOS. Enable the LSL receiver and/or outlets before starting the stream. The
app publishes two standard irregular-rate marker streams so native marker types
are preserved:

- `UnifiedMarkersString` (`string`)
- `UnifiedMarkersInt` (`int32`)

Incoming LSL streams with type `Markers` are discovered automatically. Their
values and LSL timestamps are added to the same local event timeline as UDP and
manual markers. Web browsers cannot use native liblsl or raw UDP sockets, so
the web build keeps manual/local markers and clearly disables both network
transports.

Android LSL discovery requires Wi-Fi multicast; the required internet, Wi-Fi,
network-state, and multicast permissions are included. Managed networks and
host firewalls can still block multicast discovery.

## Run

```sh
flutter pub get
flutter run
```

The setup screen controls BrainBit, SakshiSense Ring, and microphone
connections independently. You can continue with any available combination,
and disconnect the ring or microphone separately from the acquisition screen.
The ring panel shows live PPG/IMU, onboard audio RMS classification, motion
inference, and laptop/browser microphone level.

Release builds:

```sh
flutter build macos --release
flutter build web --release
flutter build apk --release
flutter build windows --release  # run on Windows
```

The repository workflows `.github/workflows/build.yml` and `.github/workflows/windows-build.yml` build and upload platform artifacts on their native GitHub runners. For Windows, GitHub Actions builds the release executable, packages a portable ZIP (`unified-acquisition-windows-x64.zip`), and generates a standalone Windows installer (`UnifiedAcquisition-Setup.exe`).

## Public releases

Versioned Android APK, Windows portable ZIP and installer, macOS application
ZIP, and Web application ZIP downloads are published on the public
[GitHub Releases page](https://github.com/manasaitech/SakshiSense-UnifiedAcquisition/releases).
See [CHANGELOG.md](CHANGELOG.md) for release details and hardware limitations.

The deployed web app is protected by a Cloudflare Pages edge login. The
current session passcode is managed as a Cloudflare secret; use `/__logout` to
clear an active browser session.

Web Bluetooth acquisition is supported in Chrome/Edge over HTTPS for the
Sakshi Ring (PPG, IMU, optional onboard audio) and browser microphone. Open
`Start Web BLE / Scan` from the setup screen, choose the ring in the browser
permission dialog, then start the session. BrainBit EEG still requires the
native Android, iOS, macOS, or Windows build because the Flutter Neurosdk2
plugin has no web implementation; the browser session deliberately does not
pretend to scan for an unsupported headset.

## Browser LSL bridge

Web browsers cannot use native LSL sockets directly. To transmit and receive
LSL marker streams from the web app, run the local bridge on the acquisition
computer:

```sh
cd lsl_bridge
npm install
npm start
```

Then enable the LSL receiver/outlet controls in the web app. The bridge listens
only on `127.0.0.1:15335`; it uses `@neurodevs/node-lsl` for outgoing markers
and `node-labstreaminglayer` for incoming markers.

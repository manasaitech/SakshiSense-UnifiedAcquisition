# Changelog

All notable changes to SakshiSense Unified Acquisition are documented here.

## [1.1.0] - 2026-09-02

### Interface and workflow

- Reworked the application theme, cards, controls, spacing, and acquisition
  hierarchy for a clearer research-session workflow.
- Rebuilt the ring and microphone panel to adapt cleanly across desktop,
  laptop, tablet, and mobile widths without clipped or hidden controls.
- Made the laptop/mobile microphone selector permanently visible, including
  before permission is granted or a device is discovered.
- Added explicit microphone permission, refresh, selection, disconnect, live
  level, recording-format, and failure states.
- Added a prominent mobile action button for starting acquisition, beginning a
  recording, and stopping a recording without opening the control drawer.
- Removed rigid panel heights that hid audio controls and signals on compact
  screens.
- Clarified that SakshiSense onboard-microphone telemetry contains RMS, peak,
  zero-crossing, and sample-count features rather than playable waveform data.

### Audio acquisition

- Fixed shared recorder notifications so microphone state and live amplitude
  update both the setup screen and the active collector screen.
- Added Android/iOS microphone permission requests alongside Bluetooth access.
- Automatically discovers native microphone inputs while retaining the
  browser-required user gesture for Web microphone permission.
- Verifies WAV encoder support before starting a recording and reports a
  focused error while allowing the remaining research streams to continue.
- Records laptop/mobile microphones as 48 kHz, mono WAV files with raw capture
  options (automatic gain, echo cancellation, and noise suppression disabled).
- Fixed Web WAV download reliability by delaying Blob URL cleanup, including
  compatibility with mobile Safari download behavior.
- Preserved separate CSV export for the ring's onboard sound-feature packets.

### PPG analysis

- Replaced the previous global-threshold peak detector with a
  sampling-rate-independent signal-processing pipeline informed by the
  original Sakshi Ring application.
- Added drift removal, two-stage smoothing, robust median/MAD normalization,
  adaptive prominence detection, sub-sample peak interpolation, and automatic
  support for either reflective-PPG polarity.
- Added RR-interval cleanup and consistency scoring before calculating heart
  rate and RMSSD.
- Added contact, clipping, packet-timing, signal-dynamic, and coverage quality
  gates; unreliable HR, RMSSD, and SpO2 estimates are withheld rather than
  displayed as plausible measurements.
- Added visible PPG quality labels and scores alongside HR, SpO2, and RMSSD.
- Expanded the retained PPG window to 30 seconds while limiting the plotted
  preview to recent samples for responsive rendering.
- Added synthetic normal/inverted-polarity and absent-contact regression tests.

### Distribution and validation

- Added a public, tag-driven GitHub Release workflow for Android APK, Windows
  portable ZIP and installer, macOS application ZIP, and Web application ZIP.
- Refreshed locally stored Android and macOS release artifacts.
- Verified the release with Flutter static analysis, unit/widget tests, Web,
  Android, and macOS builds; GitHub-hosted Windows builds also pass.
- No firmware changes are included in this release.

### Hardware limitation

- The current ring firmware sends onboard microphone features only. A genuine
  onboard-microphone WAV or MP3 cannot be reconstructed in the app without a
  future firmware protocol that transmits waveform samples.

[1.1.0]: https://github.com/manasaitech/SakshiSense-UnifiedAcquisition/releases/tag/v1.1.0

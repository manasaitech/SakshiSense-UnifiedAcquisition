import 'peripheral_recorder_stub.dart'
    if (dart.library.io) 'peripheral_recorder_io.dart'
    if (dart.library.html) 'peripheral_recorder_web.dart';
export 'peripheral_recorder_base.dart';

import 'peripheral_recorder_base.dart';

PeripheralRecorder createPeripheralRecorder(
        {required void Function() onChange}) =>
    buildPeripheralRecorder(onChange: onChange);

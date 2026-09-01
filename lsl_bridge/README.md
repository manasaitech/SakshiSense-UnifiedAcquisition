# Local browser-to-LSL bridge

Browsers cannot open native LSL UDP/TCP sockets. This helper accepts markers
from the Flutter web app over localhost WebSocket and publishes them to LSL.
It also resolves LSL marker streams and forwards incoming samples to the app.

Install native `liblsl`, then run:

```sh
npm install
npm start
```

The bridge listens only on `127.0.0.1:15335`. The web app connects when either
LSL receiver or outlet is enabled. `@neurodevs/node-lsl` provides the outlet;
`node-labstreaminglayer` provides the inlet because the former does not yet
support receiving streams.

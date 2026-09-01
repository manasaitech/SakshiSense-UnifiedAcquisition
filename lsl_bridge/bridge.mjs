import { LslStreamOutlet } from '@neurodevs/node-lsl'
import { WebSocketServer } from 'ws'
import { resolveByProp, StreamInlet } from 'node-labstreaminglayer'

const port = Number(process.env.SAKSHI_LSL_BRIDGE_PORT || 15335)
const sourceId = `sakshisense-web-${Date.now()}`
const outlet = await LslStreamOutlet.Create({
  name: 'UnifiedMarkersString',
  type: 'Markers',
  sourceId,
  channelNames: ['Marker'],
  channelFormat: 'string',
  sampleRateHz: 0,
  chunkSize: 1,
})

const clients = new Set()
const inlets = new Map()
const server = new WebSocketServer({ host: '127.0.0.1', port })

function send(socket, payload) {
  if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(payload))
}

server.on('connection', socket => {
  const state = { receive: false, outlet: false }
  clients.add({ socket, state })
  send(socket, { type: 'status', message: 'Local LSL bridge connected' })
  socket.on('message', raw => {
    try {
      const message = JSON.parse(raw.toString())
      if (message.type === 'configure') {
        state.receive = Boolean(message.receive)
        state.outlet = Boolean(message.outlet)
      } else if (message.type === 'marker' && state.outlet) {
        outlet.pushSample([String(message.value)])
      }
    } catch (error) {
      send(socket, { type: 'status', message: `Bridge error: ${error.message}` })
    }
  })
  socket.on('close', () => {
    for (const client of clients) {
      if (client.socket === socket) clients.delete(client)
    }
  })
})

setInterval(() => {
  try {
    const streams = resolveByProp('type', 'Markers', 1, 0.05)
    for (const info of streams) {
      const key = `${info.sourceId?.() || ''}|${info.name?.() || ''}`
      if (key.includes(sourceId) || inlets.has(key)) continue
      const inlet = new StreamInlet(info)
      inlet.openStream(0.1)
      inlets.set(key, inlet)
    }
    for (const [key, inlet] of inlets) {
      try {
        const [sample, timestamp] = inlet.pullSample(0)
        if (!sample?.length) continue
        for (const client of clients) {
          if (client.state.receive) send(client.socket, {
            type: 'marker',
            value: sample[0],
            source: key,
            lsl_timestamp: timestamp,
          })
        }
      } catch (_) {
        inlets.delete(key)
      }
    }
  } catch (_) {}
}, 20)

console.log(`SakshiSense LSL bridge listening on ws://127.0.0.1:${port}`)

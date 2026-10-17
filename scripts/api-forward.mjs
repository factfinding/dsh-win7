// Lets an offline Win7 test VM reach the DeepSeek API and nothing else.
// The VM has only a host-only network adapter and maps api.deepseek.com to this host in its hosts file.
// Every connection accepted here is relayed byte for byte to api.deepseek.com:443, whatever the VM asks for,
// so no other destination is reachable; TLS stays end to end between DSH and DeepSeek (nothing is decrypted).
// Usage: node api-forward.mjs [listen address, default 192.168.40.1 = VMnet1] [listen port, default 443]
import net from 'node:net'

const listenHost = process.argv[2] ?? '192.168.40.1'
const listenPort = Number(process.argv[3] ?? 443)
const target = { host: 'api.deepseek.com', port: 443 }
const stamp = () => new Date().toLocaleTimeString('zh-CN', { hour12: false })

const server = net.createServer((client) => {
  const from = `${client.remoteAddress}:${client.remotePort}`
  const started = Date.now()
  let up = 0
  let down = 0
  const upstream = net.connect(target)
  client.on('data', (chunk) => { up += chunk.length })
  upstream.on('data', (chunk) => { down += chunk.length })
  client.pipe(upstream)
  upstream.pipe(client)
  let reported = false
  const close = (reason) => {
    if (reported) return
    reported = true
    console.log(`${stamp()} ${from} -> ${target.host}  up ${up} B, down ${down} B, ${Date.now() - started} ms${reason ? `  (${reason})` : ''}`)
    client.destroy()
    upstream.destroy()
  }
  client.on('error', (error) => close(`client: ${error.code ?? error.message}`))
  upstream.on('error', (error) => close(`upstream: ${error.code ?? error.message}`))
  client.on('close', () => close())
  upstream.on('close', () => close())
})

server.on('error', (error) => {
  console.error(`cannot listen on ${listenHost}:${listenPort}: ${error.message}`)
  process.exit(1)
})
server.listen(listenPort, listenHost, () => {
  console.log(`${stamp()} forwarding ${listenHost}:${listenPort} -> ${target.host}:${target.port} (Ctrl+C to stop)`)
})

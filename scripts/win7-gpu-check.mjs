// Reports whether DeepSeek Harness Desktop renders with the GPU on this machine: the GPU devices and
// the "Graphics Feature Status" table chrome://gpu shows, read through the DevTools protocol
// (SystemInfo.getInfo). Desktop must be running with --remote-debugging-port=<port>;
// win7-gpu-check.cmd starts it that way and runs this script with Desktop's own Node.
// Usage: node win7-gpu-check.mjs [port]
const port = process.argv[2] ?? '9333'

let browser
try {
  browser = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json()
} catch {
  console.error(`No DevTools endpoint on port ${port}. Quit Desktop completely (tray icon > Quit) and run again:`)
  console.error('a Desktop that is already running ignores --remote-debugging-port.')
  process.exit(1)
}

const socket = new WebSocket(browser.webSocketDebuggerUrl)
const info = await new Promise((resolve, reject) => {
  socket.onopen = () => { socket.send(JSON.stringify({ id: 1, method: 'SystemInfo.getInfo' })) }
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data)
    if (message.id !== 1) return
    if (message.error === undefined) resolve(message.result)
    else reject(new Error(message.error.message))
  }
  socket.onerror = () => { reject(new Error('DevTools connection failed')) }
})
socket.close()

const hex = (value) => `0x${value.toString(16).padStart(4, '0')}`
const words = (...parts) => parts.filter((part) => part !== '').join(' ')
console.log(`Browser: ${browser.Browser}`)
for (const device of info.gpu.devices) {
  console.log(`GPU device: ${words(`${hex(device.vendorId)}:${hex(device.deviceId)}`, device.vendorString, device.deviceString)}`
    + `, driver ${words(device.driverVendor, device.driverVersion)}`)
}
for (const [name, value] of Object.entries(info.gpu.auxAttributes)) {
  if (/renderer|implementation|direct.?composition/iu.test(name)) console.log(`${name}: ${value}`)
}
console.log('Graphics Feature Status:')
for (const [feature, status] of Object.entries(info.gpu.featureStatus)) console.log(`  ${feature.padEnd(36)} ${status}`)

// GPU compositing is what "hardware acceleration" means for the window; the rest follow from it.
const compositing = info.gpu.featureStatus.gpu_compositing
console.log(compositing?.startsWith('enabled')
  ? 'RESULT: GPU acceleration is ON'
  : `RESULT: GPU acceleration is OFF, software rendering (gpu_compositing: ${compositing})`)

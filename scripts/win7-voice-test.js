// Voice input check for Windows 7: loads sherpa-onnx the way DSH's SenseVoice worker does
// (deepseek-harness/packages/experimental/speech-to-text-sensevoice/src/inference.ts, default config)
// and transcribes WAV files. Prints one PASS/FAIL line per step.
// Run it from a directory whose node_modules has sherpa-onnx-node and sherpa-onnx-win-x64, with
// DSH's Electron in Node mode (as the worker runs) or a Node.js build:
//   set ELECTRON_RUN_AS_NODE=1
//   "<DSH install dir>\DeepSeek Harness.exe" win7-voice-test.js <models dir> <16 kHz mono PCM16 wav>...
// <models dir> holds sensevoice-onnx\model.int8.onnx, sensevoice-onnx\tokens.txt and silero\silero_vad.onnx,
// the layout under %USERPROFILE%\.dsh\speech-to-text\sensevoice\models.
'use strict'
const { readFileSync } = require('node:fs')
const { join } = require('node:path')

const [models, ...wavs] = process.argv.slice(2)
let failures = 0
function step(name, run) {
  try {
    const detail = run()
    console.log(`PASS ${name}${detail === undefined ? '' : `: ${detail}`}`)
    return true
  } catch (error) {
    failures++
    console.log(`FAIL ${name}: ${error && error.stack || error}`)
    return false
  }
}

// 16-bit mono PCM samples of a RIFF/WAVE file, scaled to [-1, 1) as the worker does.
function readPcm16(path) {
  const data = readFileSync(path)
  if (data.toString('ascii', 0, 4) !== 'RIFF' || data.toString('ascii', 8, 12) !== 'WAVE') throw new Error(`${path} is not a WAV file`)
  let format
  for (let offset = 12; offset + 8 <= data.length;) {
    const id = data.toString('ascii', offset, offset + 4), size = data.readUInt32LE(offset + 4), body = offset + 8
    if (id === 'fmt ') format = { channels: data.readUInt16LE(body + 2), rate: data.readUInt32LE(body + 4), bits: data.readUInt16LE(body + 14) }
    if (id === 'data') {
      if (!format || format.channels !== 1 || format.rate !== 16000 || format.bits !== 16) throw new Error(`${path}: need 16 kHz mono PCM16, got ${JSON.stringify(format)}`)
      const pcm = new DataView(data.buffer, data.byteOffset + body, Math.min(size, data.length - body))
      return Float32Array.from({ length: pcm.byteLength >> 1 }, (_, i) => pcm.getInt16(i * 2, true) / 32768)
    }
    offset = body + size + (size & 1)
  }
  throw new Error(`${path} has no data chunk`)
}

console.log(`runtime: ${process.versions.electron ? `Electron ${process.versions.electron} (Node ${process.version})` : `Node ${process.version}`} on ${require('node:os').release()}`)
let sherpa, recognizer, detector
step('load sherpa-onnx-node', () => { sherpa = require('sherpa-onnx-node'); return require.resolve('sherpa-onnx-node') })
const nativeConfig = {
  featConfig: { sampleRate: 16000, featureDim: 80 },
  modelConfig: { senseVoice: { model: join(models, 'sensevoice-onnx', 'model.int8.onnx'), language: 'auto', useInverseTextNormalization: 1 },
    tokens: join(models, 'sensevoice-onnx', 'tokens.txt'), numThreads: 2, provider: 'cpu', debug: 0 },
}
if (sherpa) step('create SenseVoice recognizer', () => {
  const started = Date.now()
  recognizer = new sherpa.OfflineRecognizer(nativeConfig)
  return `${Date.now() - started} ms`
})
if (sherpa) step('create Silero VAD', () => {
  detector = new sherpa.Vad({
    sileroVad: { model: join(models, 'silero', 'silero_vad.onnx'), threshold: 0.5, minSilenceDuration: 0.5,
      minSpeechDuration: 0.25, maxSpeechDuration: 30, windowSize: 512 },
    sampleRate: 16000, numThreads: 2, provider: 'cpu', debug: 0,
  }, 30 + 0.5 + 1)
})
for (const wav of recognizer && detector ? wavs : []) {
  step(`transcribe ${wav}`, () => {
    const samples = readPcm16(wav)
    recognizer.setConfig(nativeConfig)
    detector.reset()
    const started = performance.now(), texts = []
    const drain = () => {
      while (!detector.isEmpty()) {
        const segment = detector.front(false)
        const stream = recognizer.createStream()
        stream.acceptWaveform({ sampleRate: 16000, samples: segment.samples })
        recognizer.decode(stream)
        texts.push(recognizer.getResult(stream).text.trim())
        detector.pop()
      }
    }
    for (let offset = 0; offset < samples.length; offset += 512) {
      detector.acceptWaveform(samples.subarray(offset, offset + 512))
      drain()
    }
    detector.flush(); drain()
    const text = texts.filter(Boolean).join(' ').trim()
    if (!text) throw new Error('empty transcript')
    return `${(samples.length / 16000).toFixed(1)} s audio in ${((performance.now() - started) / 1000).toFixed(1)} s: ${text}`
  })
}
console.log(failures === 0 ? 'ALL PASS' : `${failures} FAILED`)
process.exitCode = failures === 0 ? 0 : 1
